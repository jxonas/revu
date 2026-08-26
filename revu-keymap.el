;;; revu-keymap.el --- Keys, evil bindings and the dispatch palette  -*- lexical-binding: t; -*-

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

;; Everything a Review is driven by, gathered in one place (ADR-0010).
;;
;; `revu-mode-map' is the canonical keymap, laid on top of what
;; magit-section and `special-mode' already give a read-only tree buffer:
;; `TAB' and `S-TAB' fold, `n' and `p' walk sections, `M-n' and `M-p'
;; walk siblings, `^' goes up, `1'-`4' show levels, `q' buries the
;; buffer.  revu adds `a' to annotate, `e' to edit, `k' to delete, `r' to
;; toggle a Reviewed mark, `E' to Export, `g' to reload, `RET' to visit
;; what point is on, and `?' for the palette.
;;
;; `a' annotates whatever point is on and nothing wider: a selection is a
;; range, a Source line is a line, a file heading is that file, and the
;; header at the top of the buffer is the Review as a whole.  `f' and `R'
;; are still the explicit routes to the file and the Review from
;; anywhere.
;;
;; Evil users get bindings of revu's own, in a block that runs only when
;; evil is loaded.  revu depends on evil in no way and sets no initial
;; state: what the block does is keep the mnemonics where the letter is
;; not a load-bearing motion, and move them where it is -- `x' deletes,
;; `gr' reloads, `gj'/`gk' and `C-j'/`C-k' walk sections, `gh' goes up,
;; the brackets walk siblings, the `z' keys fold, and `j'/`k' and the
;; arrows move by visual line so that going up onto a collapsed heading
;; lands on its first column.  Those are evil-collection's conventions
;; for a magit-section buffer, bound by us, so the buffer behaves the
;; same on vanilla evil, on Doom and on bare evil-collection rather than
;; waiting on a module nobody here controls.
;;
;; `revu-dispatch' is the complete palette, and the only way to reach
;; three commands: `revu-force-write', which throws away what an agent
;; wrote, and the two render filters, which are rare enough that a direct
;; key would cost more than it pays.  Reaching them through the transient
;; is the friction those three are meant to have.

;;; Code:

(require 'magit-section)
(require 'seq)
(require 'transient)
(require 'revu-annotate)
(require 'revu-export)
(require 'revu-record)
(require 'revu-render)
(require 'revu-reviewed)

;; The review buffer's state lives in `revu.el', which requires this
;; file; naming it here would be a loading cycle.
(declare-function revu-review "revu")
(declare-function revu-reload "revu")
(declare-function revu-force-write "revu")
(declare-function revu-rename "revu")
(declare-function revu-open "revu")
(declare-function revu-discard "revu")

(declare-function evil-define-key* "ext:evil-core" (state keymap key def &rest bindings))
(declare-function evil-add-command-properties "ext:evil-common" (command &rest properties))
(declare-function evil-next-visual-line "ext:evil-commands" (&optional count))
(declare-function evil-previous-visual-line "ext:evil-commands" (&optional count))

;;;; Visiting what point is on

(defun revu-visit--placement ()
  "Return where the Annotation point is in stands today, or nil.
Nil when point is in no Annotation section: the reviewer is pointing at
the Source itself rather than at something they wrote about it."
  (let ((section (magit-current-section)))
    (while (and section
                (not (object-of-class-p section 'revu-annotation-section)))
      (setq section (oref section parent)))
    (when section
      (let ((id (oref section value)))
        (seq-find (lambda (placement)
                    (equal (revu-annotation-id
                            (revu-render-placement-annotation placement))
                           id))
                  (revu-annotate-placements (revu-review) default-directory))))))

(defun revu-visit--file (path line)
  "Show the file at PATH, relative to the project root, with point on LINE."
  (let ((file (expand-file-name path default-directory)))
    (if (not (file-regular-p file))
        (message "There is no %s to visit any more" path)
      (pop-to-buffer (find-file-noselect file))
      (goto-char (point-min))
      (forward-line (1- (or line 1))))))

(defun revu-visit--annotation (placement)
  "Visit the Target of the Annotation PLACEMENT stands for.
The file visited is the one the Target's path resolves to today and the
line is the one the Anchor was re-located to, so a rename and an edit
above the Annotation both lead where the reviewer means (ADR-0010).
There is no guessing: an Annotation on the Review itself, on a line the
diff removed, or on an Anchor that was not found again says so and
leaves point where it is."
  (let* ((annotation (revu-render-placement-annotation placement))
         (target (revu-annotation-target annotation))
         (path (revu-render-placement-path placement)))
    (cond
     ((equal (revu-target-kind target) "review")
      (message "This Annotation is about the Review itself; there is nowhere \
to go"))
     ((equal (revu-target-origin target) "removed")
      (message "That line was removed and is in no file to visit; staying put"))
     ((or (eq (revu-render-placement-state placement) 'orphaned) (null path))
      (message "This Annotation's Anchor was not found again; staying put"))
     (t (revu-visit--file path (revu-render-placement-line placement))))))

;;;###autoload
(defun revu-visit ()
  "Visit what point is on, in the file it stands in today.
On an Annotation that is its Target; on a line of the Source it is that
line.  A line the diff removed is in no file to go to, and so is an
Annotation whose Anchor was not found again: both say so and leave point
where it is, because a Target revu cannot place is not one it will
guess at."
  (interactive)
  (let ((placement (revu-visit--placement)))
    (if placement
        (revu-visit--annotation placement)
      (pcase (get-text-property (line-beginning-position) 'revu-target)
        (`(,path ,line ,origin)
         (if (equal origin "removed")
             (message "That line was removed and is in no file to visit; \
staying put")
           (revu-visit--file path line)))
        (_ (user-error "Point is on nothing revu can visit"))))))

;;;; The canonical keymap

(defvar-keymap revu-mode-map
  :parent magit-section-mode-map
  :doc "Keymap of `revu-mode'.
What magit-section and `special-mode' bind is inherited whole -- folding,
walking the section tree, showing levels, `q' -- and revu's own commands
are laid on top of it (ADR-0010)."
  "a" #'revu-annotate
  "e" #'revu-annotate-edit
  "k" #'revu-annotate-delete
  "r" #'revu-reviewed-toggle
  "E" #'revu-export
  "W" #'revu-export-kill
  "g" #'revu-reload
  "RET" #'revu-visit
  "?" #'revu-dispatch)

;;;; Evil

(defun revu-keymap-bind-evil (map)
  "Bind revu's commands in MAP for evil's normal and motion states.
The mnemonics of the canonical map are kept wherever the letter is not a
motion evil users rely on, and moved where it is: `x' deletes rather than
`k', `gr' reloads rather than `g', and walking and folding go under `g'
and `z' where evil-collection puts them for a magit-section buffer.  The
two Export sinks keep `E' and `W' over evil's WORD motions: a render
nobody edits is not read a WORD at a time.  No initial state is set: the
buffer stays in normal state like any other.

`j', `k', `<down>' and `<up>' are the visual-line motions rather than
evil's logical-line ones.  Going up onto a collapsed section, a logical
motion stops at the visible boundary just before the fold overlay, which
is the *end* of the heading; a visual one keeps the column point was in,
so `k' onto a collapsed heading lands where `j' onto it lands and where
plain `previous-line' has always landed.  evil-collection puts these on
the visual motions in magit's buffers for the same reason.

`revu-reviewed-toggle' is also told to leave the final newline out of a
linewise selection.  Before a command runs, evil widens a `V' selection
to the start of the line after the last one selected, which is the first
character of that section's body, and a region ending there is not a
section selection to `magit-region-sections': it selects nothing, and
`r' would mark only the section point is on.  evil-collection does the
same for magit's own buffers, and only for those."
  (evil-add-command-properties 'revu-reviewed-toggle :exclude-newline t)
  (evil-define-key* '(normal motion) map
                    (kbd "a") #'revu-annotate
                    (kbd "e") #'revu-annotate-edit
                    (kbd "x") #'revu-annotate-delete
                    (kbd "r") #'revu-reviewed-toggle
                    (kbd "E") #'revu-export
                    (kbd "W") #'revu-export-kill
                    (kbd "gr") #'revu-reload
                    (kbd "RET") #'revu-visit
                    (kbd "?") #'revu-dispatch
                    (kbd "q") #'quit-window
                    (kbd "j") #'evil-next-visual-line
                    (kbd "k") #'evil-previous-visual-line
                    (kbd "<down>") #'evil-next-visual-line
                    (kbd "<up>") #'evil-previous-visual-line
                    (kbd "gj") #'magit-section-forward
                    (kbd "gk") #'magit-section-backward
                    (kbd "C-j") #'magit-section-forward
                    (kbd "C-k") #'magit-section-backward
                    (kbd "gh") #'magit-section-up
                    (kbd "]") #'magit-section-forward-sibling
                    (kbd "[") #'magit-section-backward-sibling
                    (kbd "za") #'magit-section-toggle
                    (kbd "zo") #'magit-section-show
                    (kbd "zc") #'magit-section-hide
                    (kbd "zr") #'magit-section-show-level-4-all))

;; Bound when evil is there and not otherwise: revu requires evil in no
;; way, and an Emacs without it must be left exactly as it was.
(when (fboundp 'evil-define-key*)
  (revu-keymap-bind-evil revu-mode-map))

;;;; The palette

;;;###autoload (autoload 'revu-dispatch "revu-keymap" nil t)
(transient-define-prefix revu-dispatch ()
  "Every command a Review is driven by, and every way to start another.
Some live here and nowhere else: writing over what an agent wrote is
meant to take a deliberate detour, and the two render filters are asked
for seldom enough that a key of their own would cost more than it pays
\(ADR-0010).  The rest are here because a palette that lists only what
the reviewer already knows the key for is not a palette."
  [["Annotate"
    ("a" "what point is on" revu-annotate)
    ("l" "the line" revu-annotate-line)
    ("s" "the selection" revu-annotate-range)
    ("h" "the hunk" revu-annotate-hunk)
    ("f" "the file" revu-annotate-file)
    ("R" "the Review" revu-annotate-review)
    ("e" "edit" revu-annotate-edit)
    ("k" "delete" revu-annotate-delete)]
   ["Reviewed"
    ("r" "toggle the mark" revu-reviewed-toggle)
    ("H" "hide what is reviewed" revu-reviewed-toggle-hide-reviewed)
    ("o" "only what is annotated" revu-reviewed-toggle-annotated-only)]]
  [["Sidecar"
    ("g" "reload" revu-reload)
    ("p" "hand over its path" revu-sidecar-path)
    ("!" "write over what is there" revu-force-write)]
   ["Export"
    ("E" "as revdiff markdown" revu-export)
    ("W" "onto the kill ring" revu-export-kill)]
   ["Go"
    ("RET" "visit the Target" revu-visit)]]
  [["This Review"
    ("N" "rename" revu-rename)
    ("O" "open another" revu-open)
    ("D" "discard" revu-discard)]
   ["Review something else"
    ("dw" "the worktree" revu-diff-worktree)
    ("dS" "the worktree since a Revision" revu-diff-since)
    ("ds" "what is staged" revu-diff-staged)
    ("dr" "a range of Revisions" revu-diff-range)
    ("db" "the diff in a buffer" revu-diff-buffer)
    ("dp" "a plain file" revu-file)]])

(provide 'revu-keymap)
;;; revu-keymap.el ends here
