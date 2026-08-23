;;; revu-render-test.el --- Tests for the review buffer render  -*- lexical-binding: t; -*-

;;; Commentary:

;; Tests for the entry commands and the review buffer they render.  Every
;; test drives a command against the fixture repository and asserts on
;; what the reviewer sees -- the buffer's text and its section tree -- and
;; on the Sidecar the command left on disk.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'revu)
(require 'revu-fixture)
(require 'magit-section)

(defun revu-render-test--kill-buffers ()
  "Kill every review buffer, so one test cannot resume another's Review."
  (dolist (buffer (buffer-list))
    (when (string-prefix-p "*revu: " (buffer-name buffer))
      (kill-buffer buffer))))

(defmacro revu-render-test--in-repo (root &rest body)
  "Build the fixture repository, bind ROOT and run BODY inside it.
The repository and every review buffer BODY opened are gone when it
finishes."
  (declare (indent 1) (debug (symbolp body)))
  `(revu-fixture-with-repo ,root
     (let ((default-directory ,root))
       (unwind-protect
           (progn ,@body)
         (revu-render-test--kill-buffers)))))

(defun revu-render-test--press-tab ()
  "Run whatever TAB runs in a review buffer, on the section at point."
  (let ((command (keymap-lookup revu-mode-map "TAB")))
    (should command)
    (call-interactively command)))

(defun revu-render-test--sections (&optional class)
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

(ert-deftest revu-worktree-command-opens-a-review-buffer-over-the-worktree-diff ()
  "`revu-diff-worktree' renders the unstaged changes in a review buffer."
  (revu-render-test--in-repo root
    (let ((buffer (revu-diff-worktree "worktree")))
      (should (buffer-live-p buffer))
      (should (equal (buffer-name buffer) "*revu: worktree*"))
      (with-current-buffer buffer
        (should (eq major-mode 'revu-mode))
        (should buffer-read-only)
        (let ((text (revu-fixture-render)))
          (should (string-match-p "alpha\\.txt" text))
          (should (string-match-p "@@" text))
          (should (string-match-p "\\+alpha seven in the worktree" text))
          (should (string-match-p "-alpha seven$" text)))))))

(ert-deftest revu-staged-command-renders-every-staged-file ()
  "`revu-diff-staged' renders the staged edit, the rename and the deletion.
A rename with no edits has no hunks at all, and must still be visible."
  (revu-render-test--in-repo root
    (with-current-buffer (revu-diff-staged "staged")
      (let ((text (revu-fixture-render)))
        (should (string-match-p "^modified +beta\\.txt$" text))
        (should (string-match-p "^renamed +delta\\.txt -> delta-renamed\\.txt$"
                                text))
        (should (string-match-p "^deleted +gamma\\.txt$" text))
        (should (string-match-p "\\+beta two staged" text))
        ;; A deletion hunk ends where the file ends: nothing follows it.
        (should-not (string-match-p "^ *[0-9]+ *$" text))))))

(ert-deftest revu-staged-command-writes-a-staged-source-sidecar ()
  "The staged command leaves a Sidecar recording a staged Source."
  (revu-render-test--in-repo root
    (revu-diff-staged "staged")
    (let* ((review (revu-fixture-sidecar root "staged"))
           (source (revu-review-source review)))
      (should (equal (revu-review-name review) "staged"))
      (should (equal (revu-source-kind source) "staged"))
      (should (equal (revu-source-base source)
                     (revu-fixture-git-output root "rev-parse" "HEAD")))
      (should (equal (revu-review-annotations review) [])))))

(ert-deftest revu-render-invents-no-line-past-the-end-of-a-hunk ()
  "The newline that ends a diff is not a line of it.
Every rendered line carries content; a numbered blank at the end of a
hunk would be a line the reviewer could annotate and the file does not
have."
  (revu-render-test--in-repo root
    (with-current-buffer (revu-diff-worktree "worktree")
      (should-not (string-match-p "^ *[0-9]+ *$" (revu-fixture-render))))))

(ert-deftest revu-range-command-renders-the-diff-between-two-revisions ()
  "`revu-diff-range' renders what one branch changed against another."
  (revu-render-test--in-repo root
    (with-current-buffer (revu-diff-range "main" "feature" "main..feature")
      (should (equal (buffer-name) "*revu: main..feature*"))
      (let ((text (revu-fixture-render)))
        (should (string-match-p "^modified +alpha\\.txt$" text))
        (should (string-match-p "\\+alpha three on feature" text))
        ;; The worktree change is not in a range: a range is two commits.
        (should-not (string-match-p "in the worktree" text))))
    (let ((source (revu-review-source (revu-fixture-sidecar root "main..feature"))))
      (should (equal (revu-source-kind source) "range"))
      (should (equal (revu-source-base source)
                     (revu-fixture-git-output root "rev-parse" "main")))
      (should (equal (revu-source-head source)
                     (revu-fixture-git-output root "rev-parse" "feature"))))))

(ert-deftest revu-line-numbers-follow-the-origin-rule ()
  "A removal is numbered in the old file and everything else in the new.
The fixture line is edited so that the two sides count differently: with
a line dropped above it, the removed line and the line replacing it carry
different numbers."
  (revu-render-test--in-repo root
    (revu-fixture-write-file
     root "alpha.txt"
     (thread-last revu-fixture-alpha-baseline
                  (replace-regexp-in-string "alpha two\n" "")
                  (replace-regexp-in-string "alpha eight" "alpha eight edited")))
    (with-current-buffer (revu-diff-worktree "worktree")
      (let ((text (revu-fixture-render)))
        ;; "alpha two" is line 2 of the old file and is in no new file.
        (should (string-match-p "^ +2 -alpha two$" text))
        ;; Its replacement is line 7 of the new file; what it replaced was
        ;; line 8 of the old one.
        (should (string-match-p "^ +8 -alpha eight$" text))
        (should (string-match-p "^ +7 \\+alpha eight edited$" text))
        ;; Context is numbered in the new file too.
        (should (string-match-p "^ +8  alpha nine$" text))))))

(ert-deftest revu-render-nests-hunk-sections-under-their-file ()
  "Every hunk section sits under the section of the file it belongs to."
  (revu-render-test--in-repo root
    (with-current-buffer (revu-diff-staged "staged")
      (should (equal (mapcar (lambda (section) (oref section value))
                             (revu-render-test--sections 'revu-file-section))
                     '("beta.txt" "delta-renamed.txt" "gamma.txt")))
      (dolist (hunk (revu-render-test--sections 'revu-hunk-section))
        (should (object-of-class-p (oref hunk parent) 'revu-file-section))
        (should (equal (car (oref hunk value))
                       (oref (oref hunk parent) value)))))))

(ert-deftest revu-tab-folds-a-file-and-a-hunk ()
  "TAB on a file or a hunk hides what is under it, and shows it again."
  (revu-render-test--in-repo root
    (with-current-buffer (revu-diff-worktree "worktree")
      (let* ((file (car (revu-render-test--sections 'revu-file-section)))
             (hunk (car (revu-render-test--sections 'revu-hunk-section)))
             (first-line (save-excursion
                           (goto-char (oref hunk content))
                           (point))))
        (goto-char (oref hunk start))
        (revu-render-test--press-tab)
        (should (invisible-p first-line))
        (should-not (invisible-p (oref hunk start)))
        (revu-render-test--press-tab)
        (should-not (invisible-p first-line))
        (goto-char (oref file start))
        (revu-render-test--press-tab)
        (should (invisible-p (oref hunk start)))
        (revu-render-test--press-tab)
        (should-not (invisible-p (oref hunk start)))))))

(ert-deftest revu-re-rendering-unchanged-state-changes-nothing ()
  "Reviewing the same Source again renders the same buffer, point and all.
The buffer is a render of state: with the state unchanged there is
nothing for a second render to say differently."
  (revu-render-test--in-repo root
    (let ((buffer (revu-diff-worktree "worktree"))
          (before nil)
          (section nil))
      (with-current-buffer buffer
        (goto-char (oref (car (revu-render-test--sections 'revu-hunk-section))
                         start))
        (setq before (buffer-substring (point-min) (point-max))
              section (oref (magit-current-section) value)))
      (should (eq (revu-diff-worktree "worktree") buffer))
      (with-current-buffer buffer
        (should (equal (buffer-substring (point-min) (point-max)) before))
        (should (equal (oref (magit-current-section) value) section))
        (should (= (point) (oref (magit-current-section) start)))))))

(ert-deftest revu-buffer-command-reviews-a-pasted-diff-as-a-range ()
  "`revu-diff-buffer' reviews a unified diff already in a buffer.
The Revisions come from the diff's own `index' headers, so the Review
records what the diff spans (ADR-0005 knows no pasted-diff Source)."
  (revu-render-test--in-repo root
    (let* ((text (revu-fixture-git-output root "diff" "main..feature"))
           (revisions nil))
      (should (string-match "^index \\([0-9a-f]+\\)\\.\\.\\([0-9a-f]+\\)" text))
      (setq revisions (cons (match-string 1 text) (match-string 2 text)))
      (with-temp-buffer
        (insert text)
        (revu-diff-buffer (current-buffer) "pasted"))
      (with-current-buffer "*revu: pasted*"
        (should (string-match-p "\\+alpha three on feature" (revu-fixture-render))))
      (let ((source (revu-review-source (revu-fixture-sidecar root "pasted"))))
        (should (equal (revu-source-kind source) "range"))
        (should (equal (revu-source-base source) (car revisions)))
        (should (equal (revu-source-head source) (cdr revisions)))))))

(ert-deftest revu-buffer-command-refuses-a-diff-with-no-revisions ()
  "A diff naming nothing revu can resolve is refused, not guessed at."
  (revu-render-test--in-repo root
    (with-temp-buffer
      (insert "diff --git a/alpha.txt b/alpha.txt\n"
              "--- a/alpha.txt\n+++ b/alpha.txt\n"
              "@@ -1,1 +1,1 @@\n-alpha one\n+alpha uno\n")
      (should-error (revu-diff-buffer (current-buffer) "pasted")
                    :type 'user-error))
    (should-not (revu-fixture-sidecar root "pasted"))))

(ert-deftest revu-buffer-command-refuses-revisions-this-repository-lacks ()
  "A diff taken elsewhere is refused: its Revisions are not here to anchor to."
  (revu-render-test--in-repo root
    (with-temp-buffer
      (insert "diff --git a/alpha.txt b/alpha.txt\n"
              "index 1111111111111111111111111111111111111111.."
              "2222222222222222222222222222222222222222 100644\n"
              "--- a/alpha.txt\n+++ b/alpha.txt\n"
              "@@ -1,1 +1,1 @@\n-alpha one\n+alpha uno\n")
      (should-error (revu-diff-buffer (current-buffer) "pasted")
                    :type 'user-error))
    (should-not (revu-fixture-sidecar root "pasted"))))

(ert-deftest revu-buffer-command-reads-every-index-header-not-just-the-first ()
  "A diff is refused for any file naming an object this repository lacks.
A diff assembled elsewhere can name objects this repository has for its
first file and not its tenth, and checking the first header alone would
accept exactly that diff."
  (revu-render-test--in-repo root
    (with-temp-buffer
      ;; The first file's diff is this repository's own; the second names a
      ;; blob no repository here has ever held.
      (insert (revu-fixture-git-output root "diff" "main..feature")
              "\ndiff --git a/elsewhere.txt b/elsewhere.txt\n"
              "index 3333333333333333333333333333333333333333.."
              "4444444444444444444444444444444444444444 100644\n"
              "--- a/elsewhere.txt\n+++ b/elsewhere.txt\n"
              "@@ -1,1 +1,1 @@\n-old\n+new\n")
      (should-error (revu-diff-buffer (current-buffer) "pasted")
                    :type 'user-error))
    (should-not (revu-fixture-sidecar root "pasted"))))

(ert-deftest revu-worktree-command-shows-staged-changes-too ()
  "The worktree Review is everything HEAD does not have, staged or not.
That is what the reviewer reading before a commit is asking for, and it
is what makes the Revision the Review records the one the diff was taken
against -- which is what re-locates a removed line later (ADR-0003)."
  (revu-render-test--in-repo root
    (revu-diff-worktree "worktree")
    (let ((rendered (with-current-buffer "*revu: worktree*"
                      (revu-fixture-render))))
      ;; The fixture stages one change and leaves another unstaged.
      (should (string-match-p "beta\\.txt" rendered))
      (should (string-match-p "alpha\\.txt" rendered)))
    (let ((source (revu-review-source (revu-fixture-sidecar root "worktree"))))
      (should (equal (revu-source-base source)
                     (revu-fixture-git-output root "rev-parse" "HEAD"))))))

(ert-deftest revu-entry-commands-prompt-with-the-derived-review-name ()
  "An entry command asked for no name prompts, offering the derived one."
  (revu-render-test--in-repo root
    (let ((prompt nil))
      (cl-letf (((symbol-function 'read-string)
                 (lambda (message &optional _initial _history default)
                   (setq prompt message)
                   default)))
        (revu-diff-worktree))
      (should (string-match-p "worktree" prompt))
      (should (get-buffer "*revu: worktree*")))))

(ert-deftest revu-entry-command-resumes-the-review-already-there ()
  "Reviewing a Source again picks its Review up; it never clobbers it."
  (revu-render-test--in-repo root
    (let ((review (revu-review-add-annotation
                   (revu-review-create "worktree" (revu-source-worktree "HEAD"))
                   (revu-annotation-create "note"
                                           (revu-target-file "alpha.txt")
                                           "written yesterday"))))
      (make-directory (expand-file-name ".revu" root) t)
      (with-temp-file (expand-file-name ".revu/worktree.json" root)
        (insert (revu-review-encode review))))
    (revu-diff-worktree "worktree")
    (let ((annotations (revu-review-annotations
                        (revu-fixture-sidecar root "worktree"))))
      (should (equal (seq-length annotations) 1))
      (should (equal (revu-annotation-body (seq-elt annotations 0))
                     "written yesterday")))))

(provide 'revu-render-test)
;;; revu-render-test.el ends here
