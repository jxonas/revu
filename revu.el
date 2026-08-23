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
(require 'revu-record)
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

(provide 'revu)
;;; revu.el ends here
