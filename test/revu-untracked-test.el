;;; revu-untracked-test.el --- Tests for untracked files in a worktree Source  -*- lexical-binding: t; -*-

;;; Commentary:

;; Tests for the untracked files a worktree Source carries (ADR-0005's
;; untracked-files amendment).  `git diff' never shows a file git does
;; not track, so a file the reviewer or their agent created and never
;; staged would be invisible to the Review that promises everything the
;; worktree carries that the base does not.  Every worktree Source shows
;; it as an all-added file, an ignored file never appears, and nothing
;; about Reviewed marks, Path resolution or Anchors changes for one.

;;; Code:

(require 'ert)
(require 'magit-section)
(require 'revu)
(require 'revu-fixture)

(defun revu-untracked-test--commit-everything (root)
  "Commit everything the fixture repository at ROOT carries.
What is left is a worktree that differs from HEAD by nothing at all, so
a test can make the whole difference be an untracked file."
  (revu-fixture-git-output root "add" "-A")
  (revu-fixture-git-output root "commit" "-q" "-m" "Everything so far"))

(defun revu-untracked-test--worktree-text (root &optional revision paths)
  "Return the worktree diff of ROOT against REVISION, HEAD by default."
  (revu-diff-worktree-text root (or revision "HEAD") paths))

(defun revu-untracked-test--paths (text)
  "Return the paths the unified diff TEXT names, in diff order."
  (mapcar #'revu-diff-file-path (revu-diff-parse text)))

;;;; What a worktree Source carries

(ert-deftest revu-untracked-file-is-an-added-file-of-the-worktree-source ()
  "A file created and never staged is an all-added file of the worktree diff."
  (revu-fixture-in-repo root
    (revu-fixture-write-file root "notes.txt" "note one\nnote two\n")
    (let* ((text (revu-untracked-test--worktree-text root))
           (file (seq-find (lambda (file)
                             (equal (revu-diff-file-path file) "notes.txt"))
                           (revu-diff-parse text))))
      (should file)
      (should (equal (revu-diff-file-status file) "added"))
      (should (equal (length (revu-diff-file-hunks file)) 1))
      (should (equal (revu-diff-hunk-lines (car (revu-diff-file-hunks file)))
                     '(("added" 1 "+note one") ("added" 2 "+note two"))))
      ;; The tracked half of the Source is still all there.
      (should (member "alpha.txt" (revu-untracked-test--paths text))))))

(ert-deftest revu-untracked-file-appears-against-another-revision ()
  "Every worktree Source carries it, not only the one against HEAD."
  (revu-fixture-in-repo root
    (revu-fixture-write-file root "notes.txt" "note one\n")
    (should (member "notes.txt"
                    (revu-untracked-test--paths
                     (revu-untracked-test--worktree-text root "feature"))))))

(ert-deftest revu-untracked-ignored-file-does-not-appear ()
  "A file `.gitignore' covers is not part of the worktree Source."
  (revu-fixture-in-repo root
    (revu-fixture-write-file root ".gitignore" "*.log\n")
    (revu-fixture-git-output root "add" ".gitignore")
    (revu-fixture-git-output root "commit" "-q" "-m" "Ignore logs")
    (revu-fixture-write-file root "notes.log" "noise\n")
    (revu-fixture-write-file root "notes.txt" "note one\n")
    (let ((paths (revu-untracked-test--paths
                  (revu-untracked-test--worktree-text root))))
      (should (member "notes.txt" paths))
      (should-not (member "notes.log" paths)))))

(ert-deftest revu-untracked-review-state-does-not-appear ()
  "The Review never lists its own Sidecar and Export as files to review."
  (revu-fixture-in-repo root
    (revu-fixture-write-file root ".revu/reviews/worktree.json" "{}\n")
    (revu-fixture-write-file root ".revu/exports/worktree.md" "# Export\n")
    (let ((paths (revu-untracked-test--paths
                  (revu-untracked-test--worktree-text root))))
      (should-not (member ".revu/reviews/worktree.json" paths))
      (should-not (member ".revu/exports/worktree.md" paths)))))

(ert-deftest revu-untracked-obeys-the-narrowing ()
  "A Narrowing limits untracked files exactly as it limits tracked ones."
  (revu-fixture-in-repo root
    (revu-fixture-write-file root "notes/new.txt" "note one\n")
    (should-not (member "notes/new.txt"
                        (revu-untracked-test--paths
                         (revu-untracked-test--worktree-text
                          root nil '("alpha.txt")))))
    (should (member "notes/new.txt"
                    (revu-untracked-test--paths
                     (revu-untracked-test--worktree-text
                      root nil '("notes")))))))

(ert-deftest revu-untracked-path-the-tracked-diff-names-appears-once ()
  "A file the diff already shows is left to the diff, whatever else it is.
The fixture staged a deletion of gamma.txt; recreating it in the
worktree leaves a path that is both deleted in the diff and untracked on
disk, and a path rendered twice is a path whose Reviewed marks and folds
cannot say which of the two they mean."
  (revu-fixture-in-repo root
    (revu-fixture-write-file root "gamma.txt" "gamma again\n")
    (let ((paths (revu-untracked-test--paths
                  (revu-untracked-test--worktree-text root))))
      (should (equal (seq-count (lambda (path) (equal path "gamma.txt")) paths)
                     1)))))

(ert-deftest revu-untracked-nested-repository-is-not-descended-into ()
  "A directory holding a repository of its own is skipped, not diffed.
Git reports it as one entry ending in a slash, and asking for the diff
of a directory would fail the whole Source."
  (revu-fixture-in-repo root
    (revu-fixture-write-file root "vendor/thing/a.txt" "a\n")
    (revu-fixture-git-output (expand-file-name "vendor/thing" root) "init" "-q")
    (revu-fixture-write-file root "notes.txt" "note one\n")
    (let ((paths (revu-untracked-test--paths
                  (revu-untracked-test--worktree-text root))))
      (should (member "notes.txt" paths))
      (should-not (member "vendor/thing/a.txt" paths)))))

(ert-deftest revu-untracked-empty-file-is-a-file-with-no-hunks ()
  "An empty untracked file is a file without hunks, as a tracked one is."
  (revu-fixture-in-repo root
    (revu-fixture-write-file root "empty.txt" "")
    (let ((file (seq-find (lambda (file)
                            (equal (revu-diff-file-path file) "empty.txt"))
                          (revu-diff-parse
                           (revu-untracked-test--worktree-text root)))))
      (should file)
      (should (equal (revu-diff-file-status file) "added"))
      (should-not (revu-diff-file-hunks file)))))

(ert-deftest revu-untracked-binary-file-is-a-file-with-no-hunks ()
  "An untracked binary file is a file without hunks, as a tracked one is."
  (revu-fixture-in-repo root
    (revu-fixture-write-file root "logo.bin" "\0\1\2binary\0")
    (let ((file (seq-find (lambda (file)
                            (equal (revu-diff-file-path file) "logo.bin"))
                          (revu-diff-parse
                           (revu-untracked-test--worktree-text root)))))
      (should file)
      (should (equal (revu-diff-file-status file) "added"))
      (should-not (revu-diff-file-hunks file)))))

(ert-deftest revu-untracked-exclusion-names-the-revu-directory ()
  "The exclusion and the directory it excludes cannot drift apart.
`revu-diff.el\'s exclusion spells the name out because
`revu-directory-name\' lives a layer above it, and a rename that left
the two disagreeing would put every Sidecar back in the Review."
  (should (equal revu-diff--untracked-exclude
                 (concat "--exclude=/" revu-directory-name "/"))))

;;;; The Review over one

(ert-deftest revu-untracked-only-difference-opens-a-review ()
  "A worktree differing from its base by an untracked file alone opens."
  (revu-fixture-in-repo root
    (revu-untracked-test--commit-everything root)
    (revu-fixture-write-file root "notes.txt" "note one\n")
    (with-current-buffer (revu-diff-worktree nil "worktree")
      (should (string-match-p "notes.txt" (revu-fixture-render))))))

(ert-deftest revu-untracked-file-survives-reload-and-resume ()
  "It is there on the first paint, after a reload, and on resuming."
  (revu-fixture-in-repo root
    (revu-fixture-write-file root "notes.txt" "note one\n")
    (with-current-buffer (revu-diff-worktree nil "worktree")
      (should (string-match-p "note one" (revu-fixture-render)))
      (revu-reload)
      (should (string-match-p "note one" (revu-fixture-render))))
    (revu-fixture-kill-review-buffers)
    (with-current-buffer (revu-diff-worktree nil "worktree")
      (should (string-match-p "note one" (revu-fixture-render))))))

(ert-deftest revu-untracked-reviewed-mark-holds-after-the-file-is-staged ()
  "The hunk is cut the same way once staged, so the mark still holds."
  (revu-fixture-in-repo root
    (revu-fixture-write-file root "notes.txt" "note one\nnote two\n")
    (with-current-buffer (revu-diff-worktree nil "worktree")
      (revu-fixture-goto-line-matching "^\\+note one$")
      (revu-reviewed-toggle)
      (let ((marks (append (revu-review-marks
                            (revu-fixture-sidecar root "worktree"))
                           nil)))
        (should (equal (length marks) 1))
        (should (equal (revu-mark-path (car marks)) "notes.txt"))
        (should (equal (revu-mark-digest (car marks))
                       (revu-digest "+note one\n+note two"))))
      (revu-fixture-git-output root "add" "notes.txt")
      (revu-reload)
      (should (eq (revu-reviewed-state (revu-review) revu--files "notes.txt")
                  'reviewed)))))

(ert-deftest revu-untracked-annotation-re-anchors-as-an-added-line-does ()
  "An Annotation on an untracked line follows it once the file is staged."
  (revu-fixture-in-repo root
    (revu-fixture-write-file root "notes.txt" "note one\nnote two\n")
    (with-current-buffer (revu-diff-worktree nil "worktree")
      (revu-fixture-goto-line-matching "^\\+note two$")
      (revu-annotate-line "question" "Why this note?")
      (revu-fixture-git-output root "add" "notes.txt")
      (revu-fixture-write-file root "notes.txt" "note zero\nnote one\nnote two\n")
      (revu-reload)
      (let ((placement (car (revu-render))))
        (should (equal (revu-render-placement-path placement) "notes.txt"))
        (should (equal (revu-render-placement-state placement) 'moved))
        (should (equal (revu-render-placement-line placement) 3))))))

(ert-deftest revu-untracked-path-resolves-present-until-the-file-is-gone ()
  "Path resolution answers for an untracked file as it does for any other."
  (revu-fixture-in-repo root
    (revu-fixture-write-file root "notes.txt" "note one\n")
    (let ((source (revu-source-worktree (revu-diff-head-revision root))))
      (should (equal (revu-diff-resolve-paths root source '("notes.txt"))
                     '(("notes.txt" . present))))
      (delete-file (expand-file-name "notes.txt" root))
      (should (equal (revu-diff-resolve-paths root source '("notes.txt"))
                     '(("notes.txt" . deleted)))))))

(provide 'revu-untracked-test)
;;; revu-untracked-test.el ends here
