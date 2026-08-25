;;; revu-annotate.el --- Add, edit and delete Annotations  -*- lexical-binding: t; -*-

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

;; The reviewer's loop: annotate the line at point, the region, the hunk,
;; the file, or the Review itself; then edit or delete what is there.
;;
;; Every mutation runs in one order and finishes before the command
;; returns: the Anchor is taken from the file content the Target names,
;; the record is updated, the Sidecar is written atomically, and only
;; then is the buffer rendered again (ADR-0002, ADR-0005).  There is no
;; save step and nothing deferred, because the Sidecar is the review
;; state rather than a flush of it.
;;
;; A hunk Annotation is a `range' over the hunk, not a Target kind of its
;; own (ADR-0003), and so is an Annotation on a region.  Both pick one
;; Origin -- the added lines when the selection has any, else the removed
;; ones, else context -- so a range's endpoints are counted in one file's
;; numbers, which is what the revdiff Export needs of them.
;;
;; This file also derives where each Annotation of a Review renders now:
;; it runs the Anchor ladder over today's file content and reports the
;; line each Annotation belongs on and the state derived for it.  That
;; state is derived on every render and never persisted (ADR-0003).

;;; Code:

(require 'cl-lib)
(require 'magit-section)
(require 'seq)
(require 'string-edit)
(require 'subr-x)
(require 'revu-anchor)
(require 'revu-diff)
(require 'revu-record)
(require 'revu-render)
(require 'revu-sidecar)

;; The review buffer's state and its render live in `revu.el', which
;; requires this file; naming them here would be a loading cycle.
(defvar revu--sidecar)
(declare-function revu-render "revu")
(declare-function revu-review "revu")

;;;; Reading the file content an Anchor is taken in

(defun revu-annotate--file-content (root path)
  "Return the content of PATH under ROOT, or nil when there is no such file."
  (let ((file (expand-file-name path root)))
    (when (file-regular-p file)
      (with-temp-buffer
        (insert-file-contents file)
        (buffer-string)))))

(defun revu-annotate--head-content (root source path)
  "Return the content of PATH under ROOT on the head side of SOURCE.
An Anchor has to record the line the reviewer pointed at, so it is read
from the same content the diff was generated from: the worktree for a
worktree Review, the index for a staged one, and the head Revision for a
range.  Reading a staged or ranged line out of the worktree would bake in
whatever the worktree has drifted to since, which is a line the reviewer
never saw."
  (pcase (revu-source-kind source)
    ("staged" (revu-diff-show-file root "" path))
    ("range" (let ((head (revu-source-head source)))
               (and head (revu-diff-show-file root head path))))
    (_ (revu-annotate--file-content root path))))

(defun revu-annotate--anchor-content (root source path origin)
  "Return the content a Target on PATH with ORIGIN is anchored in.
PATH is read under ROOT, and SOURCE says what the diff was taken against.
A removed line is not on the new side at all, so its Anchor is taken in
the base blob the Source was diffed against; every other line is anchored
in what the Source's own head shows (ADR-0003).  Return nil when there is
nothing to anchor in -- the file is gone, or the Source records no
Revision revu can read."
  (if (equal origin "removed")
      (let ((base (revu-source-base source)))
        (and base (revu-diff-show-file root base path)))
    (revu-annotate--head-content root source path)))

(defun revu-annotate--anchor (root source target)
  "Return the Anchor that re-locates TARGET, or nil when it needs none.
The content it is taken in is read under ROOT, for the Review over SOURCE.
A file or Review Target names no line and carries no Anchor."
  (let* ((path (revu-target-path target))
         (kind (revu-target-kind target))
         (content (and path (member kind '("line" "range"))
                       (revu-annotate--anchor-content
                        root source path (revu-target-origin target)))))
    (when content
      (if (equal kind "line")
          (revu-anchor-create content (revu-target-line-number target))
        (revu-anchor-create-range content
                                  (revu-target-start target)
                                  (revu-target-end target))))))

;;;; Where an Annotation renders, and the state derived for it

(defun revu-annotate--cached (cache key read)
  "Return what READ gives for KEY, remembering it in CACHE.
One render asks for a file's content once however many Annotations it
carries.  A file that is not there caches its absence too, so a missing
path is not read again for every Annotation on it."
  (let ((cached (gethash key cache 'revu-annotate--unread)))
    (if (eq cached 'revu-annotate--unread)
        (setf (gethash key cache) (funcall read))
      cached)))

(defun revu-annotate--content-of (cache root path)
  "Return the current content of PATH under ROOT, remembering it in CACHE."
  (revu-annotate--cached
   cache (cons 'current path)
   (lambda () (and path (revu-annotate--file-content root path)))))

(defun revu-annotate--base-content-of (cache root source path)
  "Return the base blob of PATH for SOURCE under ROOT, remembering it in CACHE."
  (revu-annotate--cached
   cache (cons 'base path)
   (lambda ()
     (let ((base (revu-source-base source)))
       (and base path (revu-diff-show-file root base path))))))

(defun revu-annotate--resolved-path (recorded resolutions)
  "Return where RECORDED stands today, given RESOLUTIONS.
A renamed path resolves to its new name; every other path is itself.
The Target's own path is never rewritten (ADR-0004): it is what a removed
line is read from, so it has to keep saying where the line came from."
  (let ((resolution (alist-get recorded resolutions nil nil #'equal)))
    (if (eq (car-safe resolution) 'renamed) (cdr resolution) recorded)))

(defun revu-annotate--locate (annotation root source resolutions cache)
  "Locate ANNOTATION against today's content.  Return (LINE END STATE).
ROOT is the project root, SOURCE the Review's Source, RESOLUTIONS what
became of each recorded path, and CACHE the content read so far.  LINE is
the line the Annotation belongs on now, or nil when it was not found, and
END the last line of a range, which only a range has; STATE is `fresh',
`moved' or `orphaned'."
  (let* ((target (revu-annotation-target annotation))
         (recorded (revu-target-path target))
         (resolution (alist-get recorded resolutions nil nil #'equal))
         (path (revu-annotate--resolved-path recorded resolutions))
         (origin (revu-target-origin target))
         (anchor (revu-annotation-anchor annotation))
         (removed (equal origin "removed"))
         (content (if removed
                      (revu-annotate--base-content-of cache root source recorded)
                    (revu-annotate--content-of cache root path))))
    (pcase (revu-target-kind target)
      ((or "review" "file")
       (list nil nil (if (eq resolution 'deleted) 'orphaned 'fresh)))
      ((guard (null anchor))
       ;; An Annotation an agent appended may carry no Anchor at all; its
       ;; recorded lines are then all there is to go on.
       (list (or (revu-target-line-number target) (revu-target-start target))
             (revu-target-end target)
             'fresh))
      ("line"
       (let ((located
              (if removed
                  (revu-anchor-locate-removed
                   content (revu-annotate--content-of cache root path) anchor
                   (revu-target-line-number target))
                (if content
                    (revu-anchor-locate content anchor
                                        (revu-target-line-number target))
                  (cons nil 'orphaned)))))
         (list (car located) nil (cdr located))))
      ("range"
       (if (null content)
           (list nil nil 'orphaned)
         (let ((located (revu-anchor-locate-range content anchor
                                                  (revu-target-start target)
                                                  (revu-target-end target))))
           (list (car-safe (car located)) (cdr-safe (car located))
                 (cdr located))))))))

(defun revu-annotate-placements (review root)
  "Return where every Annotation of REVIEW renders under ROOT.
Each is a `revu-render-placement': the Annotation, the path it belongs to
now, the line the Anchor was re-located to, its Origin, and the state
derived for it.  Nothing here is written to the Sidecar; a stored state
is a lie as soon as the file is edited outside Emacs (ADR-0003)."
  (let ((annotations (revu-review-annotations review)))
    (when (> (seq-length annotations) 0)
      (let* ((source (revu-review-source review))
             (paths (seq-uniq
                     (seq-remove
                      #'null
                      (seq-map (lambda (annotation)
                                 (revu-target-path
                                  (revu-annotation-target annotation)))
                               annotations))))
             (resolutions (revu-diff-resolve-paths root source (append paths nil)))
             (cache (make-hash-table :test #'equal)))
        (seq-map
         (lambda (annotation)
           (let* ((target (revu-annotation-target annotation))
                  (recorded (revu-target-path target))
                  (located (revu-annotate--locate annotation root source
                                                  resolutions cache)))
             (revu-render-placement-create
              :annotation annotation
              :path (revu-annotate--resolved-path recorded resolutions)
              :line (nth 0 located)
              :end (nth 1 located)
              :origin (revu-target-origin target)
              :state (nth 2 located))))
         (append annotations nil))))))

;;;; Asking the reviewer

(defun revu-annotate--read-kind ()
  "Return the Kind the reviewer means by the Annotation they are writing.
The choice is asked for outright: what a reviewer means by an Annotation
is the one thing an agent reading it cannot guess."
  (completing-read "Kind: " revu-annotation-kinds nil t))

(defun revu-annotate--read-body (&optional initial)
  "Return the Annotation body the reviewer writes, starting from INITIAL.
The body is written in an ordinary buffer, which the reviewer leaves by
keeping what they wrote or by dropping it, because an Annotation is prose
rather than a minibuffer answer.  An empty body is refused: it says
nothing."
  (let ((body (string-trim-right
               (read-string-from-buffer
                ";; Write the Annotation.  C-c C-c to keep it, C-c C-k to drop it."
                (or initial "")))))
    (when (string-empty-p body)
      (user-error "An empty Annotation says nothing; nothing was written"))
    body))

;;;; What the reviewer is pointing at

(defun revu-annotate--target-at-point ()
  "Return the (PATH LINE ORIGIN) of the Source line point is on.
Signal a `user-error' when point is not on one."
  (or (get-text-property (line-beginning-position) 'revu-target)
      (user-error "Point is not on a line of the Source")))

(defun revu-annotate--lines-between (beginning end)
  "Return the (PATH LINE ORIGIN) of every Source line between BEGINNING and END.
Anything else the region covers -- headings, and the Annotation sections
already rendered between the lines -- carries no Target and is passed
over (ADR-0011)."
  (let ((lines nil))
    (save-excursion
      (goto-char beginning)
      (goto-char (line-beginning-position))
      (while (< (point) end)
        (let ((line (get-text-property (point) 'revu-target)))
          (when line (push line lines)))
        (forward-line 1)))
    (nreverse lines)))

(defun revu-annotate--range-target (lines)
  "Return the range Target covering LINES, in the shape they are collected in.
The lines of one file take part, and of those the added ones when there
are any, else the removed ones, else the context: a range is counted in
one file's numbers, and the added Origin is the one the Export renders
a mixed selection over."
  (unless lines
    (user-error "No line of the Source is selected"))
  (let* ((path (nth 0 (car lines)))
         (same (seq-filter (lambda (line) (equal (nth 0 line) path)) lines))
         (origin (seq-find (lambda (candidate)
                             (seq-find (lambda (line)
                                         (equal (nth 2 line) candidate))
                                       same))
                           '("added" "removed" "context")))
         (numbers (seq-map (lambda (line) (nth 1 line))
                           (seq-filter (lambda (line)
                                         (equal (nth 2 line) origin))
                                       same))))
    (revu-target-range path (apply #'min numbers) (apply #'max numbers) origin)))

(defun revu-annotate--section (class what)
  "Return the section of CLASS at point, or the one containing it.
WHAT names it in the `user-error' raised when point is in no such
section."
  (let ((section (magit-current-section)))
    (while (and section (not (object-of-class-p section class)))
      (setq section (oref section parent)))
    (or section (user-error "Point is not in %s" what))))

;;;; Mutating the Review

(defun revu-annotate--write (review)
  "Write REVIEW to the Sidecar of the current review buffer, then render it.
The write has landed on disk by the time this returns: an Annotation the
reviewer wrote is in the file an agent reads before the command that
wrote it is over (ADR-0002)."
  (revu-sidecar-write revu--sidecar review)
  (revu-render))

(defun revu-annotate--add (kind body target)
  "Add an Annotation of KIND carrying BODY on TARGET to the current Review.
The Anchor is taken first, the record next, the Sidecar after that, and
the buffer is rendered last."
  (let* ((review (revu-review))
         (root default-directory)
         (anchor (revu-annotate--anchor root (revu-review-source review) target))
         (annotation (revu-annotation-create kind target body anchor)))
    (revu-annotate--write (revu-review-add-annotation review annotation))
    annotation))

(defun revu-annotate--annotation-at-point ()
  "Return the Annotation of the section point is in.
Signal a `user-error' when point is in no Annotation section -- a
section is what makes an Annotation addressable (ADR-0008)."
  (let ((id (oref (revu-annotate--section 'revu-annotation-section
                                          "an Annotation")
                  value)))
    (or (revu-review-annotation (revu-review) id)
        (user-error "The Annotation %s is not in this Review any more" id))))

;;;; The commands

;;;###autoload
(defun revu-annotate-line (&optional kind body)
  "Annotate the line of the Source point is on, with KIND and BODY.
Both are asked for when they are not given."
  (interactive)
  (let* ((line (revu-annotate--target-at-point))
         (target (revu-target-line (nth 0 line) (nth 1 line) (nth 2 line))))
    (revu-annotate--add (or kind (revu-annotate--read-kind))
                        (or body (revu-annotate--read-body))
                        target)))

;;;###autoload
(defun revu-annotate-range (beginning end &optional kind body)
  "Annotate the Source lines between BEGINNING and END, with KIND and BODY.
Interactively, that is the region.  The Annotation is on a range Target,
which is what a run of lines is; KIND and BODY are asked for when they
are not given."
  (interactive "r")
  (let ((target (revu-annotate--range-target
                 (revu-annotate--lines-between beginning end))))
    (revu-annotate--add (or kind (revu-annotate--read-kind))
                        (or body (revu-annotate--read-body))
                        target)))

;;;###autoload
(defun revu-annotate-hunk (&optional kind body)
  "Annotate the hunk point is in, with KIND and BODY.
A hunk Annotation is a range over the hunk's lines rather than a Target
kind of its own (ADR-0003)."
  (interactive)
  (let ((section (revu-annotate--section 'revu-hunk-section "a hunk")))
    (revu-annotate-range (oref section start) (oref section end) kind body)))

;;;###autoload
(defun revu-annotate-file (&optional kind body)
  "Annotate the whole file point is in, with KIND and BODY."
  (interactive)
  (let ((path (oref (revu-annotate--section 'revu-file-section "a file") value)))
    (revu-annotate--add (or kind (revu-annotate--read-kind))
                        (or body (revu-annotate--read-body))
                        (revu-target-file path))))

;;;###autoload
(defun revu-annotate-review (&optional kind body)
  "Annotate the Review as a whole, with KIND and BODY.
This is what the reviewer has to say about the change rather than about
any line of it."
  (interactive)
  (revu-annotate--add (or kind (revu-annotate--read-kind))
                      (or body (revu-annotate--read-body))
                      (revu-target-review)))

;;;###autoload
(defun revu-annotate--annotated-section ()
  "Return the section at point that an Annotation could be made on.
An Annotation section is passed over rather than answered with: an
Annotation is not a Target, so what point is on when it is standing on
one is whatever the Annotation is rendered under.  That is the header for
an Annotation on the Review, and the file heading for one on a whole
file."
  (let ((section (magit-current-section)))
    (while (object-of-class-p section 'revu-annotation-section)
      (setq section (oref section parent)))
    section))

(defun revu-annotate (&optional kind body)
  "Annotate what point is on, with KIND and BODY.
An active region is a range and a Source line is a line.  Off the Source,
what point is in answers: the header at the top of the buffer is the
Review as a whole, and a file heading is the file.  It is the section
point is in and not one above it, so `a\=' never widens an Annotation
past what the reviewer is looking at; `f\=' and `R\=' are the explicit
routes to the file and the Review from anywhere.

Point on nothing annotatable falls through to the line, which says so."
  (interactive)
  (let ((section (revu-annotate--annotated-section)))
    (cond ((use-region-p)
           (revu-annotate-range (region-beginning) (region-end) kind body))
          ((get-text-property (line-beginning-position) 'revu-target)
           (revu-annotate-line kind body))
          ((object-of-class-p section 'revu-header-section)
           (revu-annotate-review kind body))
          ((object-of-class-p section 'revu-file-section)
           (revu-annotate-file kind body))
          (t (revu-annotate-line kind body)))))

;;;###autoload
(defun revu-annotate-edit (&optional body)
  "Rewrite the body of the Annotation point is in as BODY.
BODY is written in a buffer holding what the Annotation says now when it
is not given.  The Target and the Anchor stand: the reviewer is saying
the same thing better, not saying it about somewhere else."
  (interactive)
  (let* ((annotation (revu-annotate--annotation-at-point))
         (body (or body
                   (revu-annotate--read-body (revu-annotation-body annotation)))))
    (revu-annotate--write
     (revu-review-replace-annotation
      (revu-review) (revu-annotation-set-body annotation body)))))

;;;###autoload
(defun revu-annotate-delete ()
  "Delete the Annotation point is in from the Review."
  (interactive)
  (let ((annotation (revu-annotate--annotation-at-point)))
    (revu-annotate--write
     (revu-review-remove-annotation (revu-review)
                                    (revu-annotation-id annotation)))))

(provide 'revu-annotate)
;;; revu-annotate.el ends here
