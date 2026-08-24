;;; revu-plain-test.el --- Tests for reviewing a plain file  -*- lexical-binding: t; -*-

;;; Commentary:

;; Reviewing a Source that is a plain file rather than a diff (ADR-0011).
;; The assertions are at the command seam: what `revu-file' refuses, what
;; the review buffer renders, what lands in the Sidecar on disk, and what
;; a single file-content Reviewed mark does.

;;; Code:

(require 'ert)
(require 'revu)
(require 'revu-fixture)

(defconst revu-plain-test-readme
  "# Fixture\n\nUntouched by any diff.\n"
  "What `README.md' holds in the fixture repository.")

(defmacro revu-plain-test--answering (answer &rest body)
  "Run BODY with every `y-or-n-p' answered with ANSWER."
  (declare (indent 1) (debug (form body)))
  `(cl-letf (((symbol-function 'y-or-n-p) (lambda (&rest _) ,answer)))
     ,@body))

;;;; Entry

(ert-deftest revu-plain-refuses-a-buffer-visiting-no-file ()
  "A buffer that is not visiting a file has no content on disk to review."
  (revu-fixture-in-repo root
    (with-temp-buffer
      (insert "scratch\n")
      (should-error (revu-file) :type 'user-error))))

(ert-deftest revu-plain-refuses-a-file-outside-a-project ()
  "A file outside a project root has nowhere to put a Sidecar."
  (revu-fixture-in-repo root
    (let* ((outside (make-temp-file "revu-outside-" t))
           (file (expand-file-name "loose.txt" outside)))
      (unwind-protect
          (progn
            (with-temp-file file (insert "loose\n"))
            (should-error (revu-file file) :type 'user-error))
        (delete-directory outside t)))))

(ert-deftest revu-plain-refuses-a-file-that-was-never-saved ()
  "A new buffer whose save is declined is still visiting nothing on disk."
  (revu-fixture-in-repo root
    (let ((buffer (find-file-noselect (expand-file-name "unsaved.txt" root))))
      (unwind-protect
          (with-current-buffer buffer
            (insert "never written\n")
            (revu-plain-test--answering nil
              (should-error (revu-file) :type 'user-error)))
        (kill-buffer buffer)))))

(ert-deftest revu-plain-offers-to-save-a-modified-buffer ()
  "Accepting the offer writes the buffer, and that is what is reviewed."
  (revu-fixture-in-repo root
    (let ((buffer (find-file-noselect (expand-file-name "README.md" root))))
      (unwind-protect
          (with-current-buffer buffer
            (goto-char (point-max))
            (insert "One more line.\n")
            (revu-plain-test--answering t
              (revu-file nil "plain"))
            (should-not (buffer-modified-p buffer))
            (should (string-match-p
                     "One more line."
                     (revu-fixture-file-contents root "README.md"))))
        (kill-buffer buffer)))))

(ert-deftest revu-plain-renders-what-is-on-disk-when-the-save-is-declined ()
  "Disk is the single truth: the unsaved edit is not in the review buffer."
  (revu-fixture-in-repo root
    (let ((buffer (find-file-noselect (expand-file-name "README.md" root))))
      (unwind-protect
          (progn
            (with-current-buffer buffer
              (goto-char (point-max))
              (insert "Only in the buffer.\n"))
            (revu-plain-test--answering nil
              (revu-file (expand-file-name "README.md" root) "plain"))
            (should (buffer-modified-p buffer))
            (with-current-buffer (revu-buffer-name "plain")
              (should-not (string-match-p "Only in the buffer"
                                          (revu-fixture-render)))))
        (with-current-buffer buffer (set-buffer-modified-p nil))
        (kill-buffer buffer)))))

;;;; Render

(ert-deftest revu-plain-renders-one-flat-file-section ()
  "One file section holds every line; no hunk splits it (ADR-0011).
Numbered on purpose: the lines of a plain file count in the file, so the
blank second line is numbered too and the line after it reads 3."
  (revu-fixture-in-repo root
    (let ((revu-line-numbers t))
      (revu-file (expand-file-name "README.md" root) "plain")
      (with-current-buffer (revu-buffer-name "plain")
        (should (= 1 (length (revu-fixture-sections 'revu-file-section))))
        (should (null (revu-fixture-sections 'revu-hunk-section)))
        (let ((rendered (revu-fixture-render)))
          (should (string-match-p "^README\\.md" rendered))
          (should (string-match-p "^   1 # Fixture$" rendered))
          (should (string-match-p "^   3 Untouched by any diff\\.$" rendered)))))))

(ert-deftest revu-plain-folds-the-file-section ()
  "The file section folds like any other, which is all ADR-0011 asks of it."
  (revu-fixture-in-repo root
    (revu-file (expand-file-name "README.md" root) "plain")
    (with-current-buffer (revu-buffer-name "plain")
      (revu-fixture-goto-line-matching "^# Fixture$")
      (let ((line (point)))
        (revu-fixture-goto-line-matching "^README\\.md")
        (revu-fixture-press-tab)
        (should (invisible-p line))
        (revu-fixture-press-tab)
        (should-not (invisible-p line))))))

(ert-deftest revu-plain-positions-point-on-the-region-start ()
  "A region at entry only puts point on its first line (ADR-0011)."
  (revu-fixture-in-repo root
    (let ((buffer (find-file-noselect (expand-file-name "README.md" root))))
      (unwind-protect
          (with-current-buffer buffer
            (goto-char (point-min))
            (forward-line 2)
            (let ((transient-mark-mode t))
              (push-mark (point) t t)
              (goto-char (point-max))
              (revu-file nil "plain"))
            (with-current-buffer (revu-buffer-name "plain")
              (should (equal (get-text-property (line-beginning-position)
                                                'revu-target)
                             (list "README.md" 3 nil)))))
        (kill-buffer buffer)))))

;;;; Annotating, and resuming

(ert-deftest revu-plain-annotates-a-line-into-the-sidecar ()
  "A plain-file Target carries no Origin: its Source says there is no diff."
  (revu-fixture-in-repo root
    (revu-file (expand-file-name "README.md" root) "plain")
    (with-current-buffer (revu-buffer-name "plain")
      (revu-fixture-goto-line-matching "^Untouched by any diff\\.$")
      (revu-annotate-line "question" "What is untouched?"))
    (let* ((review (revu-fixture-sidecar root "plain"))
           (annotation (aref (revu-review-annotations review) 0))
           (target (revu-annotation-target annotation)))
      (should (equal (revu-source-kind (revu-review-source review)) "file"))
      (should (equal (revu-source-path (revu-review-source review)) "README.md"))
      (should (equal (revu-target-kind target) "line"))
      (should (equal (revu-target-path target) "README.md"))
      (should (equal (revu-target-line-number target) 3))
      (should (null (revu-target-origin target))))))

(ert-deftest revu-plain-resumes-the-review-it-left ()
  "Closing and re-entering renders yesterday's Annotation where it belongs."
  (revu-fixture-in-repo root
    (revu-file (expand-file-name "README.md" root) "plain")
    (with-current-buffer (revu-buffer-name "plain")
      (revu-fixture-goto-line-matching "^# Fixture$")
      (revu-annotate-line "note" "The title."))
    (revu-fixture-kill-review-buffers)
    (revu-file (expand-file-name "README.md" root) "plain")
    (with-current-buffer (revu-buffer-name "plain")
      (should (= 1 (length (revu-fixture-sections 'revu-annotation-section))))
      (should (string-match-p
               "# Fixture\n    note \\[fresh\\]\n      The title\\."
               (revu-fixture-render))))))

(ert-deftest revu-plain-never-follows-a-rename ()
  "A plain-file Source orphans a missing file rather than chasing it (ADR-0004)."
  (revu-fixture-in-repo root
    (revu-file (expand-file-name "README.md" root) "plain")
    (with-current-buffer (revu-buffer-name "plain")
      (revu-fixture-goto-line-matching "^# Fixture$")
      (revu-annotate-line "note" "The title."))
    (revu-fixture-git-output root "mv" "README.md" "READTHIS.md")
    (revu-fixture-git-output root "commit" "-q" "-m" "Rename the readme")
    (with-current-buffer (revu-buffer-name "plain")
      (revu-reload)
      (should (string-match-p "note \\[orphaned\\]" (revu-fixture-render))))))

(ert-deftest revu-plain-does-not-place-point-from-a-drifted-buffer ()
  "A region in an unsaved buffer says nothing about the file on disk.
Disk is the single truth, so when the save is declined the region's line
numbers describe content the review buffer is not showing.  Point stays
at the top rather than landing somewhere wrong."
  (revu-fixture-in-repo root
    (let ((buffer (find-file-noselect (expand-file-name "README.md" root))))
      (unwind-protect
          (with-current-buffer buffer
            ;; Push the interesting line down, and decline to save it.
            (goto-char (point-min))
            (insert "one\ntwo\nthree\nfour\n")
            (goto-char (point-max))
            (let ((transient-mark-mode t))
              (push-mark (point-min) t t)
              (revu-plain-test--answering nil
                (revu-file nil "plain")))
            (should (buffer-modified-p))
            (with-current-buffer (revu-buffer-name "plain")
              ;; The file on disk has three lines; the buffer claimed seven.
              (should (equal (get-text-property (line-beginning-position)
                                                'revu-target)
                             nil))
              (should (= (line-number-at-pos) 1))))
        (with-current-buffer buffer (set-buffer-modified-p nil))
        (kill-buffer buffer)))))

(ert-deftest revu-plain-renders-a-file-that-is-one-empty-line ()
  "A file holding a single newline holds one line, and it renders.
Only a file with no content at all has no lines; a blank line is a line
the reviewer can point at and annotate."
  (revu-fixture-in-repo root
    (revu-fixture-write-file root "blank.txt" "\n")
    ;; Numbered on purpose: what the test is after is that the blank line
    ;; is a line of the file, and its number is what says so.
    (let ((revu-line-numbers t))
      (revu-file (expand-file-name "blank.txt" root) "blank")
      (with-current-buffer (revu-buffer-name "blank")
        (should (string-match-p "^   1 $" (revu-fixture-render)))
        (revu-fixture-goto-line-matching "^   1 $")
        (revu-annotate-line "note" "The one line there is.")
        (let ((review (revu-fixture-sidecar root "blank")))
          (should (equal (seq-length (revu-review-annotations review)) 1)))))))

(ert-deftest revu-plain-still-reads-as-a-plain-file-once-it-is-gone ()
  "A deleted plain file is still a plain file, not a diff of one.
What tells the two apart is the Source, not whether there is content to
read: a file that has gone has none, and inferring from that would have
the render name a change to the file nobody made."
  (revu-fixture-in-repo root
    (revu-file (expand-file-name "README.md" root) "plain")
    (with-current-buffer (revu-buffer-name "plain")
      (revu-fixture-goto-line-matching "^# Fixture$")
      (revu-annotate-line "note" "The title."))
    (delete-file (expand-file-name "README.md" root))
    (with-current-buffer (revu-buffer-name "plain")
      (revu-reload)
      (let ((rendered (revu-fixture-render)))
        ;; The heading names the file and claims nothing about a diff.
        (should (string-match-p "^README\\.md" rendered))
        (should-not (string-match-p "modified" rendered))
        (should-not (string-match-p "deleted" rendered))
        (should (string-match-p "note \\[orphaned\\]" rendered)))
      ;; And there is nothing left to call read.
      (revu-fixture-goto-line-matching "^README\\.md")
      (should-error (revu-reviewed-toggle) :type 'user-error))))

;;;; Reviewed

(ert-deftest revu-plain-takes-a-single-file-content-mark ()
  "Reviewed degrades to one mark over the whole file content (ADR-0009)."
  (revu-fixture-in-repo root
    (revu-file (expand-file-name "README.md" root) "plain")
    (with-current-buffer (revu-buffer-name "plain")
      (revu-fixture-goto-line-matching "^README\\.md")
      (revu-reviewed-toggle))
    (let ((marks (revu-review-marks (revu-fixture-sidecar root "plain"))))
      (should (= 1 (seq-length marks)))
      (should (equal (revu-mark-path (aref marks 0)) "README.md"))
      (should (equal (revu-mark-digest (aref marks 0))
                     (revu-digest revu-plain-test-readme))))
    ;; Toggling again takes the assertion back.
    (with-current-buffer (revu-buffer-name "plain")
      (revu-fixture-goto-line-matching "^README\\.md")
      (revu-reviewed-toggle))
    (should (= 0 (seq-length
                  (revu-review-marks (revu-fixture-sidecar root "plain")))))))

(ert-deftest revu-plain-un-matches-the-mark-when-the-file-is-edited ()
  "An edited file hashes to nothing the marks assert, and reverting it back."
  (revu-fixture-in-repo root
    (revu-file (expand-file-name "README.md" root) "plain")
    (with-current-buffer (revu-buffer-name "plain")
      (revu-fixture-goto-line-matching "^README\\.md")
      (revu-reviewed-toggle)
      (let ((review (revu-review)))
        (should (revu-reviewed-p review revu--files "README.md")))
      (revu-fixture-write-file root "README.md" "# Fixture\n\nEdited.\n")
      (revu-reload)
      (should-not (revu-reviewed-p (revu-review) revu--files "README.md"))
      (revu-fixture-write-file root "README.md" revu-plain-test-readme)
      (revu-reload)
      (should (revu-reviewed-p (revu-review) revu--files "README.md")))))

(ert-deftest revu-plain-badges-its-file-heading-with-the-reviewed-state ()
  "A plain file wears the state on the one heading it has (ADR-0011).
There are no hunks to divide it, so there is no partial state to count:
the file is read, or it was read and has changed, or it has not been
read.  The path is the mark\'s locality, so a mark on it that no longer
matches is about this file and nothing else."
  (revu-fixture-in-repo root
    (revu-file (expand-file-name "README.md" root) "plain")
    (with-current-buffer (revu-buffer-name "plain")
      (should-not (string-match-p revu-render-reviewed-glyph
                                  (revu-fixture-render)))
      (revu-fixture-goto-line-matching "^README\\.md")
      (revu-reviewed-toggle)
      (should (string-match-p (concat "^README\\.md +"
                                      revu-render-reviewed-glyph "$")
                              (revu-fixture-render)))
      ;; Edited under the reviewer, it says it was read and has changed.
      (revu-fixture-write-file root "README.md" "# Fixture\n\nEdited.\n")
      (revu-reload)
      (should (string-match-p (concat "^README\\.md +"
                                      revu-render-stale-glyph "$")
                              (revu-fixture-render))))))

(provide 'revu-plain-test)
;;; revu-plain-test.el ends here
