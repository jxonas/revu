;;; revu-review-test.el --- Tests for naming, reopening and discarding  -*- lexical-binding: t; -*-

;;; Commentary:

;; Tests for what a Review is called and how long it lives: the scratch
;; bucket a Source opens in, what resuming one says out loud, and the
;; three commands that give a Review a name, bring it back and throw it
;; away (ADR-0005's amendment).

;;; Code:

(require 'ert)
(require 'ert-x)
(require 'cl-lib)
(require 'revu)
(require 'revu-fixture)

(defun revu-review-test--sidecar-file (root name)
  "Return the Sidecar file of the Review called NAME under ROOT."
  (expand-file-name (format ".revu/reviews/%s.json" name) root))

(defun revu-review-test--export-file (root name)
  "Return the Export file of the Review called NAME under ROOT."
  (expand-file-name (format ".revu/exports/%s.md" name) root))

(defun revu-review-test--annotate-and-export (line body)
  "Annotate the rendered line matching LINE with BODY and write the Export."
  (revu-fixture-goto-line-matching line)
  (revu-annotate-line "note" body)
  (revu-export))

(defun revu-review-test--touch-sidecar (root name)
  "Write over the Sidecar called NAME under ROOT, as an agent would.
The Review stays valid and the bytes change, which is exactly what the
write guard blocks on."
  (let* ((file (revu-review-test--sidecar-file root name))
         (review (revu-review-add-annotation
                  (revu-sidecar-review (revu-sidecar-load file))
                  (revu-annotation-create "note" (revu-target-review)
                                          "The agent got here first"))))
    (write-region (revu-review-encode review) nil file nil 'silent)
    ;; A write inside the same second leaves the modification time where
    ;; it was, and the guard would read the file as untouched.
    (set-file-times file (time-add (current-time) 2))))

;;;; The scratch bucket

(ert-deftest revu-resuming-a-review-echoes-what-it-picked-up ()
  "Opening a Review that carries Annotations says how many, and how many orphaned."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree "worktree")
      (revu-fixture-goto-line-matching "^\\+beta two staged$")
      (revu-annotate-line "note" "Still here tomorrow")
      (revu-fixture-goto-line-matching "^ beta one$")
      (revu-annotate-line "note" "And this one"))
    (revu-fixture-kill-review-buffers)
    (let ((echoed (ert-with-message-capture messages
                    (revu-diff-worktree "worktree")
                    messages)))
      (should (string-match-p "Resumed worktree: 2 Annotations (0 orphaned)"
                              echoed)))))

(ert-deftest revu-resuming-a-review-counts-the-annotations-it-lost ()
  "An Annotation whose lines are gone is counted as orphaned in the echo."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree "worktree")
      (revu-fixture-goto-line-matching "^\\+beta two staged$")
      (revu-annotate-line "note" "About to be lost"))
    (revu-fixture-kill-review-buffers)
    (revu-fixture-write-file root "beta.txt" "nothing like what it was\n")
    (let ((echoed (ert-with-message-capture messages
                    (revu-diff-worktree "worktree")
                    messages)))
      (should (string-match-p "Resumed worktree: 1 Annotation (1 orphaned)"
                              echoed)))))

(ert-deftest revu-opening-an-empty-review-says-nothing ()
  "A Review with nothing in it resumes silently: there is nothing to warn of."
  (revu-fixture-in-repo root
    (save-current-buffer (revu-diff-worktree "worktree"))
    (revu-fixture-kill-review-buffers)
    (let ((echoed (ert-with-message-capture messages
                    (revu-diff-worktree "worktree")
                    messages)))
      (should-not (string-match-p "Resumed" echoed)))))

;;;; Renaming

(ert-deftest revu-rename-moves-the-sidecar-the-export-and-the-buffer ()
  "A Review kept is renamed whole: both files move and the buffer follows."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree "worktree")
      (revu-review-test--annotate-and-export "^\\+beta two staged$" "Worth keeping")
      (should (file-exists-p (revu-review-test--export-file root "worktree")))
      (revu-rename "beta-rework")
      (should (equal (buffer-name) (revu-buffer-name "beta-rework")))
      (should (equal (revu-review-name (revu-review)) "beta-rework")))
    (should (file-exists-p (revu-review-test--sidecar-file root "beta-rework")))
    (should-not (file-exists-p (revu-review-test--sidecar-file root "worktree")))
    (should (file-exists-p (revu-review-test--export-file root "beta-rework")))
    (should-not (file-exists-p (revu-review-test--export-file root "worktree")))
    (should (equal (revu-review-name (revu-fixture-sidecar root "beta-rework"))
                   "beta-rework"))))

(ert-deftest revu-rename-keeps-annotating-under-the-new-name ()
  "The renamed buffer writes to the Sidecar that moved, not the one that left."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree "worktree")
      (revu-rename "beta-rework")
      (revu-fixture-goto-line-matching "^\\+beta two staged$")
      (revu-annotate-line "note" "Written after the rename"))
    (should (equal (seq-length (revu-review-annotations
                                (revu-fixture-sidecar root "beta-rework")))
                   1))
    (should-not (revu-fixture-sidecar root "worktree"))))

(ert-deftest revu-rename-refuses-a-name-another-review-has ()
  "Renaming never writes over the Review already under that name."
  (revu-fixture-in-repo root
    (save-current-buffer (revu-diff-staged "staged"))
    (with-current-buffer (revu-diff-worktree "worktree")
      (should-error (revu-rename "staged") :type 'user-error))
    (should (file-exists-p (revu-review-test--sidecar-file root "worktree")))
    (should (equal (revu-source-kind
                    (revu-review-source (revu-fixture-sidecar root "staged")))
                   "staged"))))

(ert-deftest revu-rename-refuses-a-name-that-is-a-path ()
  "A name is a file name under `reviews/', never a way out of it."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree "worktree")
      (should-error (revu-rename "../escaped") :type 'user-error)
      (should-error (revu-rename "") :type 'user-error)
      (should (equal (revu-review-name (revu-review)) "worktree")))
    (should (file-exists-p (revu-review-test--sidecar-file root "worktree")))))

(ert-deftest revu-rename-refuses-a-name-a-stray-export-sits-under ()
  "Neither file moves onto one somebody left behind under the new name."
  (revu-fixture-in-repo root
    (let ((stray (revu-review-test--export-file root "beta-rework")))
      (make-directory (file-name-directory stray) t)
      (write-region "left behind\n" nil stray nil 'silent)
      (with-current-buffer (revu-diff-worktree "worktree")
        (revu-review-test--annotate-and-export "^\\+beta two staged$" "Mine")
        (should-error (revu-rename "beta-rework") :type 'user-error))
      (should (equal (revu-fixture-file-contents
                      (file-name-directory stray)
                      (file-name-nondirectory stray))
                     "left behind\n"))
      (should (file-exists-p (revu-review-test--sidecar-file root "worktree"))))))

(ert-deftest revu-rename-refuses-under-the-write-guard ()
  "A Sidecar an agent wrote to since revu read it is not moved out from under it."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree "worktree")
      (revu-fixture-goto-line-matching "^\\+beta two staged$")
      (revu-annotate-line "note" "Mine")
      (revu-review-test--touch-sidecar root "worktree")
      (should-error (revu-rename "beta-rework") :type 'revu-sidecar-changed))
    (should (file-exists-p (revu-review-test--sidecar-file root "worktree")))
    (should-not (file-exists-p (revu-review-test--sidecar-file root "beta-rework")))))

;;;; Opening one that is already there

(ert-deftest revu-open-lists-every-sidecar-newest-first ()
  "Every Review on disk is offered, most recently updated first."
  (revu-fixture-in-repo root
    (save-current-buffer (revu-diff-staged "staged"))
    (save-current-buffer (revu-diff-worktree "worktree"))
    (with-current-buffer (revu-buffer-name "worktree")
      (revu-rename "beta-rework"))
    (let (offered scratch)
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (_prompt table &rest _)
                   (setq offered (all-completions "" table))
                   (setq scratch
                         (seq-filter
                          (lambda (name)
                            (funcall (cdr (assq 'annotation-function
                                                (cdr (funcall table "" nil
                                                              'metadata))))
                                     name))
                          offered))
                   "staged")))
        (revu-open))
      (should (equal offered '("beta-rework" "staged")))
      ;; The one still called what its Source derives is the scratch
      ;; bucket, and says so.
      (should (equal scratch '("staged"))))
    (should (get-buffer (revu-buffer-name "staged")))))

(ert-deftest revu-open-reopens-a-review-over-its-recorded-source ()
  "What a Review is over comes from its record, not from what is on screen."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-staged "staged")
      (revu-fixture-goto-line-matching "^\\+beta two staged$")
      (revu-annotate-line "note" "Staged, and stays staged"))
    (revu-fixture-kill-review-buffers)
    (with-current-buffer (revu-open "staged")
      (should (equal (revu-source-kind (revu-review-source (revu-review)))
                     "staged"))
      (should (string-match-p "Staged, and stays staged" (revu-fixture-render))))))

(ert-deftest revu-open-reopens-a-narrowed-review-through-its-narrowing ()
  "A narrowed Review comes back narrowed: the Narrowing is part of its Source."
  (revu-fixture-in-repo root
    (save-current-buffer (revu-diff-worktree nil '("beta.txt")))
    (revu-fixture-kill-review-buffers)
    (with-current-buffer (revu-open "worktree--beta.txt")
      (should (equal (revu-source-paths (revu-review-source (revu-review)))
                     '("beta.txt")))
      (let ((rendered (revu-fixture-render)))
        (should (string-match-p "beta\\.txt" rendered))
        (should-not (string-match-p "alpha\\.txt" rendered))))))

(ert-deftest revu-open-refuses-when-there-is-nothing-to-open ()
  "A project with no Review says so rather than offering an empty prompt."
  (revu-fixture-in-repo root
    (should-error (revu-open) :type 'user-error)))

;;;; Discarding

(ert-deftest revu-discard-removes-both-files-and-kills-the-buffer ()
  "Discarding a Review leaves nothing of it behind."
  (revu-fixture-in-repo root
    (let ((buffer (revu-diff-worktree "worktree")))
      (with-current-buffer buffer
        (revu-review-test--annotate-and-export "^\\+beta two staged$" "Never mind")
        (should (file-exists-p (revu-review-test--export-file root "worktree")))
        (revu-discard))
      (should-not (buffer-live-p buffer)))
    (should-not (file-exists-p (revu-review-test--sidecar-file root "worktree")))
    (should-not (file-exists-p (revu-review-test--export-file root "worktree")))))

(ert-deftest revu-discard-refuses-under-the-write-guard ()
  "What an agent wrote is not deleted by a reviewer who has not read it."
  (revu-fixture-in-repo root
    (let ((buffer (revu-diff-worktree "worktree")))
      (with-current-buffer buffer
        (revu-fixture-goto-line-matching "^\\+beta two staged$")
        (revu-annotate-line "note" "Mine")
        (revu-review-test--touch-sidecar root "worktree")
        (should-error (revu-discard) :type 'revu-sidecar-changed))
      (should (buffer-live-p buffer)))
    (should (file-exists-p (revu-review-test--sidecar-file root "worktree")))))

;;;; A Source with nothing in it

(defun revu-review-test--commit-everything (root)
  "Commit everything the fixture repository at ROOT carries.
Nothing is then staged and the worktree matches HEAD, which is the state
a reviewer who reaches for revu in the wrong project is in."
  (revu-fixture-git-output root "add" "-A")
  (revu-fixture-git-output root "commit" "-q" "-m" "Everything"))

(ert-deftest revu-staged-refuses-an-empty-index-and-says-where ()
  "An empty index refuses by name rather than opening an empty buffer."
  (revu-fixture-in-repo root
    (revu-review-test--commit-everything root)
    (let ((message (cadr (should-error (revu-diff-staged) :type 'user-error))))
      (should (string-match-p "staged" message))
      (should (string-match-p (regexp-quote (file-truename root)) message)))
    (should-not (revu-fixture-sidecar root "staged"))
    (should-not (get-buffer (revu-buffer-name "staged")))))

(ert-deftest revu-worktree-refuses-a-worktree-that-matches-head ()
  "A worktree carrying nothing HEAD does not opens no Review."
  (revu-fixture-in-repo root
    (revu-review-test--commit-everything root)
    (let ((message (cadr (should-error (revu-diff-worktree) :type 'user-error))))
      (should (string-match-p "worktree" message))
      (should (string-match-p (regexp-quote (file-truename root)) message)))
    (should-not (revu-fixture-sidecar root "worktree"))))

(ert-deftest revu-range-refuses-two-revisions-that-differ-by-nothing ()
  "A range whose ends hold the same tree is a Review of nothing."
  (revu-fixture-in-repo root
    (let ((message (cadr (should-error (revu-diff-range "HEAD" "HEAD")
                                       :type 'user-error))))
      (should (string-match-p "HEAD\\.\\.HEAD" message)))))

(ert-deftest revu-narrowing-that-matches-nothing-names-the-pathspecs ()
  "A Narrowing the Source has no file under says which pathspecs those were."
  (revu-fixture-in-repo root
    (let ((message (cadr (should-error (revu-diff-staged nil '("README.md"))
                                       :type 'user-error))))
      (should (string-match-p "README\\.md" message)))
    (should-not (revu-fixture-sidecar root "staged-README.md"))))

(provide 'revu-review-test)
;;; revu-review-test.el ends here
