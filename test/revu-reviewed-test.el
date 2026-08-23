;;; revu-reviewed-test.el --- Tests for Reviewed marks  -*- lexical-binding: t; -*-

;;; Commentary:

;; Tests for the Reviewed-mark commands and the two view filters.  Every
;; test drives a command in a review buffer over the fixture repository
;; and asserts on what the reviewer and their agent see: the Sidecar on
;; disk, read back as an agent would read it, and the rendered buffer's
;; text and section tree.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'magit-section)
(require 'revu)
(require 'revu-fixture)

(defconst revu-reviewed-test--worktree-hunk
  " alpha four\n alpha five\n alpha six\n-alpha seven\n\
+alpha seven in the worktree\n alpha eight\n alpha nine\n alpha ten"
  "The body of the one hunk the fixture's worktree diff shows in alpha.txt.
Written out rather than derived, so the digest a test expects comes from
the diff as git prints it and not from revu's own parser.")

(defconst revu-reviewed-test--first-alpha-hunk
  "-alpha one\n+alpha one changed\n alpha two\n alpha three\n alpha four"
  "The body of the first hunk of the two-hunk alpha.txt, as git prints it.")

(defconst revu-reviewed-test--second-alpha-hunk
  " alpha seven\n alpha eight\n alpha nine\n-alpha ten\n+alpha ten changed"
  "The body of the second hunk of the two-hunk alpha.txt, as git prints it.")

(defun revu-reviewed-test--marks (root name)
  "Return the Reviewed marks the Sidecar called NAME under ROOT holds."
  (append (revu-review-marks (revu-fixture-sidecar root name)) nil))

(defun revu-reviewed-test--section (value)
  "Return the section of the current buffer whose value is VALUE."
  (let ((found nil))
    (cl-labels ((walk (section)
                  (cond (found nil)
                        ((equal (oref section value) value) (setq found section))
                        (t (mapc #'walk (oref section children))))))
      (walk magit-root-section))
    found))

(defun revu-reviewed-test--hunk-sections (path)
  "Return the hunk sections rendered for PATH, in render order."
  (let ((found nil))
    (cl-labels ((walk (section)
                  (when (and (object-of-class-p section 'revu-hunk-section)
                             (equal (car (oref section value)) path))
                    (push section found))
                  (mapc #'walk (oref section children))))
      (walk magit-root-section))
    (nreverse found)))

(defun revu-reviewed-test--two-hunk-alpha (root)
  "Rewrite alpha.txt in the worktree under ROOT so its diff has two hunks.
The first and the last line change, and the six lines between them keep
the two runs of context apart."
  (revu-fixture-write-file
   root "alpha.txt"
   (thread-last revu-fixture-alpha-baseline
                (replace-regexp-in-string "alpha one" "alpha one changed")
                (replace-regexp-in-string "alpha ten" "alpha ten changed"))))

(ert-deftest revu-reviewed-toggle-marks-the-hunk-at-point ()
  "Marking a hunk reviewed records its content digest and collapses it.
The digest is taken over the hunk's body lines only: hunk boundaries and
`@@' numbers regenerate on every diff and are no part of what was read."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree "worktree")
      (revu-fixture-goto-line-matching "^ +7 \\+alpha seven in the worktree$")
      (revu-reviewed-toggle)
      (let ((marks (revu-reviewed-test--marks root "worktree")))
        (should (equal (length marks) 1))
        (should (equal (revu-mark-path (car marks)) "alpha.txt"))
        (should (equal (revu-mark-digest (car marks))
                       (revu-digest revu-reviewed-test--worktree-hunk))))
      (let ((sections (revu-reviewed-test--hunk-sections "alpha.txt")))
        (should (equal (length sections) 1))
        (should (oref (car sections) hidden))))))

(ert-deftest revu-reviewed-toggle-unmarks-what-it-marked ()
  "Toggling a reviewed hunk again drops the mark over what is there now."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree "worktree")
      (revu-fixture-goto-line-matching "^ +7 \\+alpha seven in the worktree$")
      (revu-reviewed-toggle)
      (should (equal (length (revu-reviewed-test--marks root "worktree")) 1))
      (revu-fixture-goto-line-matching "^ +7 \\+alpha seven in the worktree$")
      (revu-reviewed-toggle)
      (should (equal (revu-reviewed-test--marks root "worktree") nil))
      (should-not (oref (car (revu-reviewed-test--hunk-sections "alpha.txt"))
                        hidden)))))

(ert-deftest revu-reviewed-editing-a-hunk-renders-it-unreviewed ()
  "An edited hunk hashes to nothing marked, so it comes back unreviewed.
The mark itself is kept: it is an assertion the reviewer made about
content that genuinely was read, and putting that content back is what
brings the mark into force again."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree "worktree")
      (revu-fixture-goto-line-matching "^ +7 \\+alpha seven in the worktree$")
      (revu-reviewed-toggle))
    (let ((reviewed (revu-fixture-file-contents root "alpha.txt")))
      ;; Edit a line inside the hunk, and read the Review again.
      (revu-fixture-write-file
       root "alpha.txt"
       (replace-regexp-in-string "alpha four" "alpha four edited" reviewed t t))
      (revu-fixture-kill-review-buffers)
      (with-current-buffer (revu-diff-worktree "worktree")
        (should-not (oref (car (revu-reviewed-test--hunk-sections "alpha.txt"))
                          hidden))
        ;; The unmatched mark is still on disk, unpruned.
        (should (equal (length (revu-reviewed-test--marks root "worktree")) 1)))
      ;; Undo the edit, and the mark matches again.
      (revu-fixture-write-file root "alpha.txt" reviewed)
      (revu-fixture-kill-review-buffers)
      (with-current-buffer (revu-diff-worktree "worktree")
        (should (oref (car (revu-reviewed-test--hunk-sections "alpha.txt"))
                      hidden))
        (should (equal (length (revu-reviewed-test--marks root "worktree")) 1))))))

(ert-deftest revu-reviewed-toggle-marks-a-file-one-hunk-at-a-time ()
  "Marking a file reviewed takes a mark per hunk, never one over the file.
A file-level mark could go on claiming the file was read after a hunk
under it changed; a mark per hunk cannot."
  (revu-fixture-in-repo root
    (revu-reviewed-test--two-hunk-alpha root)
    (with-current-buffer (revu-diff-worktree "worktree")
      (should (equal (length (revu-reviewed-test--hunk-sections "alpha.txt")) 2))
      (revu-fixture-goto-line-matching "^modified   alpha\\.txt$")
      (revu-reviewed-toggle)
      (let ((marks (revu-reviewed-test--marks root "worktree")))
        (should (equal (length marks) 2))
        (should (equal (mapcar #'revu-mark-path marks) '("alpha.txt" "alpha.txt")))
        (should (equal (mapcar #'revu-mark-digest marks)
                       (list (revu-digest revu-reviewed-test--first-alpha-hunk)
                             (revu-digest
                              revu-reviewed-test--second-alpha-hunk)))))
      (should (oref (revu-reviewed-test--section "alpha.txt") hidden))
      ;; Toggling the file again drops every mark it took.
      (revu-fixture-goto-line-matching "^modified   alpha\\.txt$")
      (revu-reviewed-toggle)
      (should (equal (revu-reviewed-test--marks root "worktree") nil))
      (should-not (oref (revu-reviewed-test--section "alpha.txt") hidden)))))

(ert-deftest revu-reviewed-file-reads-reviewed-only-when-every-hunk-matches ()
  "A file with one hunk marked and one not is not a reviewed file."
  (revu-fixture-in-repo root
    (revu-reviewed-test--two-hunk-alpha root)
    (with-current-buffer (revu-diff-worktree "worktree")
      (revu-fixture-goto-line-matching "^ +1 \\+alpha one changed$")
      (revu-reviewed-toggle)
      (should-not (oref (revu-reviewed-test--section "alpha.txt") hidden))
      (revu-fixture-goto-line-matching "^ +10 \\+alpha ten changed$")
      (revu-reviewed-toggle)
      (should (oref (revu-reviewed-test--section "alpha.txt") hidden)))))

(ert-deftest revu-reviewed-toggle-advances-to-the-next-unreviewed-hunk ()
  "Marking a hunk moves the reviewer on to the next hunk they have not read."
  (revu-fixture-in-repo root
    (revu-reviewed-test--two-hunk-alpha root)
    (with-current-buffer (revu-diff-worktree "worktree")
      (revu-fixture-goto-line-matching "^ +1 \\+alpha one changed$")
      (revu-reviewed-toggle)
      (let ((sections (revu-reviewed-test--hunk-sections "alpha.txt")))
        (should (equal (length sections) 2))
        (should (= (point) (oref (nth 1 sections) start)))))))

(ert-deftest revu-reviewed-toggle-advances-with-hide-reviewed-on ()
  "Hiding what is read does not cost the reviewer the move to what is not.
With hide-reviewed on, the hunk just marked leaves the buffer entirely,
so there is no section left to collapse -- but the reviewer still asked
to be moved on, and grinding through a large Source is the whole point of
the filter."
  (revu-fixture-in-repo root
    (revu-reviewed-test--two-hunk-alpha root)
    (with-current-buffer (revu-diff-worktree "worktree")
      (revu-reviewed-toggle-hide-reviewed)
      (unwind-protect
          (progn
            (revu-fixture-goto-line-matching "^ +1 \\+alpha one changed$")
            (revu-reviewed-toggle)
            ;; The marked hunk has left the buffer; the one left is unread,
            ;; and point is on its heading rather than stranded.
            (let ((rendered (revu-fixture-render)))
              (should-not (string-match-p "alpha one changed" rendered))
              (should (string-match-p "alpha ten changed" rendered)))
            (should (string-prefix-p
                     "@@"
                     (buffer-substring-no-properties
                      (point) (line-end-position)))))
        (setq revu-reviewed-hide-reviewed nil)))))

(ert-deftest revu-reviewed-filters-shape-the-render-and-compose ()
  "The two filters each shape the render, and both at once compose.
Reviewed and annotated are orthogonal: an annotated hunk that has been
marked reviewed is still findable while only the annotated-only filter is
on, and drops out as soon as hide-reviewed joins it."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree "worktree")
      (revu-fixture-goto-line-matching "^ +7 \\+alpha seven in the worktree$")
      (revu-annotate-line "question" "Read and asked about")
      ;; Annotated-only leaves the files nothing was written on out.
      (revu-reviewed-toggle-annotated-only)
      (should (string-match-p "alpha\\.txt" (revu-fixture-render)))
      (should-not (string-match-p "beta\\.txt" (revu-fixture-render)))
      ;; Marking it reviewed does not take it away from that filter.
      (revu-fixture-goto-line-matching "^ +7 \\+alpha seven in the worktree$")
      (revu-reviewed-toggle)
      (should (string-match-p "alpha\\.txt" (revu-fixture-render)))
      ;; With hide-reviewed on as well, both filters have to be passed.
      (revu-reviewed-toggle-hide-reviewed)
      (should-not (string-match-p "alpha\\.txt" (revu-fixture-render)))
      (should-not (string-match-p "beta\\.txt" (revu-fixture-render)))
      ;; Hide-reviewed alone takes the reviewed file out and leaves the rest.
      (revu-reviewed-toggle-annotated-only)
      (should-not (string-match-p "alpha\\.txt" (revu-fixture-render)))
      (should (string-match-p "beta\\.txt" (revu-fixture-render)))
      ;; And with neither on, the whole Source is back.
      (revu-reviewed-toggle-hide-reviewed)
      (should (string-match-p "alpha\\.txt" (revu-fixture-render)))
      (should (string-match-p "beta\\.txt" (revu-fixture-render))))))

(provide 'revu-reviewed-test)
;;; revu-reviewed-test.el ends here
