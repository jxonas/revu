;;; revu-sidecar.el --- Read and write the Sidecar that holds a Review  -*- lexical-binding: t; -*-

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

;; The Sidecar is the review state itself, not a flush of it: every
;; change to a Review is written through to disk at once, atomically,
;; so an agent reading the file at any moment reads a whole Review.
;;
;; Because agents write to the same file, revu remembers what the file
;; looked like when it read it -- both its modification time and a
;; digest of its bytes -- and refuses to write over a file that changed
;; underneath it until the reviewer reloads.  `revu-sidecar-force-write'
;; is the one deliberate way past that, for when the reviewer judges
;; what the agent wrote to be garbage.

;;; Code:

(require 'cl-lib)
(require 'revu-record)

(define-error 'revu-sidecar-changed
  "The Sidecar changed on disk"
  'error)

(defconst revu-sidecar-file-modes #o600
  "File modes a Sidecar is written with.")

(cl-defstruct (revu-sidecar (:constructor revu--sidecar-make)
                            (:copier nil))
  "An open Sidecar: the Review it holds, and what its file looked like.
FILE is the Sidecar's path, REVIEW the last state read from or written
to it, and MTIME and DIGEST the modification time and content digest the
file had at that moment -- together, the write guard."
  file review mtime digest)

(defun revu--sidecar-contents (file)
  "Return the contents of FILE as a string, or nil when it does not exist."
  (when (file-exists-p file)
    (with-temp-buffer
      (set-buffer-multibyte nil)
      (insert-file-contents-literally file)
      (decode-coding-string (buffer-string) 'utf-8))))

(defun revu--sidecar-mtime (file)
  "Return the modification time of FILE, or nil when it does not exist."
  (file-attribute-modification-time (file-attributes file)))

(defun revu--sidecar-note-state (sidecar text)
  "Remember on SIDECAR the state of its file, whose text is now TEXT.
Return SIDECAR."
  (setf (revu-sidecar-mtime sidecar) (revu--sidecar-mtime
                                      (revu-sidecar-file sidecar)))
  (setf (revu-sidecar-digest sidecar) (revu-digest text))
  sidecar)

(defun revu-sidecar-load (file)
  "Return the Sidecar at FILE, with its Review and the write guard read.
Signal `revu-invalid-sidecar' when FILE is missing or does not hold a
Review this revu understands; the file is left untouched either way."
  (let ((text (revu--sidecar-contents file)))
    (unless text
      (signal 'revu-invalid-sidecar (list (format "No Sidecar at %s" file))))
    (let ((sidecar (revu--sidecar-make :file file
                                       :review (revu-review-decode text))))
      (revu--sidecar-note-state sidecar text))))

(defun revu--sidecar-write-text (file text)
  "Write TEXT to FILE atomically, through a temporary file in its directory.
A reader never sees a half-written Sidecar: the rename is the moment the
new Review becomes the file."
  (let* ((directory (file-name-directory file))
         (temporary (make-temp-file (expand-file-name ".revu-" directory))))
    (unwind-protect
        (progn
          (let ((coding-system-for-write 'utf-8-unix))
            (write-region text nil temporary nil 'silent))
          (set-file-modes temporary revu-sidecar-file-modes)
          (rename-file temporary file t)
          (setq temporary nil))
      (when (and temporary (file-exists-p temporary))
        (delete-file temporary)))))

(defun revu--sidecar-store (sidecar review)
  "Write REVIEW to SIDECAR's file and remember it.  Return SIDECAR."
  (let ((text (revu-review-encode review)))
    (revu--sidecar-write-text (revu-sidecar-file sidecar) text)
    (setf (revu-sidecar-review sidecar) review)
    (revu--sidecar-note-state sidecar text)))

(defun revu-sidecar-changed-p (sidecar)
  "Return non-nil when SIDECAR's file is no longer what revu last read.
The modification time is the cheap check and the content digest is the
deciding one: a file rewritten with the same bytes has not changed, so a
touch, or a checkout that restores what was already there, must not block
the reviewer's next Annotation."
  (let ((file (revu-sidecar-file sidecar)))
    (unless (equal (revu--sidecar-mtime file) (revu-sidecar-mtime sidecar))
      (let ((text (revu--sidecar-contents file)))
        (or (null text)
            (not (equal (revu-digest text) (revu-sidecar-digest sidecar))))))))

(defun revu-sidecar-write (sidecar review)
  "Write REVIEW to SIDECAR, unless its file changed underneath revu.
Signal `revu-sidecar-changed' when it did, naming the reload that clears
the block, and leave the file alone: an agent's edits are never
overwritten by accident.  Return SIDECAR."
  (when (revu-sidecar-changed-p sidecar)
    (signal 'revu-sidecar-changed
            (list (format "%s changed on disk; reload it (%s) before writing, \
or force-write to overwrite it"
                          (revu-sidecar-file sidecar) "revu-sidecar-reload"))))
  (revu--sidecar-store sidecar review))

(defun revu-sidecar-force-write (sidecar review)
  "Write REVIEW to SIDECAR whatever is in its file now.  Return SIDECAR.
This is the deliberate way past the write guard, and it overwrites
whatever an agent wrote."
  (revu--sidecar-store sidecar review))

(defun revu-sidecar-reload (sidecar)
  "Re-read SIDECAR's file into it and clear the write guard.  Return SIDECAR.
A file this revu cannot read signals and changes nothing: SIDECAR keeps
the last Review it held, and the file on disk is left as the agent wrote
it, so the reviewer can look at it and decide."
  (let ((fresh (revu-sidecar-load (revu-sidecar-file sidecar))))
    (setf (revu-sidecar-review sidecar) (revu-sidecar-review fresh))
    (setf (revu-sidecar-mtime sidecar) (revu-sidecar-mtime fresh))
    (setf (revu-sidecar-digest sidecar) (revu-sidecar-digest fresh))
    sidecar))

(defun revu-sidecar-open (file review)
  "Return the Sidecar at FILE, resuming the Review already there.
REVIEW is written only when FILE holds no Review yet.  Reviewing a
Source a second time therefore picks the Review up where it was left,
and an existing Sidecar is never clobbered by a fresh empty one."
  (if (file-exists-p file)
      (revu-sidecar-load file)
    (revu--sidecar-store (revu--sidecar-make :file file) review)))

(provide 'revu-sidecar)
;;; revu-sidecar.el ends here
