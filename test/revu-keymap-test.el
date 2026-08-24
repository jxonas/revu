;;; revu-keymap-test.el --- Tests for the keymap, evil block and palette  -*- lexical-binding: t; -*-

;;; Commentary:

;; Tests for what a Review is driven by: the canonical keymap over the
;; magit-section natives it is laid on, the guarded evil block, the
;; dispatch palette, and the command that visits a Target.  Keys are
;; asserted by driving them in a review buffer over the fixture
;; repository and reading the result where the reviewer and their agent
;; read it: the Sidecar on disk and the rendered buffer.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'ert-x)
(require 'magit-section)
(require 'revu)
(require 'revu-fixture)

(defun revu-keymap-test--press (key)
  "Run whatever KEY runs in the current review buffer."
  (let ((command (key-binding (kbd key))))
    (should command)
    (call-interactively command)))

(defun revu-keymap-test--annotations (root name)
  "Return the Annotations the Sidecar called NAME under ROOT holds, as a list."
  (append (revu-review-annotations (revu-fixture-sidecar root name)) nil))

(defmacro revu-keymap-test--answering (kind body &rest forms)
  "Run FORMS with the Kind and body prompts answered by KIND and BODY."
  (declare (indent 2))
  `(cl-letf (((symbol-function 'revu-annotate--read-kind) (lambda () ,kind))
             ((symbol-function 'revu-annotate--read-body)
              (lambda (&optional _initial) ,body)))
     ,@forms))

(defun revu-keymap-test--kill-file-buffers (root)
  "Kill every buffer visiting a file under ROOT."
  (dolist (buffer (buffer-list))
    (when (and (buffer-file-name buffer)
               (string-prefix-p (file-truename root)
                                (file-truename (buffer-file-name buffer))))
      (with-current-buffer buffer (set-buffer-modified-p nil))
      (kill-buffer buffer))))

;;;; The canonical map

(ert-deftest revu-keymap-binds-every-command-of-the-canonical-map ()
  "Each key ADR-0010 names runs the command it names, in a review buffer."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree "worktree")
      (should (eq (key-binding (kbd "a")) 'revu-annotate))
      (should (eq (key-binding (kbd "e")) 'revu-annotate-edit))
      (should (eq (key-binding (kbd "k")) 'revu-annotate-delete))
      (should (eq (key-binding (kbd "r")) 'revu-reviewed-toggle))
      (should (eq (key-binding (kbd "E")) 'revu-export))
      (should (eq (key-binding (kbd "g")) 'revu-reload))
      (should (eq (key-binding (kbd "RET")) 'revu-visit))
      (should (eq (key-binding (kbd "?")) 'revu-dispatch)))))

(ert-deftest revu-keymap-keeps-the-magit-section-natives ()
  "Folding, walking the tree and burying the buffer are left as they were.
The canonical map is laid on top of magit-section's and `special-mode's,
never in place of them."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree "worktree")
      (should (eq (key-binding (kbd "TAB")) 'magit-section-toggle))
      (should (eq (key-binding (kbd "<backtab>")) 'magit-section-cycle-global))
      (should (eq (key-binding (kbd "n")) 'magit-section-forward))
      (should (eq (key-binding (kbd "p")) 'magit-section-backward))
      (should (eq (key-binding (kbd "M-n")) 'magit-section-forward-sibling))
      (should (eq (key-binding (kbd "M-p")) 'magit-section-backward-sibling))
      (should (eq (key-binding (kbd "^")) 'magit-section-up))
      (should (eq (key-binding (kbd "1")) 'magit-section-show-level-1))
      (should (eq (key-binding (kbd "2")) 'magit-section-show-level-2))
      (should (eq (key-binding (kbd "3")) 'magit-section-show-level-3))
      (should (eq (key-binding (kbd "4")) 'magit-section-show-level-4))
      (should (eq (key-binding (kbd "q")) 'quit-window))
      (should (eq (key-binding (kbd "SPC")) 'scroll-up-command)))))

(ert-deftest revu-keymap-a-adds-and-k-deletes-an-annotation ()
  "`a' writes an Annotation to the Sidecar and `k' takes it away again."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree "worktree")
      (revu-fixture-goto-line-matching "^ +7 \\+alpha seven in the worktree$")
      (revu-keymap-test--answering "question" "Is seven the right one?"
        (revu-keymap-test--press "a"))
      (let ((annotations (revu-keymap-test--annotations root "worktree")))
        (should (equal (length annotations) 1))
        (should (equal (revu-annotation-body (car annotations))
                       "Is seven the right one?")))
      (should (string-match-p "Is seven the right one\\?"
                              (revu-fixture-render)))
      (revu-fixture-goto-line-matching "Is seven the right one")
      (revu-keymap-test--press "k")
      (should (equal (revu-keymap-test--annotations root "worktree") nil))
      (should-not (string-match-p "Is seven the right one\\?"
                                  (revu-fixture-render))))))

(ert-deftest revu-keymap-e-rewrites-the-annotation-body ()
  "`e' rewrites the body of the Annotation point is in."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree "worktree")
      (revu-fixture-goto-line-matching "^ +7 \\+alpha seven in the worktree$")
      (revu-annotate-line "note" "First words")
      (revu-fixture-goto-line-matching "First words")
      (revu-keymap-test--answering "note" "Better words"
        (revu-keymap-test--press "e"))
      (let ((annotations (revu-keymap-test--annotations root "worktree")))
        (should (equal (length annotations) 1))
        (should (equal (revu-annotation-body (car annotations))
                       "Better words")))
      (should (string-match-p "Better words" (revu-fixture-render))))))

(ert-deftest revu-keymap-r-marks-the-hunk-reviewed ()
  "`r' writes a Reviewed mark over the hunk point is in."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree "worktree")
      (revu-fixture-goto-line-matching "^ +7 \\+alpha seven in the worktree$")
      (revu-keymap-test--press "r")
      (should (equal (length (revu-review-marks
                              (revu-fixture-sidecar root "worktree")))
                     1)))))

(ert-deftest revu-keymap-e-uppercase-exports-the-review ()
  "`E' writes the Review out as revdiff markdown beside the Sidecar."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree "worktree")
      (revu-fixture-goto-line-matching "^ +7 \\+alpha seven in the worktree$")
      (revu-annotate-line "note" "Worth a look")
      (revu-keymap-test--press "E")
      (let ((file (expand-file-name ".revu/worktree.md" root)))
        (should (file-regular-p file))
        (should (equal (revu-fixture-file-contents root ".revu/worktree.md")
                       "## alpha.txt:7 (+)\nWorth a look\n"))))))

(ert-deftest revu-keymap-g-reloads-the-source-and-the-sidecar ()
  "`g' reads the Source anew, so what the worktree says now is what renders."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree "worktree")
      (should-not (string-match-p "alpha two rewritten" (revu-fixture-render)))
      (revu-fixture-write-file
       root "alpha.txt"
       (replace-regexp-in-string "alpha two" "alpha two rewritten"
                                 revu-fixture-alpha-baseline t t))
      (revu-keymap-test--press "g")
      (should (string-match-p "alpha two rewritten" (revu-fixture-render))))))

;;;; Evil

(ert-deftest revu-keymap-leaves-a-vanilla-emacs-alone ()
  "With no evil loaded the guarded block never runs and binds nothing.
`x' and `gr' mean in a review buffer exactly what they meant before, and
deleting an Annotation is on `k' where the canonical map put it."
  (should-not (fboundp 'evil-define-key*))
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree "worktree")
      (should (eq (key-binding (kbd "x")) 'undefined))
      ;; `g' is the reload command outright, not evil's prefix, so there
      ;; is no `gr' or `gj' under it, and no `z' or bracket prefix either.
      (should (eq (keymap-lookup revu-mode-map "g") 'revu-reload))
      (should-not (keymapp (keymap-lookup revu-mode-map "g")))
      (should-not (keymap-lookup revu-mode-map "z"))
      (should-not (keymap-lookup revu-mode-map "["))
      (should-not (keymap-lookup revu-mode-map "C-j"))
      (should (eq (key-binding (kbd "k")) 'revu-annotate-delete)))))

(defun revu-keymap-test--evil-map ()
  "Return a keymap carrying what the evil block binds, with evil stood in for.
The stand-in binds each key of each state into one map, which is enough
to say which command a key runs -- the point of the test is the
conventions, not evil's state machinery."
  (let ((map (make-sparse-keymap)))
    (cl-letf (((symbol-function 'evil-define-key*)
               (lambda (_states keymap &rest bindings)
                 (while bindings
                   (keymap-set keymap (key-description (pop bindings))
                               (pop bindings))))))
      (revu-keymap-bind-evil map))
    map))

(ert-deftest revu-keymap-evil-bindings-follow-evil-collection-conventions ()
  "The evil block keeps the mnemonics and moves what evil needs as a motion.
`x' deletes, `gr' reloads, `gj'/`gk' and `C-j'/`C-k' walk sections, `gh'
goes up, the brackets walk siblings and the `z' keys fold -- what
evil-collection does for a magit-section buffer, bound by revu itself."
  (let ((map (revu-keymap-test--evil-map)))
    (should (eq (keymap-lookup map "a") 'revu-annotate))
    (should (eq (keymap-lookup map "e") 'revu-annotate-edit))
    (should (eq (keymap-lookup map "x") 'revu-annotate-delete))
    (should (eq (keymap-lookup map "r") 'revu-reviewed-toggle))
    (should (eq (keymap-lookup map "E") 'revu-export))
    (should (eq (keymap-lookup map "g r") 'revu-reload))
    (should (eq (keymap-lookup map "RET") 'revu-visit))
    (should (eq (keymap-lookup map "?") 'revu-dispatch))
    (should (eq (keymap-lookup map "q") 'quit-window))
    (should (eq (keymap-lookup map "g j") 'magit-section-forward))
    (should (eq (keymap-lookup map "g k") 'magit-section-backward))
    (should (eq (keymap-lookup map "C-j") 'magit-section-forward))
    (should (eq (keymap-lookup map "C-k") 'magit-section-backward))
    (should (eq (keymap-lookup map "g h") 'magit-section-up))
    (should (eq (keymap-lookup map "]") 'magit-section-forward-sibling))
    (should (eq (keymap-lookup map "[") 'magit-section-backward-sibling))
    (should (eq (keymap-lookup map "z a") 'magit-section-toggle))
    (should (eq (keymap-lookup map "z o") 'magit-section-show))
    (should (eq (keymap-lookup map "z c") 'magit-section-hide))
    (should (eq (keymap-lookup map "z r") 'magit-section-show-level-4-all))
    ;; `k' is a motion under evil, so deleting moved off it entirely.
    (should-not (keymap-lookup map "k"))))

;;;; The palette

(defun revu-keymap-test--palette ()
  "Return the commands `revu-dispatch' offers."
  (let ((commands nil))
    (cl-labels ((walk (node)
                  (cond
                   ((vectorp node) (mapc #'walk (append node nil)))
                   ((and (consp node) (symbolp (car node))
                         (plist-get (cdr node) :command))
                    (push (plist-get (cdr node) :command) commands))
                   ((consp node) (mapc #'walk node)))))
      (walk (get 'revu-dispatch 'transient--layout)))
    (nreverse commands)))

(ert-deftest revu-dispatch-offers-the-whole-command-set ()
  "The palette is complete: every command a Review is driven by is in it."
  (should (equal (sort (revu-keymap-test--palette) #'string<)
                 (sort (list 'revu-annotate
                             'revu-annotate-line
                             'revu-annotate-range
                             'revu-annotate-hunk
                             'revu-annotate-file
                             'revu-annotate-review
                             'revu-annotate-edit
                             'revu-annotate-delete
                             'revu-reviewed-toggle
                             'revu-reviewed-toggle-hide-reviewed
                             'revu-reviewed-toggle-annotated-only
                             'revu-reload
                             'revu-sidecar-path
                             'revu-force-write
                             'revu-export
                             'revu-visit
                             ;; Starting a Review is a command a Review is
                             ;; driven by too: story 36 asks the palette to
                             ;; list every command, and the entry commands
                             ;; have no key of their own to be found by.
                             'revu-diff-worktree
                             'revu-diff-staged
                             'revu-diff-range
                             'revu-diff-buffer
                             'revu-file)
                       #'string<))))

(ert-deftest revu-dispatch-is-the-only-way-to-three-commands ()
  "Force-write and the two render filters are reachable through `?' alone.
Writing over what an agent wrote is meant to cost a detour, and the
filters are asked for too seldom to be worth a letter (ADR-0010)."
  (let ((evil (revu-keymap-test--evil-map)))
    (dolist (command '(revu-force-write
                       revu-reviewed-toggle-hide-reviewed
                       revu-reviewed-toggle-annotated-only))
      (should (memq command (revu-keymap-test--palette)))
      (should-not (where-is-internal command (list revu-mode-map)))
      (should-not (where-is-internal command (list evil))))))

;;;; Visiting a Target

(ert-deftest revu-visit-goes-to-the-line-the-annotation-is-on ()
  "`RET' on an Annotation opens its file with point on the line it is about."
  (revu-fixture-in-repo root
    (unwind-protect
        (with-current-buffer (revu-diff-worktree "worktree")
          (revu-fixture-goto-line-matching
           "^ +7 \\+alpha seven in the worktree$")
          (revu-annotate-line "note" "Right here")
          (revu-fixture-goto-line-matching "Right here")
          (revu-keymap-test--press "RET")
          (should (equal (file-truename (buffer-file-name))
                         (file-truename (expand-file-name "alpha.txt" root))))
          (should (equal (line-number-at-pos) 7)))
      (revu-keymap-test--kill-file-buffers root))))

(ert-deftest revu-visit-follows-an-anchor-that-moved ()
  "`RET' goes to where the Anchor was re-located, not to the recorded number.
The line is what the reviewer wrote about; the number it had is not."
  (revu-fixture-in-repo root
    (unwind-protect
        (with-current-buffer (revu-diff-worktree "worktree")
          (revu-fixture-goto-line-matching
           "^ +7 \\+alpha seven in the worktree$")
          (revu-annotate-line "note" "Follow me")
          ;; Two lines put in above it push the anchored line down.
          (revu-fixture-write-file
           root "alpha.txt"
           (concat "alpha zero\nalpha minus one\n"
                   (replace-regexp-in-string
                    "alpha seven" "alpha seven in the worktree"
                    revu-fixture-alpha-baseline t t)))
          (revu-fixture-goto-line-matching "Follow me")
          (revu-keymap-test--press "RET")
          (should (equal (file-truename (buffer-file-name))
                         (file-truename (expand-file-name "alpha.txt" root))))
          (should (equal (line-number-at-pos) 9)))
      (revu-keymap-test--kill-file-buffers root))))

(ert-deftest revu-visit-stays-put-on-an-orphaned-anchor ()
  "An Anchor that was not found again is not guessed at: point does not move."
  (revu-fixture-in-repo root
    (unwind-protect
        (with-current-buffer (revu-diff-worktree "worktree")
          (revu-fixture-goto-line-matching
           "^ +7 \\+alpha seven in the worktree$")
          (revu-annotate-line "note" "Gone tomorrow")
          (revu-fixture-write-file root "alpha.txt"
                                   "nothing\nof\nthe\nold\nfile\nis\nleft\n")
          (revu-fixture-goto-line-matching "Gone tomorrow")
          (let ((buffer (current-buffer))
                (start (point))
                (said (ert-with-message-capture said
                        (revu-keymap-test--press "RET")
                        said)))
            (should (string-match-p "staying put" said))
            (should (eq (current-buffer) buffer))
            (should (equal (point) start))))
      (revu-keymap-test--kill-file-buffers root))))

(ert-deftest revu-visit-stays-put-on-a-removed-line ()
  "A line the diff removed is in no file to go to, and `RET' says so."
  (revu-fixture-in-repo root
    (unwind-protect
        (with-current-buffer (revu-diff-worktree "worktree")
          (revu-fixture-goto-line-matching "^ +7 -alpha seven$")
          (revu-annotate-line "note" "Why did this go?")
          (revu-fixture-goto-line-matching "Why did this go")
          (let ((buffer (current-buffer))
                (start (point))
                (said (ert-with-message-capture said
                        (revu-keymap-test--press "RET")
                        said)))
            (should (string-match-p "staying put" said))
            (should (eq (current-buffer) buffer))
            (should (equal (point) start))))
      (revu-keymap-test--kill-file-buffers root))))

(ert-deftest revu-visit-goes-to-the-source-line-point-is-on ()
  "`RET' on a line of the Source itself opens the file at that line."
  (revu-fixture-in-repo root
    (unwind-protect
        (with-current-buffer (revu-diff-worktree "worktree")
          (revu-fixture-goto-line-matching
           "^ +7 \\+alpha seven in the worktree$")
          (revu-keymap-test--press "RET")
          (should (equal (file-truename (buffer-file-name))
                         (file-truename (expand-file-name "alpha.txt" root))))
          (should (equal (line-number-at-pos) 7)))
      (revu-keymap-test--kill-file-buffers root))))

(provide 'revu-keymap-test)
;;; revu-keymap-test.el ends here
