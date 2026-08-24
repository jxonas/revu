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

(ert-deftest revu-reviewed-toggle-collapses-on-screen-and-expands-again ()
  "Marking collapses the hunk on screen, and unmarking opens it again.
The collapse is the Reviewed mark rendered, not a `magit-section-hide'
the command runs behind the render: the state decides what the reviewer
sees (ADR-0008)."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree "worktree")
      (revu-fixture-goto-line-matching "^ +7 \\+alpha seven in the worktree$")
      (revu-reviewed-toggle)
      (should (revu-fixture-hidden-on-screen-p
               (car (revu-reviewed-test--hunk-sections "alpha.txt"))))
      (goto-char (oref (car (revu-reviewed-test--hunk-sections "alpha.txt"))
                       start))
      (revu-reviewed-toggle)
      (should-not (revu-fixture-hidden-on-screen-p
                   (car (revu-reviewed-test--hunk-sections "alpha.txt")))))))

(ert-deftest revu-reviewed-mark-collapses-what-it-marks-on-a-fresh-render ()
  "A hunk read in an earlier sitting comes back collapsed on screen."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree "worktree")
      (revu-fixture-goto-line-matching "^ +7 \\+alpha seven in the worktree$")
      (revu-reviewed-toggle))
    (revu-fixture-kill-review-buffers)
    (with-current-buffer (revu-diff-worktree "worktree")
      (should (revu-fixture-hidden-on-screen-p
               (car (revu-reviewed-test--hunk-sections "alpha.txt")))))))

(ert-deftest revu-reviewed-toggle-leaves-other-folds-alone ()
  "Marking one hunk disturbs no fold the reviewer set, in this file or another.
The marks decide what the section just toggled looks like, and the file
it is in, because marking the last unread hunk makes the file read.  A
hunk beside it that the reviewer folded by hand and has not read is
neither, and stays folded."
  (revu-fixture-in-repo root
    (revu-reviewed-test--two-hunk-alpha root)
    (with-current-buffer (revu-diff-worktree "worktree")
      (magit-section-hide (revu-reviewed-test--section "beta.txt"))
      (magit-section-hide (nth 1 (revu-reviewed-test--hunk-sections "alpha.txt")))
      (revu-fixture-goto-line-matching "^ +1 \\+alpha one changed$")
      (revu-reviewed-toggle)
      (should (revu-fixture-hidden-on-screen-p
               (revu-reviewed-test--section "beta.txt")))
      (should (revu-fixture-hidden-on-screen-p
               (nth 1 (revu-reviewed-test--hunk-sections "alpha.txt")))))))

(ert-deftest revu-reviewed-toggle-marks-a-file-one-hunk-at-a-time ()
  "Marking a file reviewed takes a mark per hunk, never one over the file.
A file-level mark could go on claiming the file was read after a hunk
under it changed; a mark per hunk cannot."
  (revu-fixture-in-repo root
    (revu-reviewed-test--two-hunk-alpha root)
    (with-current-buffer (revu-diff-worktree "worktree")
      (should (equal (length (revu-reviewed-test--hunk-sections "alpha.txt")) 2))
      (revu-fixture-goto-line-matching "^modified   alpha\\.txt")
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
      (revu-fixture-goto-line-matching "^modified   alpha\\.txt")
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

(defun revu-reviewed-test--heading (regexp)
  "Return the whole rendered line whose start matches REGEXP."
  (save-excursion
    (goto-char (point-min))
    (should (re-search-forward regexp nil t))
    (buffer-substring-no-properties (line-beginning-position)
                                    (line-end-position))))

(ert-deftest revu-reviewed-badges-the-heading-of-what-was-read ()
  "A reviewed hunk says so on its heading, whatever its fold is doing.
Collapsing is one of the two things marking does and never the only sign
that it happened: the badge is part of the heading, so opening the
section again to re-read it leaves the mark on screen."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree "worktree")
      (should-not (string-match-p revu-render-reviewed-glyph
                                  (revu-fixture-render)))
      (revu-fixture-goto-line-matching "^ +7 \\+alpha seven in the worktree$")
      (revu-reviewed-toggle)
      (let ((section (car (revu-reviewed-test--hunk-sections "alpha.txt"))))
        (should (string-suffix-p revu-render-reviewed-glyph
                                 (revu-reviewed-test--heading "^@@")))
        ;; Opening it again to re-read it keeps the badge.
        (goto-char (oref section start))
        (revu-fixture-press-tab)
        (should-not (revu-fixture-hidden-on-screen-p
                     (car (revu-reviewed-test--hunk-sections "alpha.txt"))))
        (should (string-suffix-p revu-render-reviewed-glyph
                                 (revu-reviewed-test--heading "^@@")))))))

(ert-deftest revu-reviewed-badges-a-hunk-read-and-changed-since-as-stale ()
  "A hunk the reviewer read and something else changed reads as stale.
Silence is what misleads here: without the badge the hunk is
pixel-identical to code nobody has read, so rework cannot be told from
new work."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree "worktree")
      (revu-fixture-goto-line-matching "^ +7 \\+alpha seven in the worktree$")
      (revu-reviewed-toggle))
    (revu-fixture-write-file
     root "alpha.txt"
     (replace-regexp-in-string "alpha four" "alpha four edited"
                               (revu-fixture-file-contents root "alpha.txt")
                               t t))
    (revu-fixture-kill-review-buffers)
    (with-current-buffer (revu-diff-worktree "worktree")
      (let ((heading (revu-reviewed-test--heading "^@@")))
        (should (string-suffix-p revu-render-stale-glyph heading))
        (should-not (string-match-p revu-render-reviewed-glyph heading))))))

(ert-deftest revu-reviewed-leaves-a-hunk-nobody-read-unbadged ()
  "A hunk beside a stale one, that was never read, is not called stale.
The mark records the base lines it was taken over, so an assertion that
has stopped holding is attributed to the hunk that grew out of those
lines and to no other.  Calling new work rework is the same lie as
calling rework new."
  (revu-fixture-in-repo root
    (revu-reviewed-test--two-hunk-alpha root)
    (with-current-buffer (revu-diff-worktree "worktree")
      (revu-fixture-goto-line-matching "^ +1 \\+alpha one changed$")
      (revu-reviewed-toggle))
    (revu-fixture-write-file
     root "alpha.txt"
     (replace-regexp-in-string "alpha one changed" "alpha one changed twice"
                               (revu-fixture-file-contents root "alpha.txt")
                               t t))
    (revu-fixture-kill-review-buffers)
    (with-current-buffer (revu-diff-worktree "worktree")
      (let ((review (revu-review))
            (sections (revu-reviewed-test--hunk-sections "alpha.txt")))
        (should (equal (length sections) 2))
        (should (equal (revu-reviewed-state review revu--files
                                            (oref (nth 0 sections) value))
                       'stale))
        (should (equal (revu-reviewed-state review revu--files
                                            (oref (nth 1 sections) value))
                       nil))))))

(ert-deftest revu-reviewed-attributes-nothing-to-a-mark-with-no-span ()
  "A mark taken before revu recorded spans attributes to no hunk.
A Sidecar written by an older revu says which file was read and not which
lines, so the hunk that changed cannot be told from the one beside it.
The render says nothing rather than guessing which of them to accuse."
  (revu-fixture-in-repo root
    (revu-reviewed-test--two-hunk-alpha root)
    (with-current-buffer (revu-diff-worktree "worktree")
      (revu-fixture-goto-line-matching "^ +1 \\+alpha one changed$")
      (revu-reviewed-toggle))
    ;; Rewrite the Sidecar as an older revu would have left it.
    (let ((file (expand-file-name ".revu/worktree.json" root)))
      (with-temp-file file
        (insert (replace-regexp-in-string
                 "\"span\": *\\[[0-9]+, *[0-9]+\\], *" ""
                 (revu-fixture-sidecar-text root "worktree")))))
    (revu-fixture-write-file
     root "alpha.txt"
     (replace-regexp-in-string "alpha one changed" "alpha one changed twice"
                               (revu-fixture-file-contents root "alpha.txt")
                               t t))
    (revu-fixture-kill-review-buffers)
    (with-current-buffer (revu-diff-worktree "worktree")
      (should-not (revu-mark-span
                   (car (revu-reviewed-test--marks root "worktree"))))
      (should-not (string-match-p revu-render-stale-glyph
                                  (revu-fixture-render))))))

(ert-deftest revu-reviewed-hashes-nothing-for-a-path-nothing-was-marked-on ()
  "A path carrying no mark carries no assertion that could have stopped holding.
Discovering that costs a lookup and never a digest: every hunk of a file
asks the same question, and a Source nobody has marked yet would
otherwise pay for hashing all of it on every render."
  (revu-fixture-in-repo root
    (revu-reviewed-test--two-hunk-alpha root)
    (with-current-buffer (revu-diff-worktree "worktree")
      (cl-letf (((symbol-function 'revu-reviewed--digests)
                 (lambda (&rest _) (error "Hashed a path with no marks on it"))))
        (should-not (revu-reviewed--dangling-marks (revu-review) revu--files
                                                   "alpha.txt"))))))

(ert-deftest revu-reviewed-file-heading-counts-the-hunks-that-match ()
  "A file part-way read says how much of it is left, not that it is neither.
Working down a large file is the case Reviewed marks exist for, and how
many of its hunks are read is the question being asked of its heading."
  (revu-fixture-in-repo root
    (revu-reviewed-test--two-hunk-alpha root)
    (with-current-buffer (revu-diff-worktree "worktree")
      (should-not (string-match-p "/" (revu-reviewed-test--heading
                                       "^modified   alpha\\.txt")))
      (revu-fixture-goto-line-matching "^ +1 \\+alpha one changed$")
      (revu-reviewed-toggle)
      (should (string-suffix-p "1/2" (revu-reviewed-test--heading
                                      "^modified   alpha\\.txt")))
      ;; Reading the rest of it leaves the glyph to say so on its own.
      (revu-fixture-goto-line-matching "^ +10 \\+alpha ten changed$")
      (revu-reviewed-toggle)
      (let ((heading (revu-reviewed-test--heading "^modified   alpha\\.txt")))
        (should (string-suffix-p revu-render-reviewed-glyph heading))
        (should-not (string-match-p "/" heading))))))

(provide 'revu-reviewed-test)
;;; revu-reviewed-test.el ends here
