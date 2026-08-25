;;; revu-evil-test.el --- Tests for a Review driven from evil  -*- lexical-binding: t; -*-

;;; Commentary:

;; What a command does when the reviewer drove it from an evil visual
;; selection.  A visual selection is a region plus the two hooks evil
;; hangs on the command loop: `evil-visual-pre-command' widens the region
;; to the selection before the command runs, and `evil-visual-post-command'
;; narrows it back afterwards -- and, narrowing it back, puts point where
;; the markers it kept the selection in say the reviewer was.
;;
;; That is the hazard these tests are here for.  A render erases the
;; buffer, `erase-buffer' does not detach a marker, and so every marker
;; evil left behind collapses to the top of the buffer: without
;; `revu-render--drop-selection' the reviewer who marks a run reviewed is
;; put back on the header at position one instead of on the section after
;; the run.  Nothing about it can be reached with evil absent, which is
;; why evil is a test dependency (Eldev).
;;
;; It is required here and in no other test, so the package still loads
;; with evil absent and `revu-mode-map' is still built the way a vanilla
;; Emacs builds it.

;;; Code:

(require 'ert)
(require 'evil)
(require 'revu-fixture)

(defun revu-evil-test--visual-line (beg end command thunk)
  "Call THUNK as COMMAND, from a visual-line selection of BEG to END.
The hooks are called here because a batch test has no command loop to
call them: what a reviewer's keypress runs is the pre-command hook, the
command, and the post-command hook, in that order, and a test that leaves
any of the three out is not testing the gesture that breaks."
  (evil-local-mode 1)
  (unwind-protect
      (progn
        (evil-visual-make-region beg end 'line)
        (let ((this-command command))
          (evil-visual-pre-command command)
          (unwind-protect (funcall thunk)
            (evil-visual-post-command command))))
    (when (evil-visual-state-p)
      (evil-exit-visual-state))
    (evil-local-mode -1)))

(defmacro revu-evil-test-with-visual-line (beg end command &rest body)
  "Run BODY as COMMAND, from a visual-line selection of BEG to END."
  (declare (indent 3) (debug (form form form body)))
  `(revu-evil-test--visual-line ,beg ,end ,command (lambda () ,@body)))

(ert-deftest revu-evil-marking-a-run-advances-past-it ()
  "A run marked from a `V' selection leaves point after the run, not on top.
The advance is the command's to decide, and evil's post-command hook runs
after it; the hook must find nothing of its own left to put point back
to."
  (revu-fixture-in-repo root
    (revu-fixture-two-hunk-alpha root)
    (with-current-buffer (revu-diff-worktree nil "worktree")
      (revu-evil-test-with-visual-line
          (oref (revu-fixture-hunk-section "alpha.txt" 0) start)
          (oref (revu-fixture-hunk-section "alpha.txt" 1) start)
          'revu-reviewed-toggle
        (revu-reviewed-toggle))
      (should (equal (point)
                     (oref (revu-render-section-with-value "beta.txt") start))))))

(ert-deftest revu-evil-marking-a-run-of-files-advances-past-it ()
  "The same holds for a run of file headings, which is how a run is usually made.
Every file in the run is collapsed, so the reviewer sees headings alone
and selects them with one `V'."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree nil "worktree")
      (revu-evil-test-with-visual-line
          (oref (revu-render-section-with-value "alpha.txt") start)
          (oref (revu-render-section-with-value "beta.txt") start)
          'revu-reviewed-toggle
        (revu-reviewed-toggle))
      (should (equal (point)
                     (oref (revu-render-section-with-value "delta-renamed.txt")
                           start))))))

(ert-deftest revu-evil-marking-the-last-run-stays-on-what-was-marked ()
  "With nothing after the run, point stays as near it as the render allows.
Near it and not at the top of the buffer: having nowhere to advance to is
not the same as having nowhere to be."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree nil "worktree")
      (let ((last (car (last (mapcar #'revu-diff-file-path revu--files)))))
        (revu-evil-test-with-visual-line
            (oref (revu-render-section-with-value "delta-renamed.txt") start)
            (oref (revu-render-section-with-value last) start)
            'revu-reviewed-toggle
          (revu-reviewed-toggle))
        (should (equal (point)
                       (oref (revu-render-section-with-value last) start)))))))

(ert-deftest revu-evil-annotating-a-range-keeps-the-reviewer-on-their-line ()
  "An Annotation taken over a `V\=' selection leaves point on the Source.
`revu-annotate\=' renders too, so it collapses evil\='s markers exactly as
marking does, and without the guard it puts the reviewer on the header at
the top of the buffer.  Which line of the selection they come back to is
evil\='s to say -- it is the one its own markers name -- so what is asserted
here is what revu answers for: they are still on the lines they were
reading."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree nil "worktree")
      (revu-fixture-goto-line-matching revu-fixture-worktree-seven)
      (revu-evil-test-with-visual-line
          (line-beginning-position) (line-beginning-position 2) 'revu-annotate
        (revu-annotate "note" "over a run of lines"))
      (should (string-match-p "over a run of lines" (revu-fixture-render)))
      (should-not (equal (point) (point-min)))
      (should (equal (car (get-text-property (line-beginning-position)
                                             'revu-target))
                     "alpha.txt")))))

(provide 'revu-evil-test)
;;; revu-evil-test.el ends here
