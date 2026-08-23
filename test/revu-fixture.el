;;; revu-fixture.el --- Fixture git repository for revu tests  -*- lexical-binding: t; -*-

;;; Commentary:

;; Builds a throwaway git repository that the command-seam tests run
;; against.  The repository carries every Source shape revu reviews: a
;; committed baseline, staged changes, unstaged worktree changes, a
;; second branch for a revision range, a rename, a deletion, and a plain
;; file that no diff touches.
;;
;; Every git invocation is hermetic: the identity is passed on the
;; command line, so the machine's global git configuration cannot change
;; what the fixture builds.

;;; Code:

(require 'ert)

(defconst revu-fixture-alpha-baseline
  "alpha one\nalpha two\nalpha three\nalpha four\nalpha five\n\
alpha six\nalpha seven\nalpha eight\nalpha nine\nalpha ten\n"
  "Baseline content of the fixture file that both branches change.")

(defun revu-fixture-write-file (root relative-path content)
  "Write CONTENT to RELATIVE-PATH under ROOT, creating parent directories."
  (let ((file (expand-file-name relative-path root)))
    (make-directory (file-name-directory file) t)
    (with-temp-file file
      (insert content))
    file))

(defun revu-fixture-file-contents (root relative-path)
  "Return the contents of RELATIVE-PATH under ROOT as a string."
  (with-temp-buffer
    (insert-file-contents (expand-file-name relative-path root))
    (buffer-string)))

(defun revu-fixture-git-output (root &rest args)
  "Run git ARGS in ROOT and return its standard output, trailing space trimmed.
Signal an error when git exits non-zero.  The committer and author
identity is passed on the command line, so no global git configuration
is consulted."
  (with-temp-buffer
    (let* ((default-directory (file-name-as-directory root))
           (status (apply #'call-process "git" nil t nil
                          "-c" "user.email=revu@test"
                          "-c" "user.name=revu"
                          "-c" "commit.gpgsign=false"
                          args)))
      (unless (eq status 0)
        (error "git %s failed in %s: %s"
               (string-join args " ") root (buffer-string)))
      (string-trim-right (buffer-string)))))

(defun revu-fixture-make-repo ()
  "Build the fixture git repository in a fresh temporary directory.
Return its root.  The caller is responsible for deleting it; use
`revu-fixture-with-repo' to have that done automatically."
  (let ((root (file-name-as-directory
               (make-temp-file "revu-fixture-" t))))
    (revu-fixture-git-output root "init" "-q" "-b" "main")
    ;; (a) committed baseline.
    (revu-fixture-write-file root "alpha.txt" revu-fixture-alpha-baseline)
    (revu-fixture-write-file root "beta.txt" "beta one\nbeta two\nbeta three\n")
    (revu-fixture-write-file root "gamma.txt" "gamma one\ngamma two\n")
    (revu-fixture-write-file root "delta.txt" "delta one\ndelta two\n")
    (revu-fixture-write-file root "README.md" "# Fixture\n\nUntouched by any diff.\n")
    (revu-fixture-git-output root "add" "-A")
    (revu-fixture-git-output root "commit" "-q" "-m" "Baseline")
    ;; (d) a second branch, so `A..B' has something to show.
    (revu-fixture-git-output root "checkout" "-q" "-b" "feature")
    (revu-fixture-write-file
     root "alpha.txt"
     (replace-regexp-in-string "alpha three" "alpha three on feature"
                               revu-fixture-alpha-baseline t t))
    (revu-fixture-git-output root "commit" "-q" "-a" "-m" "Change alpha on feature")
    (revu-fixture-git-output root "checkout" "-q" "main")
    ;; (b) staged changes, including (e) a rename and (f) a deletion.
    (revu-fixture-write-file root "beta.txt" "beta one\nbeta two staged\nbeta three\n")
    (revu-fixture-git-output root "add" "beta.txt")
    (revu-fixture-git-output root "mv" "delta.txt" "delta-renamed.txt")
    (revu-fixture-git-output root "rm" "-q" "gamma.txt")
    ;; (c) unstaged worktree changes.  (g) README.md is left alone.
    (revu-fixture-write-file
     root "alpha.txt"
     (replace-regexp-in-string "alpha seven" "alpha seven in the worktree"
                               revu-fixture-alpha-baseline t t))
    root))

(defmacro revu-fixture-with-repo (root &rest body)
  "Build the fixture repository, bind its root to ROOT and run BODY.
The repository is deleted when BODY finishes, however it finishes."
  (declare (indent 1) (debug (symbolp body)))
  `(let ((,root (revu-fixture-make-repo)))
     (unwind-protect
         (progn ,@body)
       (delete-directory ,root t))))

(provide 'revu-fixture)
;;; revu-fixture.el ends here
