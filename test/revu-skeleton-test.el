;;; revu-skeleton-test.el --- Tests for the revu package skeleton  -*- lexical-binding: t; -*-

;;; Commentary:

;; Tests for the fixture git repository builder and for the helpers that
;; resolve a project root and the Sidecar path inside it.

;;; Code:

(require 'ert)
(require 'revu)
(require 'revu-fixture)

(defun revu-skeleton-test--status (root)
  "Return the porcelain status lines of the fixture repository at ROOT."
  (split-string (revu-fixture-git-output root "status" "--porcelain") "\n" t))

(ert-deftest revu-declared-dependencies-are-available ()
  "The dependencies revu declares resolve and load."
  (should (require 'magit-section nil t))
  (should (require 'transient nil t))
  (should (fboundp 'magit-insert-section))
  (should (fboundp 'transient-define-prefix)))

(ert-deftest revu-fixture-builds-a-git-repository-on-main ()
  "The fixture builder leaves a git repository whose branch is main."
  (revu-fixture-with-repo root
    (should (file-directory-p (expand-file-name ".git" root)))
    (should (equal (revu-fixture-git-output root "rev-parse" "--abbrev-ref" "HEAD")
                   "main"))))

(ert-deftest revu-fixture-carries-a-committed-baseline ()
  "The fixture baseline commit holds every file the tests review."
  (revu-fixture-with-repo root
    (let ((tracked (split-string
                    (revu-fixture-git-output root "ls-tree" "-r" "--name-only" "main")
                    "\n" t)))
      (should (member "alpha.txt" tracked))
      (should (member "beta.txt" tracked))
      (should (member "gamma.txt" tracked))
      (should (member "delta.txt" tracked))
      (should (member "README.md" tracked)))))

(ert-deftest revu-fixture-carries-staged-and-worktree-changes ()
  "The fixture repository shows staged changes and unstaged worktree changes."
  (revu-fixture-with-repo root
    (let ((status (revu-skeleton-test--status root)))
      ;; Staged: a modification, a rename and a deletion.
      (should (member "M  beta.txt" status))
      (should (member "R  delta.txt -> delta-renamed.txt" status))
      (should (member "D  gamma.txt" status))
      ;; Unstaged: a worktree modification that is not staged.
      (should (member " M alpha.txt" status))
      ;; A plain file that no diff touches.
      (should-not (seq-find (lambda (line) (string-suffix-p "README.md" line))
                            status)))))

(ert-deftest revu-fixture-carries-a-second-branch-for-a-range ()
  "The fixture repository has a second branch that changes a baseline file."
  (revu-fixture-with-repo root
    (let ((branches (split-string
                     (revu-fixture-git-output root "branch" "--format=%(refname:short)")
                     "\n" t)))
      (should (member "main" branches))
      (should (member "feature" branches)))
    (should (string-match-p
             "alpha three on feature"
             (revu-fixture-git-output root "diff" "main..feature")))))

(ert-deftest revu-project-root-resolves-the-enclosing-repository ()
  "`revu-project-root' returns the repository root of a file under it."
  (revu-fixture-with-repo root
    (should (equal (revu-project-root (expand-file-name "alpha.txt" root))
                   (file-name-as-directory (file-truename root))))))

(ert-deftest revu-project-root-refuses-a-path-outside-a-project ()
  "`revu-project-root' refuses a path that belongs to no project."
  (let ((orphan (file-name-as-directory (make-temp-file "revu-orphan-" t))))
    (unwind-protect
        (should-error (revu-project-root (expand-file-name "loose.txt" orphan))
                      :type 'user-error)
      (delete-directory orphan t))))

(ert-deftest revu-sidecar-file-name-lives-under-the-project-root ()
  "The Sidecar of a Review is named after it under the project's reviews directory."
  (revu-fixture-with-repo root
    (let ((sidecar (revu-sidecar-file-name "worktree" root)))
      (should (equal sidecar
                     (expand-file-name ".revu/reviews/worktree.json"
                                       (file-truename root))))
      ;; Naming a file is not writing one: nothing is created until a
      ;; command has something to put there.
      (should-not (file-exists-p (file-name-directory sidecar)))
      (should-not (file-exists-p sidecar)))))

(ert-deftest revu-export-file-name-lives-beside-the-reviews-directory ()
  "An Export is named after its Review under the project's exports directory."
  (revu-fixture-with-repo root
    (let ((export (revu-export-file-name "worktree" root)))
      (should (equal export
                     (expand-file-name ".revu/exports/worktree.md"
                                       (file-truename root))))
      (should-not (file-exists-p (file-name-directory export))))))

(ert-deftest revu-export-file-name-refuses-a-path-outside-a-project ()
  "No Export location is invented for a file outside a project root."
  (let ((orphan (file-name-as-directory (make-temp-file "revu-orphan-" t))))
    (unwind-protect
        (should-error (revu-export-file-name "worktree" orphan)
                      :type 'user-error)
      (delete-directory orphan t))))

(ert-deftest revu-sidecar-file-name-refuses-a-path-outside-a-project ()
  "No Sidecar location is invented for a file outside a project root."
  (let ((orphan (file-name-as-directory (make-temp-file "revu-orphan-" t))))
    (unwind-protect
        (should-error (revu-sidecar-file-name "worktree" orphan)
                      :type 'user-error)
      (delete-directory orphan t))))

(provide 'revu-skeleton-test)
;;; revu-skeleton-test.el ends here
