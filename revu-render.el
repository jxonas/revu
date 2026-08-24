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
;; Visibility is part of what a render applies, not something the buffer
;; carries over on its own: building the tree only resolves each
;; section's `hidden' slot, and the render puts those slots on screen
;; before it hands the buffer back.  A fold the reviewer set survives
;; because magit-section's visibility cache resolves it again, not
;; because the old overlay was left alone -- there is no old buffer.
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

(defface revu-annotation-heading
  '((t :inherit font-lock-keyword-face))
  "Face of the heading that opens an Annotation's section."
  :group 'revu)

(defface revu-annotation-body
  '((t :inherit font-lock-doc-face))
  "Face of the body the reviewer wrote on an Annotation."
  :group 'revu)

(defface revu-reply
  '((t :inherit font-lock-string-face))
  "Face of the Reply an agent wrote under an Annotation.
A Reply has a face of its own because its presence is the answered
signal (ADR-0007): the reviewer tells an answered Annotation from an
unanswered one by reading the buffer."
  :group 'revu)

(defface revu-moved
  '((t :inherit warning))
  "Face of the badge on an Annotation whose Anchor was re-found elsewhere."
  :group 'revu)

(defface revu-orphaned
  '((t :inherit error))
  "Face of the badge on an Annotation whose Anchor was not found at all."
  :group 'revu)

(defclass revu-file-section (magit-section) ()
  "The section holding one file of the Source under review.")

(defclass revu-hunk-section (magit-section) ()
  "The section holding one hunk of a file under review.")

(defclass revu-annotation-section (magit-section) ()
  "The section holding one Annotation.
Its value is the Annotation's ULID, which is the Annotation's identity:
two Annotations on one Target are two sections, and point can rest on
either of them.")

(cl-defstruct (revu-render-placement
               (:constructor revu-render-placement-create)
               (:copier nil))
  "Where one Annotation renders now, and the state derived for it.
ANNOTATION is the record, PATH the file it belongs to today, LINE the
line its Anchor was re-located to and ORIGIN that line's Origin, and
STATE is `fresh', `moved' or `orphaned'.  END is the last line of a
range, re-located on its own; only a range Target has one.  An
Annotation on the Review has no PATH, and one that was not found again
has no LINE: it renders under the heading of its file, or at the top of
the buffer when its file is not in the Source at all."
  annotation path line end origin state)

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
  "Return the heading text of FILE, a `revu-diff-file'.
A plain file is named and nothing more: there is no diff, so there is
nothing for a status word to say about it (ADR-0011)."
  (if (revu-diff-file-plain file)
      (revu-diff-file-path file)
    (concat (revu-render--status-label (revu-diff-file-status file))
          "  "
          (if (equal (revu-diff-file-status file) "renamed")
              (format "%s -> %s"
                      (revu-diff-file-old-path file)
                      (revu-diff-file-path file))
              (revu-diff-file-path file)))))

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

(defun revu-render-line (path old-path line width)
  "Insert LINE of the file at PATH, prefixed by its number in WIDTH columns.
LINE is (ORIGIN NUMBER TEXT).  The number is the line's number in the
file its Origin counts in -- the old file for a removal, the new file for
anything else -- and the whole line carries a `revu-target' property naming
what the reviewer is pointing at.

A removed line is named under OLD-PATH, the path the file had before the
diff renamed it, because that is the only path the line exists under: it
is read back from the base blob, and ADR-0004 keeps a Target's path as
recorded rather than rewriting it later."
  (pcase-let ((`(,origin ,number ,text) line))
    (insert
     (propertize
      (concat (propertize (format (format "%%%dd " width) number)
                          'font-lock-face 'revu-line-number)
              (propertize text 'font-lock-face (revu-render--line-face origin))
              "\n")
      'revu-target (list (if (equal origin "removed") old-path path)
                         number origin)))))

(defconst revu-render--annotation-indent "    "
  "What an Annotation's heading is indented by under the line it is about.")

(defun revu-render--state-face (state)
  "Return the face the badge naming Anchor STATE is rendered in."
  (pcase state
    ('moved 'revu-moved)
    ('orphaned 'revu-orphaned)
    (_ 'revu-annotation-heading)))

(defun revu-render-annotation (placement)
  "Insert the Annotation of PLACEMENT as a section of its own.
The heading names the Kind the reviewer chose and the state derived for
the Anchor, and the body under it is the section's content, so `TAB'
folds it away like any other section.  An agent's Reply follows the body
it answers, in a face of its own."
  (let* ((annotation (revu-render-placement-annotation placement))
         (state (revu-render-placement-state placement))
         (reply (revu-annotation-reply annotation)))
    (magit-insert-section (revu-annotation-section
                           (revu-annotation-id annotation))
      (magit-insert-heading
        (concat revu-render--annotation-indent
                (propertize (revu-annotation-kind annotation)
                            'font-lock-face 'revu-annotation-heading)
                (when state
                  (propertize (format " [%s]" state)
                              'font-lock-face (revu-render--state-face state)))))
      (dolist (line (split-string (revu-annotation-body annotation) "\n"))
        (insert revu-render--annotation-indent "  "
                (propertize line 'font-lock-face 'revu-annotation-body)
                "\n"))
      (dolist (line (and reply (split-string reply "\n")))
        (insert revu-render--annotation-indent "  "
                (propertize line 'font-lock-face 'revu-reply)
                "\n")))))

(defun revu-render--lines (hunk file width placements)
  "Insert the lines of HUNK of FILE, in WIDTH columns, with their PLACEMENTS.
The Annotations on a line are inserted as sections under it, which is
what makes them foldable and addressable (ADR-0008)."
  (dolist (line (revu-diff-hunk-lines hunk))
    (revu-render-line (revu-diff-file-path file) (revu-diff-file-old-path file)
                      line width)
    (dolist (placement (revu-render--placements-at
                        placements (nth 1 line) (nth 0 line)))
      (revu-render-annotation placement))))

(defun revu-render--placements-on (placements path)
  "Return the PLACEMENTS that belong to the file at PATH."
  (seq-filter (lambda (placement)
                (equal (revu-render-placement-path placement) path))
              placements))

(defun revu-render--placements-at (placements number origin)
  "Return the PLACEMENTS that belong on the line NUMBER of Origin ORIGIN."
  (seq-filter (lambda (placement)
                (and (equal (revu-render-placement-line placement) number)
                     (equal (revu-render-placement-origin placement) origin)))
              placements))

(defun revu-render--file-lines (file)
  "Return every (NUMBER . ORIGIN) FILE renders, as a list."
  (let ((lines nil))
    (dolist (hunk (revu-diff-file-hunks file))
      (dolist (line (revu-diff-hunk-lines hunk))
        (push (cons (nth 1 line) (nth 0 line)) lines)))
    lines))

(defun revu-render--unplaced (placements file)
  "Return the PLACEMENTS of FILE that no line FILE renders is about.
An Annotation on a whole file has no line to sit under, and one whose
Anchor was orphaned, or re-located outside every hunk, has no line left
to sit under; both belong under the file's own heading, where the
reviewer can still see them."
  (let ((lines (revu-render--file-lines file)))
    (seq-remove (lambda (placement)
                  (member (cons (revu-render-placement-line placement)
                                (revu-render-placement-origin placement))
                          lines))
                placements)))

(defun revu-render--annotated-p (placements hunk)
  "Return non-nil when PLACEMENTS puts an Annotation on HUNK.
PLACEMENTS are the ones already known to belong to HUNK's file.  A whole-file
Annotation, and one whose Anchor was orphaned, belongs to no hunk: it
renders under the file's own heading, which is where the annotated-only
filter keeps it findable."
  (seq-find (lambda (line)
              (revu-render--placements-at placements (nth 1 line) (nth 0 line)))
            (revu-diff-hunk-lines hunk)))

(defun revu-render-diff (files &optional hidden-p placements keep-p)
  "Render FILES, a list of `revu-diff-file', into the current buffer.
HIDDEN-P is called with the value of each file and hunk section and
decides whether that section is rendered collapsed; a Reviewed mark
collapses what it marks through it.  PLACEMENTS are the
`revu-render-placement's of the Review's Annotations, which render as
sections under the lines they are about.  KEEP-P is called with the value
of each file and hunk section and with whether any Annotation is on it,
and decides whether that section is rendered at all; the buffer's view
filters shape the render through it, and a nil KEEP-P renders the whole
Source.  Point is left where the same section, or failing that the same
line, held it before."
  (let* ((inhibit-read-only t)
         (previous (revu-render--point-state))
         (paths (mapcar #'revu-diff-file-path files))
         ;; An Annotation on the Review, and one on a file the Source does
         ;; not carry, belong to no file section: they open the buffer.
         (loose (seq-remove (lambda (placement)
                              (member (revu-render-placement-path placement)
                                      paths))
                            placements)))
    (erase-buffer)
    (magit-insert-section (magit-section 'revu-review)
      (dolist (placement loose)
        (revu-render-annotation placement))
      (dolist (file files)
        (let* ((path (revu-diff-file-path file))
               (width (revu-render--number-width file))
               (mine (revu-render--placements-on placements path))
               (plain (revu-diff-file-plain file))
               (hunks (seq-filter
                       (lambda (hunk)
                         (or plain (null keep-p)
                             (funcall keep-p
                                      (cons path (revu-diff-hunk-header hunk))
                                      (revu-render--annotated-p mine hunk))))
                       (revu-diff-file-hunks file))))
          (when (or (null keep-p) (funcall keep-p path (and mine t)))
            (magit-insert-section (revu-file-section
                                   path
                                   (and hidden-p (funcall hidden-p path)))
              (magit-insert-heading
                (propertize (revu-render--file-heading file)
                            'font-lock-face 'revu-file-heading))
              (dolist (placement (revu-render--unplaced mine file))
                (revu-render-annotation placement))
              (dolist (hunk hunks)
                ;; A plain file is the diff render minus the hunk split: its
                ;; lines sit flat under the one file section (ADR-0011).
                (if plain
                    (revu-render--lines hunk file width mine)
                  (let ((value (cons path (revu-diff-hunk-header hunk))))
                    (magit-insert-section (revu-hunk-section
                                           value
                                           (and hidden-p
                                                (funcall hidden-p value)))
                      (magit-insert-heading
                        (propertize (revu-diff-hunk-header hunk)
                                    'font-lock-face 'revu-hunk-heading))
                      (revu-render--lines hunk file width mine))))))))))
    ;; Building the tree only resolves each section's visibility into its
    ;; `hidden' slot; what hides text is an invisible overlay, and only
    ;; `magit-section-hide' makes one.  Magit's own applier walks the tree
    ;; and puts the slots on screen, so the render ends by calling it --
    ;; without it every render comes back fully expanded, whatever it
    ;; resolved (dcr-01m0rkxmpxza).
    (magit-section-show magit-root-section)
    (revu-render--restore-point previous)))

(defun revu-render--point-state ()
  "Return where point is, as the section it is in and the line it is on."
  (cons (and magit-root-section
             (let ((section (magit-current-section)))
               (and section (oref section value))))
        (line-number-at-pos)))

(defun revu-render-section-with-value (value)
  "Return the section whose value is VALUE, or nil when there is none.
A section's value is its identity across a render, which is how a command
finds again what it acted on once the buffer has been built anew."
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
  (let ((section (revu-render-section-with-value (car state))))
    (if section
        (goto-char (oref section start))
      (goto-char (point-min))
      (forward-line (1- (cdr state))))))

(provide 'revu-render)
;;; revu-render.el ends here
