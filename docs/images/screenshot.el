;;; screenshot.el --- Open the Review the README screenshot shows  -*- lexical-binding: t; -*-

;; Run from the repository root with
;;
;;   eldev emacs -l docs/images/screenshot.el
;;
;; It builds the test fixture repository, reviews its worktree against
;; HEAD, adds one Annotation of each Kind and marks one hunk reviewed,
;; then leaves the Review buffer on screen.  Take the picture, then quit
;; Emacs; the fixture repository is deleted on exit.
;;
;; In batch mode (`eldev emacs --batch -l docs/images/screenshot.el') it
;; prints the rendered buffer, the Sidecar and the Export instead.

(require 'revu)
(require 'revu-fixture)

(defvar screenshot--root (revu-fixture-make-repo))

(add-hook 'kill-emacs-hook
          (lambda () (delete-directory screenshot--root t)))

(let ((default-directory screenshot--root))
  (revu-fixture-write-file
   screenshot--root "alpha.txt"
   (thread-last revu-fixture-alpha-baseline
                (replace-regexp-in-string "alpha two\n" "alpha two\nalpha two and a half\n")
                (replace-regexp-in-string "alpha seven" "alpha seven in the worktree")))
  (revu-fixture-write-file screenshot--root "src/parser.py"
                           "def parse(text):\n    return text.split()\n")
  (with-current-buffer (revu-diff-worktree nil "worktree")
    (revu-fixture-goto-line-matching "^\\+alpha two and a half$")
    (revu-annotate-line "question" "Is this line meant to be here, or is it a leftover from the rebase?")
    (revu-fixture-goto-line-matching "^\\+alpha seven in the worktree$")
    (revu-annotate-line "change" "Drop the suffix. The file name already says which tree this is.")
    (revu-fixture-goto-line-matching "^\\+    return text.split()$")
    (revu-annotate-file "note" "New module. Nothing imports it yet.")
    (revu-fixture-goto-line-matching "beta two staged")
    (revu-reviewed-toggle)
    (goto-char (point-min))
    (revu-export)
    (when noninteractive
      (princ (revu-fixture-render))
      (princ "\n=== SIDECAR ===\n")
      (princ (revu-fixture-sidecar-text screenshot--root "worktree"))
      (princ "\n=== EXPORT ===\n")
      (princ (revu-fixture-file-contents screenshot--root ".revu/exports/worktree.md")))
    (unless noninteractive
      (delete-other-windows)
      (switch-to-buffer (current-buffer)))))

;;; screenshot.el ends here
