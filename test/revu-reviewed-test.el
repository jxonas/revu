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

(ert-deftest revu-reviewed-toggle-marks-the-hunk-at-point ()
  "Marking a hunk reviewed records its content digest and collapses it.
The digest is taken over the hunk's body lines only: hunk boundaries and
`@@' numbers regenerate on every diff and are no part of what was read."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree "worktree")
      (revu-fixture-goto-line-matching "^\\+alpha seven in the worktree$")
      (revu-reviewed-toggle)
      (let ((marks (revu-reviewed-test--marks root "worktree")))
        (should (equal (length marks) 1))
        (should (equal (revu-mark-path (car marks)) "alpha.txt"))
        (should (equal (revu-mark-digest (car marks))
                       (revu-digest revu-reviewed-test--worktree-hunk))))
      (let ((sections (revu-fixture-hunk-sections "alpha.txt")))
        (should (equal (length sections) 1))
        (should (oref (car sections) hidden))))))

(ert-deftest revu-reviewed-toggle-unmarks-what-it-marked ()
  "Toggling a reviewed hunk again drops the mark over what is there now."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree "worktree")
      (revu-fixture-goto-line-matching "^\\+alpha seven in the worktree$")
      (revu-reviewed-toggle)
      (should (equal (length (revu-reviewed-test--marks root "worktree")) 1))
      (revu-fixture-goto-line-matching "^\\+alpha seven in the worktree$")
      (revu-reviewed-toggle)
      (should (equal (revu-reviewed-test--marks root "worktree") nil))
      (should-not (oref (car (revu-fixture-hunk-sections "alpha.txt"))
                        hidden)))))

(ert-deftest revu-reviewed-editing-a-hunk-renders-it-unreviewed ()
  "An edited hunk hashes to nothing marked, so it comes back unreviewed.
The mark itself is kept: it is an assertion the reviewer made about
content that genuinely was read, and putting that content back is what
brings the mark into force again."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree "worktree")
      (revu-fixture-goto-line-matching "^\\+alpha seven in the worktree$")
      (revu-reviewed-toggle))
    (let ((reviewed (revu-fixture-file-contents root "alpha.txt")))
      ;; Edit a line inside the hunk, and read the Review again.
      (revu-fixture-write-file
       root "alpha.txt"
       (replace-regexp-in-string "alpha four" "alpha four edited" reviewed t t))
      (revu-fixture-kill-review-buffers)
      (with-current-buffer (revu-diff-worktree "worktree")
        (should-not (oref (car (revu-fixture-hunk-sections "alpha.txt"))
                          hidden))
        ;; The unmatched mark is still on disk, unpruned.
        (should (equal (length (revu-reviewed-test--marks root "worktree")) 1)))
      ;; Undo the edit, and the mark matches again.
      (revu-fixture-write-file root "alpha.txt" reviewed)
      (revu-fixture-kill-review-buffers)
      (with-current-buffer (revu-diff-worktree "worktree")
        (should (oref (car (revu-fixture-hunk-sections "alpha.txt"))
                      hidden))
        (should (equal (length (revu-reviewed-test--marks root "worktree")) 1))))))

(ert-deftest revu-reviewed-toggle-collapses-on-screen-and-expands-again ()
  "Marking collapses the hunk on screen, and unmarking opens it again.
The collapse is the Reviewed mark rendered, not a `magit-section-hide'
the command runs behind the render: the state decides what the reviewer
sees (ADR-0008)."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree "worktree")
      (revu-fixture-goto-line-matching "^\\+alpha seven in the worktree$")
      (revu-reviewed-toggle)
      (should (revu-fixture-hidden-on-screen-p
               (car (revu-fixture-hunk-sections "alpha.txt"))))
      (goto-char (oref (car (revu-fixture-hunk-sections "alpha.txt"))
                       start))
      (revu-reviewed-toggle)
      (should-not (revu-fixture-hidden-on-screen-p
                   (car (revu-fixture-hunk-sections "alpha.txt")))))))

(ert-deftest revu-reviewed-mark-collapses-what-it-marks-on-a-fresh-render ()
  "A hunk read in an earlier sitting comes back collapsed on screen."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree "worktree")
      (revu-fixture-goto-line-matching "^\\+alpha seven in the worktree$")
      (revu-reviewed-toggle))
    (revu-fixture-kill-review-buffers)
    (with-current-buffer (revu-diff-worktree "worktree")
      (should (revu-fixture-hidden-on-screen-p
               (car (revu-fixture-hunk-sections "alpha.txt")))))))

(ert-deftest revu-reviewed-toggle-leaves-other-folds-alone ()
  "Marking one hunk disturbs no fold the reviewer set, in this file or another.
The marks decide what the section just toggled looks like, and the file
it is in, because marking the last unread hunk makes the file read.  A
hunk beside it that the reviewer folded by hand and has not read is
neither, and stays folded."
  (revu-fixture-in-repo root
    (revu-fixture-two-hunk-alpha root)
    (with-current-buffer (revu-diff-worktree "worktree")
      (magit-section-hide (revu-reviewed-test--section "beta.txt"))
      (magit-section-hide (nth 1 (revu-fixture-hunk-sections "alpha.txt")))
      (revu-fixture-goto-line-matching "^\\+alpha one changed$")
      (revu-reviewed-toggle)
      (should (revu-fixture-hidden-on-screen-p
               (revu-reviewed-test--section "beta.txt")))
      (should (revu-fixture-hidden-on-screen-p
               (nth 1 (revu-fixture-hunk-sections "alpha.txt")))))))

(ert-deftest revu-reviewed-toggle-marks-a-file-one-hunk-at-a-time ()
  "Marking a file reviewed takes a mark per hunk, never one over the file.
A file-level mark could go on claiming the file was read after a hunk
under it changed; a mark per hunk cannot."
  (revu-fixture-in-repo root
    (revu-fixture-two-hunk-alpha root)
    (with-current-buffer (revu-diff-worktree "worktree")
      (should (equal (length (revu-fixture-hunk-sections "alpha.txt")) 2))
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
    (revu-fixture-two-hunk-alpha root)
    (with-current-buffer (revu-diff-worktree "worktree")
      (revu-fixture-goto-line-matching "^\\+alpha one changed$")
      (revu-reviewed-toggle)
      (should-not (oref (revu-reviewed-test--section "alpha.txt") hidden))
      (revu-fixture-goto-line-matching "^\\+alpha ten changed$")
      (revu-reviewed-toggle)
      (should (oref (revu-reviewed-test--section "alpha.txt") hidden)))))

(ert-deftest revu-reviewed-toggle-advances-to-the-next-hunk ()
  "Marking a hunk moves the reviewer on to the next hunk's heading."
  (revu-fixture-in-repo root
    (revu-fixture-two-hunk-alpha root)
    (with-current-buffer (revu-diff-worktree "worktree")
      (revu-fixture-goto-line-matching "^\\+alpha one changed$")
      (revu-reviewed-toggle)
      (let ((sections (revu-fixture-hunk-sections "alpha.txt")))
        (should (equal (length sections) 2))
        (should (= (point) (oref (nth 1 sections) start)))))))

(ert-deftest revu-reviewed-toggle-advances-from-the-last-hunk-to-the-next-file ()
  "The section after the last hunk of a file is the next file itself.
The advance is one walk over siblings: within a file it steps hunk to
hunk, and off the end of one it steps to the file below."
  (revu-fixture-in-repo root
    (revu-fixture-two-hunk-alpha root)
    (with-current-buffer (revu-diff-worktree "worktree")
      (revu-fixture-goto-line-matching "^\\+alpha ten changed$")
      (revu-reviewed-toggle)
      (should (= (point) (oref (revu-reviewed-test--section "beta.txt") start))))))

(ert-deftest revu-reviewed-toggle-advances-onto-what-was-read-already ()
  "The next sibling is the next sibling, reviewed or not.
Stepping over read work would leave the reviewer somewhere they cannot
predict from what is on screen; the badge on the heading already says
the section was read, and moving through it is one keypress."
  (revu-fixture-in-repo root
    (revu-fixture-two-hunk-alpha root)
    (with-current-buffer (revu-diff-worktree "worktree")
      (revu-fixture-goto-line-matching "^\\+beta two staged$")
      (revu-reviewed-toggle)
      (revu-fixture-goto-line-matching "^\\+alpha ten changed$")
      (revu-reviewed-toggle)
      (should (= (point) (oref (revu-reviewed-test--section "beta.txt") start))))))

(ert-deftest revu-reviewed-toggle-advances-past-a-collapsed-file ()
  "With every file collapsed, marking one lands on the next file's heading.
A heading below a fold is not somewhere point can be left: Emacs pushes
it out of the invisible text at the end of the command, past the whole
file the fold covers.  The fold is the reviewer's own and the advance
leaves it alone."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree "worktree")
      (mapc #'magit-section-hide (revu-fixture-sections 'revu-file-section))
      (revu-fixture-goto-line-matching "^modified   alpha\\.txt")
      (revu-reviewed-toggle)
      (let ((beta (revu-reviewed-test--section "beta.txt")))
        (should (= (point) (oref beta start)))
        (should (revu-fixture-hidden-on-screen-p beta))))))

(ert-deftest revu-reviewed-toggle-advances-with-hide-reviewed-on ()
  "Hiding what is read does not cost the reviewer the move to what is next.
With hide-reviewed on, the hunk just marked leaves the buffer entirely,
so there is no section left to advance from -- but the reviewer still
asked to be moved on, and grinding through a large Source is the whole
point of the filter.  The walk is over the Source's order rather than the
buffer's for exactly this reason."
  (revu-fixture-in-repo root
    (revu-fixture-two-hunk-alpha root)
    (with-current-buffer (revu-diff-worktree "worktree")
      (revu-reviewed-toggle-hide-reviewed)
      (unwind-protect
          (progn
            (revu-fixture-goto-line-matching "^\\+alpha one changed$")
            (revu-reviewed-toggle)
            (let ((rendered (revu-fixture-render)))
              (should-not (string-match-p "alpha one changed" rendered))
              (should (string-match-p "alpha ten changed" rendered)))
            (let ((sections (revu-fixture-hunk-sections "alpha.txt")))
              (should (equal (length sections) 1))
              (should (= (point) (oref (car sections) start)))))
        (setq revu-reviewed-hide-reviewed nil)))))

(ert-deftest revu-reviewed-toggle-stays-on-the-last-file-of-the-source ()
  "Marking the last file leaves point on it: there is nowhere to advance to.
Moving anywhere else would be a guess, and the reviewer has read to the
end of what is shown."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree "worktree")
      (revu-fixture-goto-line-matching "^deleted    gamma\\.txt")
      (revu-reviewed-toggle)
      (should (= (point) (oref (revu-reviewed-test--section "gamma.txt") start))))))

(ert-deftest revu-reviewed-toggle-lands-on-the-heading-of-a-collapsed-parent ()
  "Point never lands under a fold; it lands on the heading of the fold.
Marking the last hunk of the last file makes that file read, so the
render collapses it and the hunk's own heading goes with it.  The file's
heading is where the reviewer is left, and nothing is opened to get them
there."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree "worktree")
      (revu-fixture-goto-line-matching "^-gamma one$")
      (revu-reviewed-toggle)
      (let ((gamma (revu-reviewed-test--section "gamma.txt")))
        (should (= (point) (oref gamma start)))
        (should (revu-fixture-hidden-on-screen-p gamma))))))

(ert-deftest revu-reviewed-toggle-falls-back-to-what-is-above-it ()
  "With the last file marked and hidden, point goes to the section above it.
Nothing rendered follows what was marked and what was marked is gone, so
the nearest rendered section before it is where the reviewer is left."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree "worktree")
      (revu-reviewed-toggle-hide-reviewed)
      (unwind-protect
          (progn
            (revu-fixture-goto-line-matching "^deleted    gamma\\.txt")
            (revu-reviewed-toggle)
            (should-not (string-match-p "gamma" (revu-fixture-render)))
            (should (= (point)
                       (oref (revu-reviewed-test--section "delta-renamed.txt")
                             start))))
        (setq revu-reviewed-hide-reviewed nil)))))

(ert-deftest revu-reviewed-unmarking-does-not-move-point ()
  "Taking a mark back is not reading anything, so it moves nobody on."
  (revu-fixture-in-repo root
    (revu-fixture-two-hunk-alpha root)
    (with-current-buffer (revu-diff-worktree "worktree")
      (revu-fixture-goto-line-matching "^\\+alpha one changed$")
      (revu-reviewed-toggle)
      (goto-char (oref (revu-fixture-hunk-section "alpha.txt" 0) start))
      (revu-reviewed-toggle)
      (should (= (point) (oref (revu-fixture-hunk-section "alpha.txt" 0)
                               start))))))

(ert-deftest revu-reviewed-filters-shape-the-render-and-compose ()
  "The two filters each shape the render, and both at once compose.
Reviewed and annotated are orthogonal: an annotated hunk that has been
marked reviewed is still findable while only the annotated-only filter is
on, and drops out as soon as hide-reviewed joins it."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree "worktree")
      (revu-fixture-goto-line-matching "^\\+alpha seven in the worktree$")
      (revu-annotate-line "question" "Read and asked about")
      ;; Annotated-only leaves the files nothing was written on out.
      (revu-reviewed-toggle-annotated-only)
      (should (string-match-p "alpha\\.txt" (revu-fixture-render)))
      (should-not (string-match-p "beta\\.txt" (revu-fixture-render)))
      ;; Marking it reviewed does not take it away from that filter.
      (revu-fixture-goto-line-matching "^\\+alpha seven in the worktree$")
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
      (revu-fixture-goto-line-matching "^\\+alpha seven in the worktree$")
      (revu-reviewed-toggle)
      (let ((section (car (revu-fixture-hunk-sections "alpha.txt"))))
        (should (string-suffix-p revu-render-reviewed-glyph
                                 (revu-reviewed-test--heading "^@@")))
        ;; Opening it again to re-read it keeps the badge.
        (goto-char (oref section start))
        (revu-fixture-press-tab)
        (should-not (revu-fixture-hidden-on-screen-p
                     (car (revu-fixture-hunk-sections "alpha.txt"))))
        (should (string-suffix-p revu-render-reviewed-glyph
                                 (revu-reviewed-test--heading "^@@")))))))

(ert-deftest revu-reviewed-badges-a-hunk-read-and-changed-since-as-stale ()
  "A hunk the reviewer read and something else changed reads as stale.
Silence is what misleads here: without the badge the hunk is
pixel-identical to code nobody has read, so rework cannot be told from
new work."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree "worktree")
      (revu-fixture-goto-line-matching "^\\+alpha seven in the worktree$")
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
    (revu-fixture-two-hunk-alpha root)
    (with-current-buffer (revu-diff-worktree "worktree")
      (revu-fixture-goto-line-matching "^\\+alpha one changed$")
      (revu-reviewed-toggle))
    (revu-fixture-write-file
     root "alpha.txt"
     (replace-regexp-in-string "alpha one changed" "alpha one changed twice"
                               (revu-fixture-file-contents root "alpha.txt")
                               t t))
    (revu-fixture-kill-review-buffers)
    (with-current-buffer (revu-diff-worktree "worktree")
      (let ((review (revu-review))
            (sections (revu-fixture-hunk-sections "alpha.txt")))
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
    (revu-fixture-two-hunk-alpha root)
    (with-current-buffer (revu-diff-worktree "worktree")
      (revu-fixture-goto-line-matching "^\\+alpha one changed$")
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
    (revu-fixture-two-hunk-alpha root)
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
    (revu-fixture-two-hunk-alpha root)
    (with-current-buffer (revu-diff-worktree "worktree")
      (should-not (string-match-p "/" (revu-reviewed-test--heading
                                       "^modified   alpha\\.txt")))
      (revu-fixture-goto-line-matching "^\\+alpha one changed$")
      (revu-reviewed-toggle)
      (should (string-suffix-p "1/2" (revu-reviewed-test--heading
                                      "^modified   alpha\\.txt")))
      ;; Reading the rest of it leaves the glyph to say so on its own.
      (revu-fixture-goto-line-matching "^\\+alpha ten changed$")
      (revu-reviewed-toggle)
      (let ((heading (revu-reviewed-test--heading "^modified   alpha\\.txt")))
        (should (string-suffix-p revu-render-reviewed-glyph heading))
        (should-not (string-match-p "/" heading))))))

;;;; Marking a run in one gesture

(ert-deftest revu-reviewed-toggle-marks-a-selected-run-of-hunks ()
  "A region spanning sibling hunk headings marks every hunk it covers.
One press, one mark per hunk: the run is a gesture, and what it leaves
behind is the same marks eight presses would have left."
  (revu-fixture-in-repo root
    (revu-fixture-two-hunk-alpha root)
    (with-current-buffer (revu-diff-worktree "worktree")
      (revu-fixture-with-selection (revu-fixture-hunk-section "alpha.txt" 0)
          (revu-fixture-hunk-section "alpha.txt" 1)
        (revu-reviewed-toggle))
      (let ((marks (revu-reviewed-test--marks root "worktree")))
        (should (equal (mapcar #'revu-mark-digest marks)
                       (list (revu-digest revu-reviewed-test--first-alpha-hunk)
                             (revu-digest
                              revu-reviewed-test--second-alpha-hunk))))))))

(ert-deftest revu-reviewed-toggle-marks-a-selected-run-of-files ()
  "A region spanning sibling file headings marks every hunk under them.
A file is still marked one hunk at a time (ADR-0009); selecting two of
them only says which files."
  (revu-fixture-in-repo root
    (revu-fixture-two-hunk-alpha root)
    (with-current-buffer (revu-diff-worktree "worktree")
      (revu-fixture-with-selection (revu-reviewed-test--section "alpha.txt")
          (revu-reviewed-test--section "beta.txt")
        (revu-reviewed-toggle))
      (should (equal (mapcar #'revu-mark-path
                             (revu-reviewed-test--marks root "worktree"))
                     '("alpha.txt" "alpha.txt" "beta.txt"))))))

(ert-deftest revu-reviewed-toggle-reads-a-region-inside-a-hunk-as-no-selection ()
  "A region inside one hunk's body is a run of lines, not a run of sections.
It marks the hunk point is in, exactly as no region at all would."
  (revu-fixture-in-repo root
    (revu-fixture-two-hunk-alpha root)
    (with-current-buffer (revu-diff-worktree "worktree")
      (let ((transient-mark-mode t))
        (revu-fixture-goto-line-matching "^ alpha two$")
        (push-mark (point) t t)
        (revu-fixture-goto-line-matching "^ alpha four$")
        (revu-reviewed-toggle))
      (should (equal (mapcar #'revu-mark-digest
                             (revu-reviewed-test--marks root "worktree"))
                     (list (revu-digest
                            revu-reviewed-test--first-alpha-hunk)))))))

(ert-deftest revu-reviewed-annotates-a-region-inside-a-hunk-as-a-range ()
  "The same region an Annotation is taken over is still a range Target.
The region has two meanings in the review buffer and this is the other
one: inside a body it is Source lines, and `a' has not changed."
  (revu-fixture-in-repo root
    (revu-fixture-two-hunk-alpha root)
    (with-current-buffer (revu-diff-worktree "worktree")
      (let ((transient-mark-mode t))
        (revu-fixture-goto-line-matching "^ alpha two$")
        (push-mark (point) t t)
        (revu-fixture-goto-line-matching "^ alpha four$")
        (revu-annotate "change" "About these lines"))
      (let ((annotations (append (revu-review-annotations
                                  (revu-fixture-sidecar root "worktree"))
                                 nil)))
        (should (equal (length annotations) 1))
        (should (equal (revu-target-kind
                        (revu-annotation-target (car annotations)))
                       "range"))))))

(ert-deftest revu-reviewed-toggle-marks-the-rest-of-a-selection ()
  "A selection marks and never flips, so a hunk already read keeps its mark."
  (revu-fixture-in-repo root
    (revu-fixture-two-hunk-alpha root)
    (with-current-buffer (revu-diff-worktree "worktree")
      (revu-fixture-goto-line-matching "^\\+alpha one changed$")
      (revu-reviewed-toggle)
      (should (equal (length (revu-reviewed-test--marks root "worktree")) 1))
      (revu-fixture-with-selection (revu-fixture-hunk-section "alpha.txt" 0)
          (revu-fixture-hunk-section "alpha.txt" 1)
        (revu-reviewed-toggle))
      (should (equal (mapcar #'revu-mark-digest
                             (revu-reviewed-test--marks root "worktree"))
                     (list (revu-digest revu-reviewed-test--first-alpha-hunk)
                           (revu-digest
                            revu-reviewed-test--second-alpha-hunk)))))))

(ert-deftest revu-reviewed-toggle-unmarks-a-selection-with-a-prefix-argument ()
  "A prefix argument unmarks the run the region selects."
  (revu-fixture-in-repo root
    (revu-fixture-two-hunk-alpha root)
    (with-current-buffer (revu-diff-worktree "worktree")
      (revu-fixture-with-selection (revu-fixture-hunk-section "alpha.txt" 0)
          (revu-fixture-hunk-section "alpha.txt" 1)
        (revu-reviewed-toggle))
      (should (equal (length (revu-reviewed-test--marks root "worktree")) 2))
      (revu-fixture-with-selection (revu-fixture-hunk-section "alpha.txt" 0)
          (revu-fixture-hunk-section "alpha.txt" 1)
        (revu-reviewed-toggle t))
      (should (equal (revu-reviewed-test--marks root "worktree") nil)))))

(ert-deftest revu-reviewed-toggle-unmarks-the-section-at-point-with-a-prefix ()
  "With no selection a prefix argument unmarks, and never marks."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree "worktree")
      (revu-fixture-goto-line-matching revu-fixture-worktree-seven)
      ;; An unread hunk is not marked by the argument that unmarks.
      (revu-reviewed-toggle t)
      (should (equal (revu-reviewed-test--marks root "worktree") nil))
      (revu-reviewed-toggle)
      (should (equal (length (revu-reviewed-test--marks root "worktree")) 1))
      (revu-fixture-goto-line-matching revu-fixture-worktree-seven)
      (revu-reviewed-toggle t)
      (should (equal (revu-reviewed-test--marks root "worktree") nil)))))

(ert-deftest revu-reviewed-toggle-skips-what-has-nothing-to-mark ()
  "A rename that changed no line has no assertion to make, and is passed over.
The rest of the selection is marked, and the reviewer is told what was
left out rather than being left to count marks."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree "worktree")
      (let ((said nil))
        (cl-letf (((symbol-function 'message)
                   (lambda (format &rest arguments)
                     (push (apply #'format format arguments) said))))
          (revu-fixture-with-selection
              (revu-reviewed-test--section "beta.txt")
              (revu-reviewed-test--section "gamma.txt")
            (revu-reviewed-toggle)))
        (should (equal (mapcar #'revu-mark-path
                               (revu-reviewed-test--marks root "worktree"))
                       '("beta.txt" "gamma.txt")))
        (should (seq-find (lambda (line)
                            (string-match-p "Skipped 1 section" line))
                          said))))))

(ert-deftest revu-reviewed-toggle-refuses-a-selection-with-nothing-to-mark ()
  "A selection of nothing markable is an error, not a silent no-op."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree "worktree")
      (let ((renamed (revu-reviewed-test--section "delta-renamed.txt")))
        (should-error (revu-fixture-with-selection renamed renamed
                        (revu-reviewed-toggle))
                      :type 'user-error))
      (should (equal (revu-reviewed-test--marks root "worktree") nil)))))

(ert-deftest revu-reviewed-toggle-writes-and-renders-once-for-a-run ()
  "The whole gesture is one Sidecar write and one render.
A write per hunk would mean a render per hunk, and the render is what a
large Source is expensive to redraw."
  (revu-fixture-in-repo root
    (revu-fixture-two-hunk-alpha root)
    (with-current-buffer (revu-diff-worktree "worktree")
      (let ((writes 0)
            (renders 0)
            (write (symbol-function 'revu-sidecar-write))
            (render (symbol-function 'revu-render)))
        (cl-letf (((symbol-function 'revu-sidecar-write)
                   (lambda (&rest arguments)
                     (setq writes (1+ writes))
                     (apply write arguments)))
                  ((symbol-function 'revu-render)
                   (lambda (&rest arguments)
                     (setq renders (1+ renders))
                     (apply render arguments))))
          (revu-fixture-with-selection
              (revu-reviewed-test--section "alpha.txt")
              (revu-reviewed-test--section "beta.txt")
            (revu-reviewed-toggle)))
        (should (equal (length (revu-reviewed-test--marks root "worktree")) 3))
        (should (equal writes 1))
        (should (equal renders 1))))))

(ert-deftest revu-reviewed-toggle-advances-past-a-marked-run ()
  "Marking a run moves the reviewer on from the last section it covered.
The run ends on the last hunk of alpha.txt, so the section after it is
beta.txt."
  (revu-fixture-in-repo root
    (revu-fixture-two-hunk-alpha root)
    (with-current-buffer (revu-diff-worktree "worktree")
      (revu-fixture-with-selection (revu-fixture-hunk-section "alpha.txt" 0)
          (revu-fixture-hunk-section "alpha.txt" 1)
        (revu-reviewed-toggle))
      (should (equal (point)
                     (oref (revu-reviewed-test--section "beta.txt") start))))))

(ert-deftest revu-reviewed-toggle-advances-past-a-run-with-hide-reviewed-on ()
  "With the run gone from the buffer, the move on to the next work survives.
Advancing from where point ended up would leave the reviewer above the
run and re-offer the hunks they just read."
  (revu-fixture-in-repo root
    (revu-fixture-two-hunk-alpha root)
    (with-current-buffer (revu-diff-worktree "worktree")
      (revu-reviewed-toggle-hide-reviewed)
      (unwind-protect
          (progn
            (revu-fixture-with-selection
                (revu-fixture-hunk-section "alpha.txt" 0)
                (revu-fixture-hunk-section "alpha.txt" 1)
              (revu-reviewed-toggle))
            (should-not (string-match-p "alpha" (revu-fixture-render)))
            (should (equal (point)
                           (oref (revu-reviewed-test--section "beta.txt")
                                 start))))
        (setq revu-reviewed-hide-reviewed nil)))))

(ert-deftest revu-reviewed-toggle-leaves-a-fold-outside-the-selection-alone ()
  "A hunk the reviewer folded by hand, outside the run, keeps its fold."
  (revu-fixture-in-repo root
    (revu-fixture-two-hunk-alpha root)
    (with-current-buffer (revu-diff-worktree "worktree")
      (magit-section-hide (car (revu-fixture-hunk-sections "beta.txt")))
      (revu-fixture-with-selection (revu-fixture-hunk-section "alpha.txt" 0)
          (revu-fixture-hunk-section "alpha.txt" 1)
        (revu-reviewed-toggle))
      (should (revu-fixture-hidden-on-screen-p
               (car (revu-fixture-hunk-sections "beta.txt")))))))

(provide 'revu-reviewed-test)
;;; revu-reviewed-test.el ends here
