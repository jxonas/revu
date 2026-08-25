;;; revu-diff.el --- Generate and parse the unified diffs revu reviews  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Jonas Rodrigues

;; Author: Jonas Rodrigues

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; The Source side of revu: the git invocations that produce a unified
;; diff, and the parser that turns one into the files, hunks and lines
;; the review buffer renders.
;;
;; revu parses diffs itself rather than borrowing another package's
;; washer (ADR-0008), so the shape the renderer sees is revu's own: a
;; file carries its path and the hunks under it, a hunk carries its `@@'
;; header and its lines, and a line carries its Origin, its number and
;; the text as the diff wrote it.  Origin decides which file the number
;; counts in: a removal is numbered in the old file, everything else in
;; the new.
;;
;; Every git command runs with the configuration that could change the
;; shape of a diff turned off, so what revu parses does not depend on the
;; reviewer's git configuration.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'revu-record)

(define-error 'revu-git-failed
  "A git command revu ran failed"
  'error)

(cl-defstruct (revu-diff-file (:constructor revu-diff-file-create)
                              (:copier nil))
  "One file of a parsed diff.
PATH is the file as the diff leaves it and OLD-PATH as it found it; they
differ only for a rename.  STATUS is `modified', `added', `deleted' or
`renamed', and HUNKS are the file's hunks, in diff order -- a rename with
no edits and a mode change both have none.

PLAIN says the file is a plain file under review rather than one the
diff parser built, and CONTENT is what it holds, verbatim -- nil for a
plain file that has since been deleted, which is why PLAIN and not
CONTENT is what tells the two apart.  A plain file's Reviewed mark is
taken over exactly these bytes (ADR-0009), which is why they are kept
rather than re-joined from the lines."
  path old-path status hunks plain content)

(cl-defstruct (revu-diff-hunk (:constructor revu-diff-hunk-create)
                              (:copier nil))
  "One hunk of a parsed diff.
HEADER is the `@@' line verbatim, OLD-START and NEW-START the first line
the hunk covers on each side, and LINES a list of (ORIGIN NUMBER TEXT):
the line's Origin, its number in the file that Origin counts in, and the
diff's text for it, leading origin character included."
  header old-start new-start lines)

;;;; Running git

(defconst revu-diff--git-configuration
  '("-c" "diff.noprefix=false"
    "-c" "diff.mnemonicPrefix=false"
    "-c" "diff.external="
    "-c" "core.quotepath=false")
  "Git configuration that pins the shape of the diffs revu parses.
A reviewer who has turned path prefixes off, or an external diff on,
still gets the unified diff this parser reads.")

(defconst revu-diff--diff-options
  '("--no-color" "--no-ext-diff" "--unified=3")
  "Options every `git diff' revu runs carries.")

(defun revu-diff--call (root arguments)
  "Run git with ARGUMENTS in ROOT.
Return a cons of the exit status and the output."
  (with-temp-buffer
    (let* ((default-directory (file-name-as-directory root))
           (status (apply #'call-process "git" nil t nil
                          (append '("--no-pager")
                                  revu-diff--git-configuration
                                  arguments))))
      (cons status (buffer-string)))))

(defun revu-diff--git (root &rest arguments)
  "Run git with ARGUMENTS in ROOT and return its output.
Signal `revu-git-failed' when git does, quoting what it said: a review
opened over a diff git refused to produce would be a review of nothing."
  (let ((result (revu-diff--call root arguments)))
    (unless (eq (car result) 0)
      (signal 'revu-git-failed
              (list (format "git %s failed in %s: %s"
                            (string-join arguments " ") root
                            (string-trim (cdr result))))))
    (cdr result)))

(defun revu-diff-head-revision (root)
  "Return the Revision HEAD names in the repository at ROOT."
  (string-trim (revu-diff--git root "rev-parse" "HEAD")))

(defun revu-diff-resolve-revision (root revision)
  "Return the object REVISION names in ROOT, or nil when it names none."
  (let ((result (revu-diff--call
                 root (list "rev-parse" "--verify" "--quiet"
                            (concat revision "^{}")))))
    (when (eq (car result) 0)
      (string-trim (cdr result)))))

(defun revu-diff-merge-base (root a b)
  "Return the commit where Revisions A and B last diverged in ROOT.
Return nil when they share no history, or when either names nothing.
This is what a three-dot range means, and a Source records the commit it
resolves to rather than the notation it was written with."
  (let ((result (revu-diff--call root (list "merge-base" a b))))
    (when (eq (car result) 0)
      (string-trim (cdr result)))))

(defun revu-diff-abbreviate-revision (root revision)
  "Return REVISION abbreviated as far as ROOT still resolves it.
This is git's own abbreviation, which is the length a log shows an
object id at.  Return nil when git will not abbreviate it."
  (let ((result (revu-diff--call root (list "rev-parse" "--short" revision))))
    (when (eq (car result) 0)
      (string-trim (cdr result)))))

(defun revu-diff-describe-revision (root revision)
  "Return REVISION as its abbreviated id and subject, or nil when ROOT has none.
This is how a Revision is named to the reviewer -- \"abc1234 Add the
header section\" -- rather than as the forty characters the record holds.
Nil when git does not know the object as a commit: a Revision rebased
away is gone, and a pasted diff\\='s `index\\=' header names blobs, which are
objects and not commits.  The caller falls back to the id it has.

The abbreviation is git\\='s own, so it is the length a log shows the object
at, and one call answers for both halves."
  (let ((result (revu-diff--call
                 root (list "log" "-1" "--no-decorate" "--format=%h %s"
                            (concat revision "^{commit}")))))
    (when (eq (car result) 0)
      (let ((described (string-trim (cdr result))))
        (unless (string-empty-p described)
          described)))))

(defun revu-diff-object-exists-p (root object)
  "Return non-nil when OBJECT names an object present in ROOT.
A blob is an object but not a Revision, so this is the question a diff's
`index' header can answer."
  (eq (car (revu-diff--call root (list "cat-file" "-e" object))) 0))

(defun revu-diff--pathspecs (paths)
  "Return the `git diff\\=' arguments limiting a diff to PATHS, or nil.
The pathspecs come last, behind the `--\\=' that keeps git from reading one
of them as a Revision."
  (when (> (length paths) 0)
    (cons "--" (append paths nil))))

(defun revu-diff-worktree-text (root revision &optional paths)
  "Return the unified diff of the worktree at ROOT against REVISION.
Everything uncommitted is here, staged or not: the reviewer asking for
the worktree is asking to read what they are about to commit, and a
change that has already been staged is still one of them.  Diffing
against the Revision the Review records is also what lets a removed line
re-locate in the base blob (ADR-0003).  PATHS, when given, is the
Narrowing the diff is limited to."
  (apply #'revu-diff--git root "diff" revision
         (append revu-diff--diff-options (revu-diff--pathspecs paths))))

(defun revu-diff-staged-text (root &optional paths)
  "Return the unified diff of the index at ROOT against HEAD.
PATHS, when given, is the Narrowing the diff is limited to."
  (apply #'revu-diff--git root "diff" "--cached"
         (append revu-diff--diff-options (revu-diff--pathspecs paths))))

(defun revu-diff-range-text (root base head &optional paths)
  "Return the unified diff between Revisions BASE and HEAD in ROOT.
PATHS, when given, is the Narrowing the diff is limited to."
  (apply #'revu-diff--git root "diff"
         (append revu-diff--diff-options
                 (list (format "%s..%s" base head))
                 (revu-diff--pathspecs paths))))

(defun revu-diff-show-file (root revision path)
  "Return the content of PATH at REVISION in ROOT, or nil when it has none.
This is where a line the diff removed still lives: it is gone from the
worktree, so an Anchor on it re-locates inside the base blob (ADR-0003).
PATH is the Target's recorded path, which a later rename never rewrites."
  (let ((result (revu-diff--call root (list "show" (format "%s:%s" revision
                                                           path)))))
    (when (eq (car result) 0)
      (cdr result))))

;;;; Path resolution

(defun revu-diff--name-status-arguments (source)
  "Return the `git diff' arguments naming what SOURCE was taken over.
ADR-0004 writes this as `<base>..worktree' for every git Source, and it
means the worktree literally: the question is what became of the path by
now, not what the Source's own two ends said about it.  A range whose
head is long past still has its files renamed under it, and asking
`base..head' would call those files deleted."
  (let ((base (revu-source-base source)))
    (and base (member (revu-source-kind source) '("worktree" "staged" "range"))
         (list base))))

(defun revu-diff--renames (root source)
  "Return what became of the paths SOURCE spans in ROOT, as an alist.
One `git diff -M --name-status' call answers for every path at once, so
a load costs one git invocation however many Annotations went missing."
  (let ((arguments (revu-diff--name-status-arguments source))
        (renames nil))
    (when arguments
      (dolist (line (split-string
                     (apply #'revu-diff--git root "diff" "-M" "--name-status"
                            arguments)
                     "\n" t))
        (let ((fields (split-string line "\t")))
          (pcase (substring (car fields) 0 1)
            ("R" (push (cons (nth 1 fields) (cons 'renamed (nth 2 fields)))
                       renames))
            ("D" (push (cons (nth 1 fields) 'deleted) renames))))))
    renames))

(defun revu-diff-resolve-paths (root source paths)
  "Return where each of PATHS is now under ROOT, given SOURCE, as an alist.
A resolution is `present', `deleted', or a cons of `renamed' and the
path the file has now.  It is derived on every load and never persisted,
because the answer changes the moment somebody runs git.

A plain-file Review never follows a rename: a missing file is deleted,
whether or not it happens to sit inside a repository (ADR-0004)."
  (let* ((missing (seq-remove
                   (lambda (path)
                     (file-exists-p (expand-file-name path root)))
                   paths))
         (renames (when (and missing
                             (not (equal (revu-source-kind source) "file")))
                    (revu-diff--renames root source))))
    (mapcar (lambda (path)
              (cons path
                    (cond
                     ((not (member path missing)) 'present)
                     ((alist-get path renames nil nil #'equal))
                     (t 'deleted))))
            paths)))

;;;; Parsing

(defconst revu-diff--file-header-regexp
  "\\`diff --git a/\\(.*\\) b/\\(.*\\)\\'"
  "Regexp matching the `diff --git' line that opens a file's diff.")

(defconst revu-diff--hunk-header-regexp
  "\\`@@ -\\([0-9]+\\)\\(?:,[0-9]+\\)? \\+\\([0-9]+\\)\\(?:,[0-9]+\\)? @@"
  "Regexp matching the `@@' line that opens a hunk.")

(defconst revu-diff--index-regexp
  "\\`index \\([0-9a-f]+\\)\\.\\.\\([0-9a-f]+\\)"
  "Regexp matching the `index' line naming the blobs a file's diff spans.")

(defun revu-diff-buffer-revisions (text)
  "Return the Revisions the pasted diff TEXT names, as a cons, or nil.
The pair comes from the first `index' header, which is the only place a
unified diff records what it was taken between."
  (let ((found nil))
    (dolist (line (split-string text "\n"))
      (when (and (null found) (string-match revu-diff--index-regexp line))
        (setq found (cons (match-string 1 line) (match-string 2 line)))))
    found))

(defun revu-diff-buffer-objects (text)
  "Return every object the `index' headers of the pasted diff TEXT name.
A diff carries one header per file, and a diff assembled elsewhere can
name objects this repository has for its first file and not its tenth.
Refusing on the first header alone would accept exactly that diff."
  (let ((objects nil))
    (dolist (line (split-string text "\n"))
      (when (string-match revu-diff--index-regexp line)
        (push (match-string 1 line) objects)
        (push (match-string 2 line) objects)))
    (nreverse (delete-dups objects))))

(defun revu-diff-parse (text)
  "Return the files the unified diff TEXT describes.
Each is a `revu-diff-file'.  A file with no hunks -- a pure rename, a
deletion recorded by header alone -- is kept: the reviewer must still see
that it changed."
  (let ((files nil) (path nil) (old-path nil) (status nil)
        (hunks nil) (hunk nil) (lines nil) (old 0) (new 0))
    (cl-labels
        ((close-hunk ()
           (when hunk
             (setf (revu-diff-hunk-lines hunk) (nreverse lines))
             (push hunk hunks))
           (setq hunk nil lines nil))
         (close-file ()
           (close-hunk)
           (when path
             (push (revu-diff-file-create :path path
                                          :old-path (or old-path path)
                                          :status (or status "modified")
                                          :hunks (nreverse hunks))
                   files))
           (setq path nil old-path nil status nil hunks nil)))
      ;; The newline that ends the diff closes its last line; it does not
      ;; open another one.
      (dolist (line (split-string (replace-regexp-in-string "\n\\'" "" text)
                                  "\n"))
        (cond
         ((string-match revu-diff--file-header-regexp line)
          (close-file)
          (setq old-path (match-string 1 line)
                path (match-string 2 line)))
         ((null path) nil)
         ((string-prefix-p "new file mode" line) (setq status "added"))
         ((string-prefix-p "deleted file mode" line) (setq status "deleted"))
         ((string-prefix-p "rename from " line)
          (setq status "renamed"
                old-path (substring line (length "rename from "))))
         ((string-prefix-p "rename to " line)
          (setq status "renamed"
                path (substring line (length "rename to "))))
         ((string-match revu-diff--hunk-header-regexp line)
          (close-hunk)
          (setq old (string-to-number (match-string 1 line))
                new (string-to-number (match-string 2 line))
                hunk (revu-diff-hunk-create :header line
                                            :old-start old
                                            :new-start new
                                            :lines nil)))
         ((null hunk) nil)
         ((string-prefix-p "\\" line) nil)   ; "\ No newline at end of file".
         ((string-prefix-p "+" line)
          (push (list "added" new line) lines)
          (setq new (1+ new)))
         ((string-prefix-p "-" line)
          (push (list "removed" old line) lines)
          (setq old (1+ old)))
         ((or (string-prefix-p " " line) (string-empty-p line))
          ;; git writes a context line as a space and the text; an empty
          ;; context line reaches us as the empty string.
          (push (list "context" new (if (string-empty-p line) " " line)) lines)
          (setq old (1+ old) new (1+ new)))))
      (close-file))
    (nreverse files)))

(provide 'revu-diff)
;;; revu-diff.el ends here
