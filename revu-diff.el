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
Nil when git does not know the object as a commit -- a Revision rebased
away is gone.  The caller falls back to the id it has.

The abbreviation is git\\='s own, so it is the length a log shows the object
at, and one call answers for both halves."
  (let ((result (revu-diff--call
                 root (list "log" "-1" "--no-decorate" "--format=%h %s"
                            (concat revision "^{commit}")))))
    (when (eq (car result) 0)
      (let ((described (string-trim (cdr result))))
        (unless (string-empty-p described)
          described)))))

(defun revu-diff-revision-names (root)
  "Return the local branch and tag names the repository at ROOT carries.
These are the Revisions a reviewer picks one of by name, and the whole
of what revu offers for completion.  Remote branches are left out: they
can still be written, and offering every ref a fetch dragged in buries
the handful that are being worked on."
  (split-string (revu-diff--git root "for-each-ref" "--format=%(refname:short)"
                                "refs/heads" "refs/tags")
                "\n" t))

(defun revu-diff--pathspecs (paths)
  "Return the `git diff\\=' arguments limiting a diff to PATHS, or nil.
The pathspecs come last, behind the `--\\=' that keeps git from reading one
of them as a Revision."
  (when (> (length paths) 0)
    (cons "--" (append paths nil))))

(defconst revu-diff--untracked-exclude "--exclude=/.revu/"
  "The `git ls-files' argument keeping a Review from listing its own state.
The Review\\='s own Sidecar and Export are written under
`revu-directory-name' -- spelled out here because that lives a layer
above this file -- and a Review that listed the file it is being written
into would carry a file whose content changed with every Annotation.
The exclusion is anchored to the root, so a directory of that name
someone keeps deeper in the tree is theirs.")

(defun revu-diff--untracked-paths (root paths)
  "Return the untracked files of the worktree at ROOT, in git\\='s order.
Ignored files are not among them: `--exclude-standard' is what makes
`.gitignore' mean here what it means everywhere else.  PATHS, when
given, is the Narrowing, and limits these exactly as it limits the
tracked half of the Source.

An entry ending in a slash is a repository nested in this one, which git
reports whole rather than descending into.  It is dropped: there is no
diff of a directory to take, and asking for one would fail the Source
the reviewer asked for over a repository that is not theirs."
  (seq-remove
   (lambda (path) (string-suffix-p "/" path))
   (split-string (apply #'revu-diff--git root "ls-files" "--others"
                        "--exclude-standard" revu-diff--untracked-exclude "-z"
                        (revu-diff--pathspecs paths))
                 "\0" t)))

(defun revu-diff--untracked-text (root path)
  "Return the all-added diff of the untracked file PATH under ROOT.
`git diff --no-index' against the null device writes the file as the
added file it is, with the same options the rest of the Source is cut
with -- so its hunk carries the content lines it will carry once the
file is staged, and a Reviewed mark taken over it holds across the `git
add' unless a clean filter rewrites the bytes on the way into the
index.  Git reports a difference by exiting 1, which is the whole point
of the call; anything above that is a failure like any other."
  (let ((result (revu-diff--call
                 root (append (list "diff" "--no-index")
                              revu-diff--diff-options
                              (list "--" null-device path)))))
    (unless (memq (car result) '(0 1))
      (signal 'revu-git-failed
              (list (format "git diff of the untracked %s failed in %s: %s"
                            path root (string-trim (cdr result))))))
    (cdr result)))

(defun revu-diff-worktree-text (root revision &optional paths)
  "Return the unified diff of the worktree at ROOT against REVISION.
Everything uncommitted is here, staged or not: the reviewer asking for
the worktree is asking to read what they are about to commit, and a
change that has already been staged is still one of them.  Diffing
against the Revision the Review records is also what lets a removed line
re-locate in the base blob (ADR-0003).  PATHS, when given, is the
Narrowing the diff is limited to.

An untracked file is here too, as an all-added file appended after the
diff git gives (ADR-0005\\='s untracked-files amendment).  `git diff' shows
no file git does not track, and forgetting to stage a new file is the
common case, so a Source promising everything the worktree carries has
to go and ask for those separately.  A path the diff already names is
left to the diff: a file deleted from the index and written again is
both, and rendering it twice would leave its Reviewed marks and its
folds unable to say which of the two they meant."
  (let* ((diffed (apply #'revu-diff--git root "diff" revision
                        (append revu-diff--diff-options
                                (revu-diff--pathspecs paths))))
         (spoken-for (revu-diff--diffed-paths diffed)))
    (apply #'concat diffed
           (mapcar (lambda (path) (revu-diff--untracked-text root path))
                   (seq-remove (lambda (path) (member path spoken-for))
                               (revu-diff--untracked-paths root paths))))))

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
whether or not it happens to sit inside a repository (ADR-0004).

A patch is asked nothing at all: it is immutable and was not necessarily
taken here, so its every path is present.  A diff from another machine
names files this repository has never held, and reading those as deleted
would orphan the Annotations on a Source that cannot change."
  (if (equal (revu-source-kind source) "patch")
      (mapcar (lambda (path) (cons path 'present)) paths)
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
              paths))))

;;;; Parsing

(defconst revu-diff--file-header-regexp
  "\\`diff --git a/\\(.*\\) b/\\(.*\\)\\'"
  "Regexp matching the `diff --git' line that opens a file's diff.")

(defun revu-diff--diffed-paths (text)
  "Return the paths the unified diff TEXT already names.
Read off the `diff --git' headers rather than by parsing: the caller
only needs to know which paths are spoken for, and a hunk line can never
be mistaken for a header because every one of them opens with `+', `-',
a space or a backslash."
  (let ((paths nil))
    (dolist (line (split-string text "\n") (nreverse paths))
      (when (string-match revu-diff--file-header-regexp line)
        (push (match-string 2 line) paths)))))

(defconst revu-diff--hunk-header-regexp
  "\\`@@ -\\([0-9]+\\)\\(?:,[0-9]+\\)? \\+\\([0-9]+\\)\\(?:,[0-9]+\\)? @@"
  "Regexp matching the `@@' line that opens a hunk.")

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
