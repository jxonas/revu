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
(require 'magit-section)
(require 'seq)
(require 'revu)
(require 'revu-record)

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

(defun revu-fixture-sidecar (root name)
  "Return the Review persisted in the Sidecar called NAME under ROOT.
The Sidecar is read back from disk and decoded, so a test sees what an
agent reading the file would see.  Return nil when there is no such
Sidecar."
  (let ((file (expand-file-name (format ".revu/%s.json" name) root)))
    (when (file-exists-p file)
      (with-temp-buffer
        (insert-file-contents file)
        (revu-review-decode (buffer-string))))))

(defun revu-fixture-sidecar-text (root name)
  "Return the raw text of the Sidecar called NAME under ROOT, or nil."
  (let ((file (expand-file-name (format ".revu/%s.json" name) root)))
    (when (file-exists-p file)
      (with-temp-buffer
        (insert-file-contents file)
        (buffer-string)))))

(defun revu-fixture-render (&optional buffer)
  "Return the rendered text of BUFFER, which defaults to the current one.
Text properties are dropped: a test asserts on what the reviewer reads."
  (with-current-buffer (or buffer (current-buffer))
    (buffer-substring-no-properties (point-min) (point-max))))

(defmacro revu-fixture-with-repo (root &rest body)
  "Build the fixture repository, bind its root to ROOT and run BODY.
The repository is deleted when BODY finishes, however it finishes."
  (declare (indent 1) (debug (symbolp body)))
  `(let ((,root (revu-fixture-make-repo)))
     (unwind-protect
         (progn ,@body)
       (delete-directory ,root t))))

(defun revu-fixture-kill-review-buffers ()
  "Kill every review buffer, so one test cannot resume another's Review."
  (dolist (buffer (buffer-list))
    (when (string-prefix-p "*revu: " (buffer-name buffer))
      (kill-buffer buffer))))

(defmacro revu-fixture-in-repo (root &rest body)
  "Build the fixture repository, bind ROOT and run BODY inside it.
The repository and every review buffer BODY opened are gone when it
finishes, so tests cannot leak Reviews into one another."
  (declare (indent 1) (debug (symbolp body)))
  `(revu-fixture-with-repo ,root
     (let ((default-directory ,root))
       (unwind-protect
           (progn ,@body)
         (revu-fixture-kill-review-buffers)))))

(defun revu-fixture-goto-line-matching (regexp)
  "Put point at the beginning of the first rendered line matching REGEXP."
  (goto-char (point-min))
  (should (re-search-forward regexp nil t))
  (goto-char (line-beginning-position)))

(defun revu-fixture-press-tab ()
  "Run whatever TAB runs in a review buffer, on the section at point."
  (let ((command (keymap-lookup revu-mode-map "TAB")))
    (should command)
    (call-interactively command)))

(defun revu-fixture-sections (&optional class)
  "Return the sections of the current buffer, depth first.
With CLASS, return only the sections of that class."
  (let ((found nil))
    (letrec ((walk (lambda (section)
                     (when (or (null class) (object-of-class-p section class))
                       (push section found))
                     (dolist (child (oref section children))
                       (funcall walk child)))))
      (funcall walk magit-root-section))
    (nreverse found)))

(defun revu-fixture-hunk-sections (path)
  "Return the hunk sections rendered for PATH, in render order."
  (seq-filter (lambda (section) (equal (car (oref section value)) path))
              (revu-fixture-sections 'revu-hunk-section)))

(defun revu-fixture-two-hunk-alpha (root &optional extra)
  "Rewrite alpha.txt in the worktree under ROOT so its diff has two hunks.
The first and the last line change, and the six lines between them keep
the two runs of context apart.  EXTRA, when given, is inserted as a line
inside the first hunk, which moves every `@@' number below it without
adding a hunk of its own."
  (revu-fixture-write-file
   root "alpha.txt"
   (thread-last revu-fixture-alpha-baseline
                (replace-regexp-in-string
                 "alpha one\n"
                 (concat "alpha one changed\n" (and extra (concat extra "\n"))))
                (replace-regexp-in-string "alpha ten" "alpha ten changed"))))

(defconst revu-fixture-worktree-seven
  "^ +7 \\+alpha seven in the worktree$"
  "The rendered worktree line the point tests put the reviewer on.
It is the added half of the one line the worktree changes, so it is a
line with context above it, a removed line beside it and hunks either
side -- everything a test about where point lands needs around it.")

(defun revu-fixture-put-point-on-and-highlight (regexp)
  "Put point on the line matching REGEXP and highlight the section it is in.
The highlight is what a reviewer moving point would get: outside a
command loop nothing runs the post-command hook magit-section installs,
so the test asks for the update that hook would have asked for."
  (revu-fixture-goto-line-matching regexp)
  (magit-section-update-highlight t))

(defun revu-fixture-face-on-screen (regexp)
  "Return the face showing on the text REGEXP matches.
Reads overlays as well as text properties, because the current-section
highlight is an overlay: a test that read only the text property would
pass over a line whose colour the highlight has covered."
  (save-excursion
    (goto-char (point-min))
    (should (re-search-forward regexp nil t))
    (get-char-property (match-beginning 0) 'font-lock-face)))

(defmacro revu-fixture-fold-outlives (&rest body)
  "Fold the first file section, run BODY, and assert the fold is still on screen.
BODY is whatever renders the buffer again -- a reload, a filter toggled
and back -- and the fold it leaves behind is the invariant of ADR-0012."
  (declare (indent 0))
  `(progn
     (let ((file (car (revu-fixture-sections 'revu-file-section))))
       (magit-section-hide file)
       (should (revu-fixture-hidden-on-screen-p file)))
     ,@body
     (should (revu-fixture-hidden-on-screen-p
              (car (revu-fixture-sections 'revu-file-section))))))

(defun revu-fixture-hidden-on-screen-p (section)
  "Return non-nil while the body of SECTION is invisible on screen.
The `hidden' slot is magit-section's model of visibility and nothing
more: what hides text is an invisible overlay, so a test that reads the
slot can pass over a buffer the reviewer sees fully expanded.  A test
asserts on this instead."
  (let ((content (oref section content)))
    (and content (invisible-p content))))

(provide 'revu-fixture)
;;; revu-fixture.el ends here
