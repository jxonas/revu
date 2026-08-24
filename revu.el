;;; revu.el --- Review diffs and files with exportable annotations  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Jonas Rodrigues

;; Author: Jonas Rodrigues
;; Version: 0.1.0
;; Package-Requires: ((emacs "30.2") (magit-section "4.3.0") (transient "0.13.0"))
;; Keywords: tools, vc
;; URL: https://github.com/jonasrodrigues/revu

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

;; revu reviews a Source -- a diff or a plain file -- in a dedicated
;; read-only buffer, and persists the reviewer's Annotations as a
;; Sidecar: one JSON file per Review under `<project-root>/.revu/'.
;; The Sidecar is the review state itself, and the record AI agents and
;; scripts read.
;;
;; This file carries the package entry points and the helpers that
;; locate the project root and the Sidecar directory.

;;; Code:

(require 'project)
(require 'revu-anchor)
(require 'revu-annotate)
(require 'revu-diff)
(require 'revu-export)
(require 'revu-keymap)
(require 'revu-record)
(require 'revu-render)
(require 'revu-reviewed)
(require 'revu-sidecar)

(defgroup revu nil
  "Review diffs and files with exportable annotations."
  :group 'tools
  :prefix "revu-")

(defconst revu-directory-name ".revu"
  "Name of the per-project directory holding Sidecar files.")

(defun revu-project-root (path)
  "Return the root of the project containing PATH, as a directory name.
PATH may name a file or a directory and need not exist.  Signal a
`user-error' when PATH belongs to no project: revu refuses a Source
outside a project root rather than inventing a Sidecar location for it."
  (let* ((expanded (expand-file-name path))
         (directory (file-name-as-directory
                     (if (file-directory-p expanded)
                         expanded
                       (file-name-directory expanded))))
         (project (project-current nil directory)))
    (unless project
      (user-error "No project root for %s; revu reviews files inside a project"
                  path))
    (file-name-as-directory (file-truename (project-root project)))))

(defun revu-sidecar-file-name (name &optional path)
  "Return the Sidecar file that persists the Review called NAME.
The Sidecar lives in the `revu-directory-name' directory of the project
containing PATH, which defaults to `default-directory'.  That directory
is created when it does not exist yet; the Sidecar itself is not.
Signal a `user-error' when PATH belongs to no project."
  (let ((directory (expand-file-name
                    revu-directory-name
                    (revu-project-root (or path default-directory)))))
    (make-directory directory t)
    (expand-file-name (concat name ".json") directory)))

;;;; The review buffer

(defvar-local revu--sidecar nil
  "The Sidecar this review buffer reads and writes its Review through.")

(defvar-local revu--files nil
  "The parsed Source this review buffer renders, as `revu-diff-file's.")

;; `revu-mode-map' is `revu-keymap.el's, and everything that drives a
;; Review is bound there.

(define-derived-mode revu-mode magit-section-mode "Revu"
  "Major mode of the buffer a Source is reviewed in.

The buffer is read-only and is a render of the Review's state: every
command changes the state, writes it to the Sidecar and renders again.
Nothing is edited here, and revu never puts a mode on the reviewer's own
file buffers (ADR-0010)."
  (setq buffer-read-only t))

(defun revu-buffer-name (name)
  "Return the name of the buffer the Review called NAME is reviewed in."
  (format "*revu: %s*" name))

(defun revu-review ()
  "Return the Review the current buffer is reviewing.
Signal a `user-error' outside a review buffer."
  (unless revu--sidecar
    (user-error "Not in a revu review buffer"))
  (revu-sidecar-review revu--sidecar))

(defun revu-render ()
  "Render the current review buffer from the state it carries.
Where each Annotation belongs, and the state of its Anchor, is derived
from today's file content on every render and never persisted."
  (let ((review (revu-review)))
    (revu-render-diff revu--files
                      (revu-reviewed-hidden-p review revu--files)
                      (revu-annotate-placements review default-directory)
                      (revu-reviewed-keep-p review revu--files)
                      (revu-reviewed-state-p review revu--files))))

(defun revu--file-content (file)
  "Return the content of FILE, or nil when there is no such file.
A plain file that has since been deleted reads as nothing, and the
Annotations on it orphan; revu does not go looking for where it went,
because a plain-file Source follows no rename (ADR-0004)."
  (when (file-regular-p file)
    (with-temp-buffer
      (insert-file-contents file)
      (buffer-string))))

(defun revu--plain-file (path content)
  "Return the `revu-diff-file' the plain file at PATH holding CONTENT renders as.
Every line of the file is carried in one hunk, because ADR-0011 renders a
plain file flat: the hunk is the whole file, and the render puts no
section of its own around it.  A line carries no Origin -- there is no
diff for it to belong to a part of -- so the Annotations made on it
record none either.

CONTENT is nil for a file that has since been deleted, which still marks
the file plain: nothing about it is a diff, and the render says so rather
than falling back to naming a change nobody made."
  (let* ((split (split-string (or content "") "\n"))
         ;; A file's last newline ends its last line rather than opening
         ;; another one.  What is left is every line the file has, blank
         ;; ones included: a file holding one empty line has a line, and
         ;; only a file with no content at all has none.
         (lines (if (and content (string-suffix-p "\n" content))
                    (butlast split)
                  split))
         (number 0))
    (revu-diff-file-create
     :path path
     :plain t
     :content content
     :hunks (unless (or (null content) (string-empty-p content))
              (list (revu-diff-hunk-create
                     :header nil
                     :old-start 1
                     :new-start 1
                     :lines (mapcar (lambda (text)
                                      (list nil (setq number (1+ number)) text))
                                    lines)))))))

(defun revu--source-files (source root)
  "Return the files to render for SOURCE, read anew in the repository at ROOT.
This is how a Source is read again on reload: the Review records what it
was taken from, so a diff can always be taken anew and a plain file read
anew.  A Review whose Source was a pasted diff records the Revisions it
spanned, so it is read back from the repository like any other range."
  (pcase (revu-source-kind source)
    ("worktree" (revu-diff-parse
                 (revu-diff-worktree-text root (revu-source-base source))))
    ("staged" (revu-diff-parse (revu-diff-staged-text root)))
    ("range" (revu-diff-parse
              (revu-diff-range-text root
                                    (revu-source-base source)
                                    (revu-source-head source))))
    ("file" (let ((path (revu-source-path source)))
              (list (revu--plain-file
                     path
                     (revu--file-content (expand-file-name path root))))))
    (kind (user-error "Cannot read a %s Source again" kind))))

;;;###autoload
(defun revu-reload ()
  "Read the Sidecar and the Source again, and render the Review anew.
This is the return leg (ADR-0007): an agent answers a `question' by
writing a Reply, and may append Annotations of its own, and this is where
the reviewer sees them.  Both sides are read in one pass, so the
Annotations are re-anchored against the Source as it is now.

Nothing is merged.  A Sidecar this revu cannot read refuses loudly and
names where the trouble is; the buffer keeps the Review it was showing
and the file is left as the agent wrote it, for the reviewer to look at."
  (interactive)
  (let* ((review (revu-review))
         (files (revu--source-files (revu-review-source review)
                                    default-directory)))
    (revu-sidecar-reload revu--sidecar)
    (setq revu--files files)
    (revu-render)
    (message "Reloaded %s" (revu-sidecar-file revu--sidecar))))

;;;###autoload
(defun revu-force-write ()
  "Write this Review over whatever is in the Sidecar now.
The way past the write guard, for when the reviewer has read what an
agent wrote and judges it garbage.  Everything the agent put in the file
is lost, which is why this is a command of its own and not what a blocked
Annotation quietly falls back to."
  (interactive)
  (let ((review (revu-review)))
    (revu-sidecar-force-write revu--sidecar review)
    (revu-render)
    (message "Wrote %s over what was there" (revu-sidecar-file revu--sidecar))))

(defun revu--read-review-name (source)
  "Prompt for the name of the Review over SOURCE, offering the derived one.
The default is derived from the Source, so accepting it a second time
resumes the Review already there rather than starting another."
  (let ((default (revu-review-name-for-source source)))
    (read-string (format "Review name (default %s): " default)
                 nil nil default)))

(defun revu--open (source files name)
  "Open the Review called NAME over SOURCE, rendering FILES.
The Sidecar is resumed when one is already there and written when it is
not; the buffer is reused when the Review is already open.  Return the
review buffer."
  (let* ((root (revu-project-root default-directory))
         (file (revu-sidecar-file-name name root))
         (sidecar (revu-sidecar-open file (revu-review-create name source)))
         (buffer (get-buffer-create (revu-buffer-name name))))
    (with-current-buffer buffer
      (unless (derived-mode-p 'revu-mode)
        (revu-mode))
      (setq default-directory root
            revu--sidecar sidecar
            revu--files files)
      (revu-render))
    (pop-to-buffer buffer)
    buffer))

;;;###autoload
(defun revu-diff-worktree (&optional name)
  "Review everything the worktree carries that HEAD does not.
Staged and unstaged changes alike, because that is what the reviewer is
about to commit.  NAME names the Review; it is prompted for, with the
name derived from the Source offered as the default."
  (interactive)
  (let* ((root (revu-project-root default-directory))
         (revision (revu-diff-head-revision root))
         (source (revu-source-worktree revision))
         (name (or name (revu--read-review-name source))))
    (revu--open source
                (revu-diff-parse (revu-diff-worktree-text root revision))
                name)))

;;;###autoload
(defun revu-diff-staged (&optional name)
  "Review what is staged in the index, against HEAD.
NAME names the Review; it is prompted for, with the name derived from the
Source offered as the default."
  (interactive)
  (let* ((root (revu-project-root default-directory))
         (source (revu-source-staged (revu-diff-head-revision root)))
         (name (or name (revu--read-review-name source))))
    (revu--open source (revu-diff-parse (revu-diff-staged-text root)) name)))

;;;###autoload
(defun revu-diff-range (&optional base head name)
  "Review what the Revisions BASE and HEAD differ by.
NAME names the Review; it is prompted for, with the name derived from the
Revisions as they were typed -- `main..feature', not the commits they
resolve to -- offered as the default.  The Review itself records the
commits, because that is what re-anchoring a removed line needs."
  (interactive)
  (let* ((root (revu-project-root default-directory))
         (base (or base (read-string "Base revision: ")))
         (head (or head (read-string "Head revision: " "HEAD")))
         (name (or name (revu--read-review-name (revu-source-range base head))))
         (source (revu-source-range (revu--resolve root base)
                                    (revu--resolve root head))))
    (revu--open source
                (revu-diff-parse (revu-diff-range-text root base head))
                name)))

(defun revu--resolve (root revision)
  "Return the commit REVISION names in ROOT.
Signal a `user-error' when it names none: a Review that cannot say what
it was taken between cannot re-locate a removed line later."
  (or (revu-diff-resolve-revision root revision)
      (user-error "No such revision in this repository: %s" revision)))

;;;###autoload
(defun revu-diff-buffer (&optional buffer name)
  "Review the unified diff already in BUFFER, which defaults to this one.
NAME names the Review, and is prompted for when it is not given.
The Revisions are read from the diff's own `index' headers, and the
Review is recorded as the range between them.  A diff carrying no such
headers, or naming objects this repository does not have, is refused:
revu will not review a diff it cannot say the provenance of."
  (interactive)
  (let* ((buffer (or buffer (current-buffer)))
         (text (with-current-buffer buffer
                 (buffer-substring-no-properties (point-min) (point-max))))
         (root (revu-project-root default-directory))
         (revisions (revu-diff-buffer-revisions text)))
    (unless revisions
      (user-error "%s carries no diff `index' header naming what it spans"
                  (buffer-name buffer)))
    (dolist (object (revu-diff-buffer-objects text))
      (unless (revu-diff-object-exists-p root object)
        (user-error "%s names %s, which this repository does not have"
                    (buffer-name buffer) object)))
    (let ((source (revu-source-range (car revisions) (cdr revisions))))
      (revu--open source (revu-diff-parse text)
                  (or name (revu--read-review-name source))))))

;;;; Plain files

(defun revu--saved-file (file)
  "Return FILE with the reviewer given the chance to save the buffer on it.
Signal a `user-error' when FILE is nothing revu can review: a buffer
visiting no file at all, or one whose file has never been written.  An
Anchor and a Reviewed mark are both taken over what is on disk, and disk
is what an agent reads, so a Source that is not there is refused rather
than guessed at (ADR-0011)."
  (let ((file (or file buffer-file-name)))
    (unless file
      (user-error "This buffer is visiting no file; revu reviews saved files"))
    (let ((buffer (get-file-buffer file)))
      (when (and buffer (buffer-modified-p buffer)
                 (y-or-n-p (format "Save %s before reviewing it? "
                                   (file-name-nondirectory file))))
        (with-current-buffer buffer (save-buffer)))
      (unless (file-regular-p file)
        (user-error "%s has never been written; revu reviews saved files" file))
      (when (and buffer (buffer-modified-p buffer))
        (message "Reviewing what %s holds on disk; the buffer has unsaved edits"
                 (file-name-nondirectory file))))
    file))

(defun revu--goto-line (number)
  "Put point on the rendered line numbered NUMBER of the file under review."
  (goto-char (point-min))
  (let ((found nil))
    (while (and (not found) (not (eobp)))
      (let ((target (get-text-property (point) 'revu-target)))
        (if (equal (nth 1 target) number)
            (setq found t)
          (forward-line 1))))
    (unless found
      (goto-char (point-min)))))

;;;###autoload
(defun revu-file (&optional file name)
  "Review the plain FILE, which defaults to the one this buffer visits.
NAME names the Review; it is prompted for, with the name derived from the
Source offered as the default.

One file is reviewed per Review, flat, with no diff about it (ADR-0011).
What is on disk is what is reviewed, whatever an open buffer on the file
has been edited to since it was last written; a modified buffer is
offered the chance to be saved first.  An active region does one thing
only: it puts point on its first line in the review buffer."
  (interactive)
  (let* (;; A region says where to start reading, and it says it in the
         ;; visiting buffer's line numbers.  Those describe the disk file
         ;; only while the buffer has not drifted from it, so a buffer
         ;; whose save was declined places point nowhere in particular
         ;; rather than somewhere wrong.
         (line (and (use-region-p)
                    (not (buffer-modified-p))
                    (line-number-at-pos (region-beginning))))
         (file (file-truename (revu--saved-file file)))
         (root (revu-project-root file))
         (path (file-relative-name file root))
         (source (revu-source-file path))
         (name (or name (revu--read-review-name source)))
         (default-directory root))
    (revu--open source (revu--source-files source root) name)
    (when line
      (with-current-buffer (revu-buffer-name name)
        (revu--goto-line line)))))

(provide 'revu)
;;; revu.el ends here
