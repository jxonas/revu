;;; revu-render.el --- Render a Review as a section tree  -*- lexical-binding: t; -*-

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

;; The review buffer is a render of state and nothing else (ADR-0008):
;; every change to a Review is a change to the state followed by a fresh
;; render, so the buffer can never drift from what the Sidecar holds.
;; Rendering the same state twice produces the same buffer.
;;
;; The tree is built with the standalone `magit-section' library, never
;; magit itself: a file is a section, a hunk is a section under it, and
;; folding, navigation and collapsing come with them.  A section that
;; should come back collapsed is rendered with `magit-insert-section's
;; HIDE argument, which is how a Reviewed mark will collapse what it
;; marks.
;;
;; Every source line carries a `revu-target' text property -- its path, its
;; number and its Origin -- so a command can tell what the reviewer is
;; pointing at, and a dim line-number prefix, because reviewers talk to
;; agents in line numbers (ADR-0011).  Text is faced with
;; `font-lock-face': `global-font-lock-mode' strips `face'.

;;; Code:

(require 'cl-lib)
(require 'diff-mode)
(require 'magit-section)
(require 'seq)
(require 'revu-diff)
(require 'revu-record)

(defface revu-line-number
  '((t :inherit shadow))
  "Face of the line-number prefix revu puts on every rendered line."
  :group 'revu)

(defface revu-file-heading
  '((t :inherit diff-file-header))
  "Face of the heading that opens a file's section."
  :group 'revu)

(defface revu-hunk-heading
  '((t :inherit diff-hunk-header))
  "Face of the heading that opens a hunk's section."
  :group 'revu)

(defclass revu-file-section (magit-section) ()
  "The section holding one file of the Source under review.")

(defclass revu-hunk-section (magit-section) ()
  "The section holding one hunk of a file under review.")

(defconst revu-render--line-number-width 4
  "Least width of the line-number prefix, in characters.")

(defun revu-render--status-label (status)
  "Return the word that opens the heading of a file with STATUS."
  (pcase status
    ("added" "new file ")
    ("deleted" "deleted  ")
    ("renamed" "renamed  ")
    (_ "modified ")))

(defun revu-render--file-heading (file)
  "Return the heading text of FILE, a `revu-diff-file'."
  (concat (revu-render--status-label (revu-diff-file-status file))
          "  "
          (if (equal (revu-diff-file-status file) "renamed")
              (format "%s -> %s"
                      (revu-diff-file-old-path file)
                      (revu-diff-file-path file))
            (revu-diff-file-path file))))

(defun revu-render--number-width (file)
  "Return the width the line-number prefix takes for FILE.
One width per file keeps a file's lines aligned with each other, whatever
the numbers on either side of it reach."
  (let ((widest 0))
    (dolist (hunk (revu-diff-file-hunks file))
      (dolist (line (revu-diff-hunk-lines hunk))
        (setq widest (max widest (length (number-to-string (nth 1 line)))))))
    (max revu-render--line-number-width widest)))

(defun revu-render--line-face (origin)
  "Return the face a line of ORIGIN is rendered in."
  (pcase origin
    ("added" 'diff-added)
    ("removed" 'diff-removed)
    (_ 'diff-context)))

(defun revu-render-line (path line width)
  "Insert LINE of the file at PATH, prefixed by its number in WIDTH columns.
LINE is (ORIGIN NUMBER TEXT).  The number is the line's number in the
file its Origin counts in -- the old file for a removal, the new file for
anything else -- and the whole line carries a `revu-target' property naming
what the reviewer is pointing at."
  (pcase-let ((`(,origin ,number ,text) line))
    (insert
     (propertize
      (concat (propertize (format (format "%%%dd " width) number)
                          'font-lock-face 'revu-line-number)
              (propertize text 'font-lock-face (revu-render--line-face origin))
              "\n")
      'revu-target (list path number origin)))))

(defun revu-render-diff (files &optional hidden-p)
  "Render FILES, a list of `revu-diff-file', into the current buffer.
HIDDEN-P is called with the value of each file and hunk section and
decides whether that section is rendered collapsed; a Reviewed mark
collapses what it marks through it.  Point is left where the same
section, or failing that the same line, held it before."
  (let ((inhibit-read-only t)
        (previous (revu-render--point-state)))
    (erase-buffer)
    (magit-insert-section (magit-section 'revu-review)
      (dolist (file files)
        (let* ((path (revu-diff-file-path file))
               (width (revu-render--number-width file)))
          (magit-insert-section (revu-file-section path
                                                   (and hidden-p
                                                        (funcall hidden-p path)))
            (magit-insert-heading
              (propertize (revu-render--file-heading file)
                          'font-lock-face 'revu-file-heading))
            (dolist (hunk (revu-diff-file-hunks file))
              (let ((value (cons path (revu-diff-hunk-header hunk))))
                (magit-insert-section (revu-hunk-section value
                                                         (and hidden-p
                                                              (funcall hidden-p
                                                                       value)))
                  (magit-insert-heading
                    (propertize (revu-diff-hunk-header hunk)
                                'font-lock-face 'revu-hunk-heading))
                  (dolist (line (revu-diff-hunk-lines hunk))
                    (revu-render-line path line width)))))))))
    (revu-render--restore-point previous)))

(defun revu-render--point-state ()
  "Return where point is, as the section it is in and the line it is on."
  (cons (and magit-root-section
             (let ((section (magit-current-section)))
               (and section (oref section value))))
        (line-number-at-pos)))

(defun revu-render--section-with-value (value)
  "Return the section whose value is VALUE, or nil when there is none."
  (unless (null value)
    (let ((found nil))
      (cl-labels ((walk (section)
                    (cond (found nil)
                          ((equal (oref section value) value)
                           (setq found section))
                          (t (mapc #'walk (oref section children))))))
        (walk magit-root-section))
      found)))

(defun revu-render--restore-point (state)
  "Put point back where STATE, from `revu-render--point-state', had it.
The section the reviewer was reading is the better answer, because a
render that adds a line above it would otherwise slide the buffer out
from under them; the line number is the answer when that section is gone."
  (let ((section (revu-render--section-with-value (car state))))
    (if section
        (goto-char (oref section start))
      (goto-char (point-min))
      (forward-line (1- (cdr state))))))

(provide 'revu-render)
;;; revu-render.el ends here
