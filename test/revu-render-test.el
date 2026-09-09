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

(ert-deftest revu-worktree-command-opens-a-review-buffer-over-the-worktree-diff ()
  "`revu-diff-worktree' renders the unstaged changes in a review buffer."
  (revu-fixture-in-repo root
    (let ((buffer (revu-diff-worktree nil "worktree")))
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
  (revu-fixture-in-repo root
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
  (revu-fixture-in-repo root
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
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree nil "worktree")
      (should-not (string-match-p "^ *[0-9]+ *$" (revu-fixture-render))))))

(ert-deftest revu-range-command-renders-the-diff-between-two-revisions ()
  "`revu-diff-range' renders what one branch changed against another."
  (revu-fixture-in-repo root
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
The fixture line is edited so the old and new files count differently: with
a line dropped above it, the removed line and the line replacing it carry
different numbers."
  (revu-fixture-in-repo root
    (revu-fixture-write-file
     root "alpha.txt"
     (thread-last revu-fixture-alpha-baseline
                  (replace-regexp-in-string "alpha two\n" "")
                  (replace-regexp-in-string "alpha eight" "alpha eight edited")))
    (let ((revu-line-numbers t))
      (with-current-buffer (revu-diff-worktree nil "worktree")
        (let ((text (revu-fixture-render)))
          ;; "alpha two" is line 2 of the old file and is in no new file.
          (should (string-match-p "^ +2 -alpha two$" text))
          ;; Its replacement is line 7 of the new file; what it replaced was
          ;; line 8 of the old one.
          (should (string-match-p "^ +8 -alpha eight$" text))
          (should (string-match-p "^ +7 \\+alpha eight edited$" text))
          ;; Context is numbered in the new file too.
          (should (string-match-p "^ +8  alpha nine$" text)))))))

(ert-deftest revu-line-numbers-are-off-by-default ()
  "With `revu-line-numbers' nil no line carries a number prefix.
The default is off: the reviewer reads the diff, and asks for the numbers
only when they are going to quote them at an agent (ADR-0011)."
  (revu-fixture-in-repo root
    (should-not revu-line-numbers)
    (with-current-buffer (revu-diff-worktree nil "worktree")
      (let ((text (revu-fixture-render)))
        (should (string-match-p "^\\+alpha seven in the worktree$" text))
        (should (string-match-p "^-alpha seven$" text))
        (should-not (string-match-p "^ *[0-9]+ [-+ ]" text))))))

(ert-deftest revu-line-numbers-off-still-name-what-point-is-on ()
  "A line with no visible number still carries its Target.
The number lives in the `revu-target' property, so what a command reads
off the line does not depend on the prefix being drawn."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree nil "worktree")
      (revu-fixture-goto-line-matching "^\\+alpha seven in the worktree$")
      (let ((target (get-text-property (line-beginning-position) 'revu-target)))
        (should (equal target (list "alpha.txt" 7 "added")))))
    (let ((revu-line-numbers t))
      (with-current-buffer (revu-diff-worktree nil "numbered")
        (revu-fixture-goto-line-matching "\\+alpha seven in the worktree$")
        (should (equal (get-text-property (line-beginning-position) 'revu-target)
                       (list "alpha.txt" 7 "added")))))))

(ert-deftest revu-render-nests-hunk-sections-under-their-file ()
  "Every hunk section sits under the section of the file it belongs to."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-staged "staged")
      (should (equal (mapcar (lambda (section) (oref section value))
                             (revu-fixture-sections 'revu-file-section))
                     '("beta.txt" "delta-renamed.txt" "gamma.txt")))
      (dolist (hunk (revu-fixture-sections 'revu-hunk-section))
        (should (object-of-class-p (oref hunk parent) 'revu-file-section))
        (should (equal (car (oref hunk value))
                       (oref (oref hunk parent) value)))))))

(ert-deftest revu-tab-folds-a-file-and-a-hunk ()
  "TAB on a file or a hunk hides what is under it, and shows it again."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree nil "worktree")
      (let* ((file (car (revu-fixture-sections 'revu-file-section)))
             (hunk (car (revu-fixture-sections 'revu-hunk-section)))
             (first-line (save-excursion
                           (goto-char (oref hunk content))
                           (point))))
        (goto-char (oref hunk start))
        (revu-fixture-press-tab)
        (should (invisible-p first-line))
        (should-not (invisible-p (oref hunk start)))
        (revu-fixture-press-tab)
        (should-not (invisible-p first-line))
        (goto-char (oref file start))
        (revu-fixture-press-tab)
        (should (invisible-p (oref hunk start)))
        (revu-fixture-press-tab)
        (should-not (invisible-p (oref hunk start)))))))

(ert-deftest revu-render-keeps-a-fold-the-reviewer-set-across-a-reload ()
  "A section the reviewer folded is still folded on screen after a reload.
Visibility survives a render because the render applies it: magit-section
resolves the visibility of every section it builds, but only an invisible
overlay hides anything, and the slot alone leaves the buffer expanded
\(ADR-0008)."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree nil "worktree")
      (let ((file (car (revu-fixture-sections 'revu-file-section))))
        (magit-section-hide file)
        (should (revu-fixture-hidden-on-screen-p file))
        ;; The fold went into magit's visibility cache, which is what a
        ;; render reads it back from: without an entry there this test
        ;; would pass over a bug it cannot see.
        (should magit-section-visibility-cache))
      (revu-reload)
      (should (revu-fixture-hidden-on-screen-p
               (car (revu-fixture-sections 'revu-file-section)))))))

(ert-deftest revu-render-keeps-a-global-collapse-across-a-reload ()
  "Collapsing the whole buffer survives a reload, on screen and not just in the slot.
`magit-section-cycle-global' is how a reviewer collapses everything at
once, and it takes a different route to the same visibility than folding
one section does."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree nil "worktree")
      (magit-section-cycle-global)
      ;; A rename that changed nothing has no body to hide, and nothing to
      ;; say about whether a fold held.
      (cl-flet ((folded-files ()
                  (seq-filter (lambda (file)
                                (and (oref file content)
                                     (< (oref file content) (oref file end))))
                              (revu-fixture-sections 'revu-file-section))))
        (should (folded-files))
        (dolist (file (folded-files))
          (should (revu-fixture-hidden-on-screen-p file)))
        (revu-reload)
        (dolist (file (folded-files))
          (should (revu-fixture-hidden-on-screen-p file)))))))

(ert-deftest revu-render-keeps-a-hunk-fold-across-an-edit-to-its-file ()
  "A hunk the reviewer folded is still folded once its file changes under it.
Reload exists to show what changed, and a hunk's header text changes with
it, so a fold keyed on that text is lost on exactly the render the
reviewer asked for.  A hunk's fold is keyed on its position among its
file's hunks instead (ADR-0012)."
  (revu-fixture-in-repo root
    (revu-fixture-two-hunk-alpha root)
    (with-current-buffer (revu-diff-worktree nil "worktree")
      (let ((headers nil))
        (dolist (hunk (revu-fixture-hunk-sections "alpha.txt"))
          (push (cdr (oref hunk value)) headers)
          (magit-section-hide hunk))
        (should (equal (length headers) 2))
        (revu-fixture-two-hunk-alpha root "alpha one and a half")
        (revu-reload)
        (let ((hunks (revu-fixture-hunk-sections "alpha.txt")))
          (should (equal (length hunks) 2))
          ;; Without a changed header there is no bug here to see.
          (should-not (equal (mapcar (lambda (h) (cdr (oref h value))) hunks)
                             (nreverse headers)))
          (dolist (hunk hunks)
            (should (revu-fixture-hidden-on-screen-p hunk))))))))

(ert-deftest revu-render-keeps-a-fold-when-magit-caches-no-visibility ()
  "A fold survives a reload with `magit-section-cache-visibility' globally nil.
That option decides whether a fold is ever written to magit's cache, and
the fold invariant (ADR-0012) is read back out of it.  A reviewer who
turned it off for magit would lose every fold in a review buffer, so
`revu-mode' binds it buffer-locally."
  (revu-fixture-in-repo root
    (let ((magit-section-cache-visibility nil))
      (with-current-buffer (revu-diff-worktree nil "worktree")
        (revu-fixture-fold-outlives (revu-reload))))))

(ert-deftest revu-render-keeps-a-fold-when-magit-caches-other-section-types ()
  "A fold survives a reload when the cache option names types that are not revu's.
`magit-section-cache-visibility' takes a list of section types as well as
a boolean, so a value naming magit's own types excludes revu's without
the reviewer ever intending to."
  (revu-fixture-in-repo root
    (let ((magit-section-cache-visibility '(file hunk)))
      (with-current-buffer (revu-diff-worktree nil "worktree")
        (revu-fixture-fold-outlives (revu-reload))))))

(ert-deftest revu-render-keeps-a-fold-when-magit-preserves-no-visibility ()
  "A fold survives with `magit-section-preserve-visibility' globally nil.
The cache can be perfectly populated and still never consulted: that
option gates the read.  Defending the write alone would leave the
invariant just as broken.

The filter is what asks the question here.  A render that rebuilds the
same tree reads a fold back off the previous tree without the cache, but
a section the filter dropped is in no previous tree: coming back folded
is the cache and nothing else."
  (revu-fixture-in-repo root
    (let ((magit-section-preserve-visibility nil))
      (with-current-buffer (revu-diff-worktree nil "worktree")
        (revu-fixture-fold-outlives
         (revu-reviewed-toggle-annotated-only)
         (should-not (revu-fixture-sections 'revu-file-section))
         (revu-reviewed-toggle-annotated-only))))))

(ert-deftest revu-render-leaves-the-visibility-options-alone-outside-the-review ()
  "Opening a review changes neither visibility option outside its own buffer.
revu inherits the reviewer's magit-section configuration; the two
bindings that defend the fold invariant are buffer-local exceptions, not
a global assignment."
  (revu-fixture-in-repo root
    (let ((magit-section-cache-visibility nil)
          (magit-section-preserve-visibility nil))
      (with-current-buffer (revu-diff-worktree nil "worktree")
        (should (eq magit-section-cache-visibility t))
        (should (eq magit-section-preserve-visibility t)))
      (should-not magit-section-cache-visibility)
      (should-not magit-section-preserve-visibility)
      (should-not (default-value 'magit-section-cache-visibility))
      (should-not (default-value 'magit-section-preserve-visibility)))))

(ert-deftest revu-render-keeps-a-hunk-fold-when-a-filter-drops-the-hunk-above-it ()
  "A view filter dropping a hunk leaves the fold of the hunk below it alone.
A hunk is placed among the hunks its file was parsed with, not among the
ones a render kept: an index over what was rendered would hand a hunk the
fold of the hunk above it as soon as a filter dropped one."
  (revu-fixture-in-repo root
    (revu-fixture-two-hunk-alpha root)
    (with-current-buffer (revu-diff-worktree nil "worktree")
      (magit-section-hide (nth 1 (revu-fixture-hunk-sections "alpha.txt")))
      (revu-reviewed-toggle-hide-reviewed)
      (revu-fixture-goto-line-matching "^\\+alpha one changed$")
      ;; Marking the first hunk read drops it from the render.
      (revu-reviewed-toggle)
      (let ((hunks (revu-fixture-hunk-sections "alpha.txt")))
        (should (equal (length hunks) 1))
        (should (revu-fixture-hidden-on-screen-p (car hunks)))))))

(ert-deftest revu-re-rendering-unchanged-state-changes-nothing ()
  "Reviewing the same Source again renders the same buffer, point and all.
The buffer is a render of state: with the state unchanged there is
nothing for a second render to say differently."
  (revu-fixture-in-repo root
    (let ((buffer (revu-diff-worktree nil "worktree"))
          (before nil)
          (section nil))
      (with-current-buffer buffer
        (goto-char (oref (car (revu-fixture-sections 'revu-hunk-section))
                         start))
        (setq before (buffer-substring (point-min) (point-max))
              section (oref (magit-current-section) value)))
      (should (eq (revu-diff-worktree nil "worktree") buffer))
      (with-current-buffer buffer
        (should (equal (buffer-substring (point-min) (point-max)) before))
        (should (equal (oref (magit-current-section) value) section))
        (should (= (point) (oref (magit-current-section) start)))))))

(ert-deftest revu-buffer-command-records-a-pasted-diff-whole ()
  "`revu-diff-buffer' reviews a unified diff already in a buffer.
The diff is a Source of its own: the record is the text itself, and the
Review is named for its digest (ADR-0005's amendment)."
  (revu-fixture-in-repo root
    (let ((text (revu-fixture-git-output root "diff" "main..feature")))
      (with-temp-buffer
        (insert text)
        (revu-diff-buffer (current-buffer) "pasted"))
      (with-current-buffer "*revu: pasted*"
        (should (string-match-p "\\+alpha three on feature"
                                (revu-fixture-render))))
      (let ((source (revu-review-source (revu-fixture-sidecar root "pasted"))))
        (should (equal (revu-source-kind source) "patch"))
        (should (equal (revu-source-text source) text))))))

(ert-deftest revu-buffer-command-reviews-a-diff-with-no-index-headers ()
  "A diff from a mail carries no `index' header, and is reviewed anyway.
What those headers name is this repository's business, and a diff taken
elsewhere has none of it here."
  (revu-fixture-in-repo root
    (with-temp-buffer
      (insert "diff --git a/alpha.txt b/alpha.txt\n"
              "--- a/alpha.txt\n+++ b/alpha.txt\n"
              "@@ -1,1 +1,1 @@\n-alpha one\n+alpha uno\n")
      (revu-diff-buffer (current-buffer) "pasted"))
    (with-current-buffer "*revu: pasted*"
      (should (string-match-p "\\+alpha uno" (revu-fixture-render))))
    (should (revu-fixture-sidecar root "pasted"))))

(ert-deftest revu-buffer-command-reviews-a-diff-taken-on-another-machine ()
  "A diff naming objects and files this repository lacks is reviewed as it is.
Nothing about a patch is looked up: it is read back from its own record."
  (revu-fixture-in-repo root
    (with-temp-buffer
      (insert "diff --git a/elsewhere.txt b/elsewhere.txt\n"
              "index 1111111111111111111111111111111111111111.."
              "2222222222222222222222222222222222222222 100644\n"
              "--- a/elsewhere.txt\n+++ b/elsewhere.txt\n"
              "@@ -1,1 +1,1 @@\n-old\n+new\n")
      (revu-diff-buffer (current-buffer) "pasted"))
    (with-current-buffer "*revu: pasted*"
      (should (string-match-p "elsewhere.txt" (revu-fixture-render)))
      (should (string-match-p "\\+new" (revu-fixture-render))))))

(ert-deftest revu-buffer-command-refuses-a-buffer-holding-no-diff ()
  "A buffer with no file diff in it is refused and leaves no Sidecar.
An empty review buffer cannot say whether revu failed or whether there
was nothing there, which is why an empty Source is refused too."
  (revu-fixture-in-repo root
    (dolist (text '("" "Looks good to me, ship it.\n"))
      (with-temp-buffer
        (insert text)
        (should-error (revu-diff-buffer (current-buffer) "pasted")
                      :type 'user-error))
      (should-not (revu-fixture-sidecar root "pasted")))))

(ert-deftest revu-buffer-command-resumes-the-same-review-for-the-same-text ()
  "The name is the text's digest, so the same paste is the same Review.
A different text is a different diff and opens a Review of its own."
  (revu-fixture-in-repo root
    (let* ((text (revu-fixture-git-output root "diff" "main..feature"))
           (other (concat text "\n"))
           (name (lambda (pasted)
                   (with-temp-buffer
                     (insert pasted)
                     (with-current-buffer (revu-diff-buffer (current-buffer))
                       (revu-review-name (revu-review)))))))
      (should (equal (funcall name text) (funcall name text)))
      (should (string-prefix-p "patch-" (funcall name text)))
      (should-not (equal (funcall name text) (funcall name other))))))

(defconst revu-render-test--two-file-patch
  "diff --git a/elsewhere/one.txt b/elsewhere/one.txt
--- a/elsewhere/one.txt
+++ b/elsewhere/one.txt
@@ -1,3 +1,3 @@
 one first
-one second
+one second changed
 one third
diff --git a/elsewhere/two.txt b/elsewhere/two.txt
--- a/elsewhere/two.txt
+++ b/elsewhere/two.txt
@@ -1,3 +1,3 @@
 two first
-two second
+two second changed
 two third
"
  "A two-file diff over paths this repository has never held.")

(ert-deftest revu-patch-review-reopens-over-every-file-it-recorded ()
  "A patch is read back whole: every file, its Annotations and its marks.
The recorded text is the Source, so a reload and a reopen render what was
pasted rather than whatever this repository can be asked for."
  (revu-fixture-in-repo root
    (with-temp-buffer
      (insert revu-render-test--two-file-patch)
      (revu-diff-buffer (current-buffer) "pasted"))
    (with-current-buffer "*revu: pasted*"
      (revu-fixture-goto-line-matching "^\\+two second changed$")
      (revu-annotate-line "note" "On the second file")
      (revu-reviewed-toggle)
      (revu-reload)
      (let ((render (revu-fixture-render)))
        (should (string-match-p "elsewhere/one.txt" render))
        (should (string-match-p "\\+one second changed" render))
        (should (string-match-p "\\+two second changed" render))
        (should (string-match-p "On the second file" render))))
    (kill-buffer "*revu: pasted*")
    (revu-open "pasted")
    (with-current-buffer "*revu: pasted*"
      (let ((render (revu-fixture-render)))
        (should (string-match-p "elsewhere/one.txt" render))
        (should (string-match-p "elsewhere/two.txt" render))
        (should (string-match-p "On the second file" render)))
      ;; The mark still holds: it was taken over the hunk of a Source that
      ;; cannot change.
      (should (eq (revu-reviewed-state (revu-review) revu--files
                                       "elsewhere/two.txt")
                  'reviewed)))))

(ert-deftest revu-worktree-command-shows-staged-changes-too ()
  "The worktree Review is everything HEAD does not have, staged or not.
That is what the reviewer reading before a commit is asking for, and it
is what makes the Revision the Review records the one the diff was taken
against -- which is what re-locates a removed line later (ADR-0003)."
  (revu-fixture-in-repo root
    (revu-diff-worktree nil "worktree")
    (let ((rendered (with-current-buffer "*revu: worktree*"
                      (revu-fixture-render))))
      ;; The fixture stages one change and leaves another unstaged.
      (should (string-match-p "beta\\.txt" rendered))
      (should (string-match-p "alpha\\.txt" rendered)))
    (let ((source (revu-review-source (revu-fixture-sidecar root "worktree"))))
      (should (equal (revu-source-base source)
                     (revu-fixture-git-output root "rev-parse" "HEAD"))))))

(ert-deftest revu-worktree-command-takes-a-base-revision ()
  "The worktree may be reviewed against any Revision, not only HEAD.
The diff is the one `git diff <revision>' takes -- everything the
worktree carries that the Revision does not -- and the Source records the
commit the Revision resolved to, so the Review can be read again."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree "feature")
      (should (equal (buffer-name) "*revu: worktree-vs-feature*"))
      (let ((text (revu-fixture-render)))
        ;; The branch's own change is not in the worktree, so it reads
        ;; as removed; the worktree's own change is still added.
        (should (string-match-p "-alpha three on feature" text))
        (should (string-match-p "\\+alpha seven in the worktree" text))))
    (let ((source (revu-review-source
                   (revu-fixture-sidecar root "worktree-vs-feature"))))
      (should (equal (revu-source-kind source) "worktree"))
      (should (equal (revu-source-base source)
                     (revu-fixture-git-output root "rev-parse" "feature"))))))

(ert-deftest revu-worktree-command-keeps-the-head-review-out-of-it ()
  "The worktree against HEAD and against a Revision are two Reviews.
The HEAD Review must not fork as HEAD moves, and a Review taken against
something else must not resume it under the wrong Annotations."
  (revu-fixture-in-repo root
    (revu-diff-worktree)
    (revu-diff-worktree "feature")
    (should (revu-fixture-sidecar root "worktree"))
    (should (revu-fixture-sidecar root "worktree-vs-feature"))
    ;; The Review of the worktree against HEAD is called `worktree'
    ;; whatever commit HEAD is on.
    (should (equal (revu-review-name (revu-fixture-sidecar root "worktree"))
                   "worktree"))
    (should (equal (revu-source-base
                    (revu-review-source (revu-fixture-sidecar root "worktree")))
                   (revu-fixture-git-output root "rev-parse" "HEAD")))))

(ert-deftest revu-worktree-command-reads-a-base-naming-head-as-head ()
  "A base that names the commit HEAD names is the worktree Review of HEAD.
The branch that is checked out is HEAD, and reviewing the worktree
against it by name is the same Source: it opens the one Review of what
is about to be committed rather than a second one beside it."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree "main")
      (should (equal (buffer-name) "*revu: worktree*")))
    (should-not (revu-fixture-sidecar root "worktree-vs-main"))))

(ert-deftest revu-worktree-command-refuses-a-revision-naming-nothing ()
  "A base that names no commit is refused, not guessed at."
  (revu-fixture-in-repo root
    (let ((message (cadr (should-error (revu-diff-worktree "no-such-thing")
                                       :type 'user-error))))
      (should (string-match-p "no-such-thing" message)))
    (should-not (revu-fixture-sidecar root "worktree-vs-no-such-thing"))))

(ert-deftest revu-since-command-opens-the-worktree-against-the-revision-it-reads ()
  "`revu-diff-since' prompts for a Revision and opens the worktree against it.
Completion offers the local branches and tags, and requires no match, so
any Revision git reads can be written instead."
  (revu-fixture-in-repo root
    (let (collection require-match)
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (_prompt table &optional _predicate match &rest _)
                   (setq collection table require-match match)
                   "feature")))
        (call-interactively #'revu-diff-since))
      (should (member "feature" collection))
      (should (member "main" collection))
      (should-not require-match))
    (with-current-buffer "*revu: worktree-vs-feature*"
      (let ((text (revu-fixture-render)))
        (should (string-match-p "-alpha three on feature" text))
        (should (string-match-p "\\+alpha seven in the worktree" text))))
    (should (equal (revu-source-base
                    (revu-review-source
                     (revu-fixture-sidecar root "worktree-vs-feature")))
                   (revu-fixture-git-output root "rev-parse" "feature")))))

(ert-deftest revu-since-command-completes-over-branches-and-tags-only ()
  "Tags are offered beside the local branches; remote branches are not.
A tag is what \"everything since the release\" is usually written as, and
the refs a fetch dragged in would bury the handful being worked on."
  (revu-fixture-in-repo root
    (revu-fixture-git-output root "tag" "v1" "feature")
    (revu-fixture-git-output root "update-ref" "refs/remotes/origin/main" "HEAD")
    (let (collection)
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (_prompt table &rest _) (setq collection table) "v1")))
        (call-interactively #'revu-diff-since))
      (should (member "v1" collection))
      (should (member "feature" collection))
      (should-not (member "origin/main" collection)))
    (should (get-buffer "*revu: worktree-vs-v1*"))))

(ert-deftest revu-since-command-takes-a-revision-nothing-names ()
  "Free text reaches git: a Revision no branch or tag names still opens.
The Review is named for it as it was typed, exactly as a named ref is."
  (revu-fixture-in-repo root
    (let ((written (revu-fixture-git-output root "rev-parse" "--short" "feature")))
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (&rest _) written)))
        (call-interactively #'revu-diff-since))
      (should (get-buffer (format "*revu: worktree-vs-%s*" written)))
      (should (equal (revu-source-base
                      (revu-review-source
                       (revu-fixture-sidecar root (format "worktree-vs-%s" written))))
                     (revu-fixture-git-output root "rev-parse" "feature"))))))

(ert-deftest revu-since-command-asks-for-a-name-under-a-prefix-argument ()
  "A prefix argument asks for a name of the Review's own, as the others do."
  (revu-fixture-in-repo root
    (let (offered)
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (&rest _) "feature"))
                ((symbol-function 'read-string)
                 (lambda (_prompt &optional _initial _history default)
                   (setq offered default)
                   "named-by-hand")))
        (let ((current-prefix-arg '(4)))
          (call-interactively #'revu-diff-since)))
      (should (equal offered "worktree-vs-feature"))
      (should (get-buffer "*revu: named-by-hand*")))))

(ert-deftest revu-since-command-reads-a-revision-naming-head-as-the-worktree ()
  "A Revision naming the commit HEAD names opens the everyday worktree Review."
  (revu-fixture-in-repo root
    (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) "main")))
      (call-interactively #'revu-diff-since))
    (should (get-buffer "*revu: worktree*"))
    (should-not (revu-fixture-sidecar root "worktree-vs-main"))))

(ert-deftest revu-since-command-refuses-a-revision-naming-nothing ()
  "A Revision naming no commit is refused, in the words every entry command uses.
The refusal is compared against another entry command's, not against the
one this command delegates to: what the criterion asks is that a
reviewer reads the same sentence wherever they wrote the Revision."
  (revu-fixture-in-repo root
    (let ((refusal (cl-letf (((symbol-function 'completing-read)
                              (lambda (&rest _) "no-such-thing")))
                     (cadr (should-error (call-interactively #'revu-diff-since)
                                         :type 'user-error)))))
      (should (equal refusal
                     (cadr (should-error (revu-diff-range "no-such-thing" "HEAD")
                                         :type 'user-error)))))
    (should-not (revu-fixture-sidecar root "worktree-vs-no-such-thing"))))

(ert-deftest revu-since-command-refuses-a-revision-that-is-nothing-at-all ()
  "No Revision at all is refused rather than read as HEAD.
`revu-diff-worktree' takes a base of nothing as HEAD, and a caller from
Lisp that named no Revision must not land in the everyday `worktree'
Review by that route: it asked for the worktree since something."
  (revu-fixture-in-repo root
    (should-error (revu-diff-since nil) :type 'user-error)
    (should-error (revu-diff-since "") :type 'user-error)
    (should-not (get-buffer "*revu: worktree*"))
    (should-not (revu-fixture-sidecar root "worktree"))))

(ert-deftest revu-since-command-resumes-the-review-pinned-to-the-base-it-recorded ()
  "Asking again for the same Revision resumes the Review over the commit it holds.
Commits landing on top move the branch, not the Review: `g' shows them,
and the edits still uncommitted, as changes against the original base."
  (revu-fixture-in-repo root
    ;; `qa' names a commit HEAD moves past, so the worktree carries
    ;; something over it and the Review is the worktree-vs one.
    (revu-fixture-git-output root "branch" "qa")
    (revu-fixture-git-output root "commit" "-q" "-a" "-m" "Land the worktree")
    (let ((recorded (revu-fixture-git-output root "rev-parse" "qa")))
      (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) "qa")))
        (save-current-buffer (call-interactively #'revu-diff-since))
        (revu-fixture-kill-review-buffers)
        ;; An agent commits on top twice over, and `qa' follows one of
        ;; them: the Revision has moved, and it is still not HEAD.
        (revu-fixture-write-file root "beta.txt"
                                 "beta one\nbeta two landed\nbeta three\n")
        (revu-fixture-git-output root "commit" "-q" "-a" "-m" "Land beta")
        (revu-fixture-write-file root "README.md" "# Fixture\n\nEdited after.\n")
        (revu-fixture-git-output root "commit" "-q" "-a" "-m" "Edit the README")
        (revu-fixture-git-output root "branch" "-f" "qa" "HEAD~")
        (with-current-buffer (call-interactively #'revu-diff-since)
          (should (equal (buffer-name) "*revu: worktree-vs-qa*"))
          (revu-fixture-write-file
           root "alpha.txt"
           (replace-regexp-in-string "alpha one" "alpha one changed"
                                     revu-fixture-alpha-baseline t t))
          (revu-reload)
          (let ((text (revu-fixture-render)))
            ;; The commit that landed on top, and the edit made since.
            (should (string-match-p "\\+beta two landed" text))
            (should (string-match-p "\\+alpha one changed" text)))))
      (should (equal (revu-source-base
                      (revu-review-source
                       (revu-fixture-sidecar root "worktree-vs-qa")))
                     recorded)))))

(ert-deftest revu-entry-commands-open-on-the-derived-name-without-a-prompt ()
  "An entry command asked for no name opens on the derived one, silently."
  (revu-fixture-in-repo root
    (cl-letf (((symbol-function 'read-string)
               (lambda (&rest _) (error "An entry command must not prompt"))))
      (call-interactively #'revu-diff-worktree))
    (should (get-buffer "*revu: worktree*"))))

(ert-deftest revu-entry-commands-ask-for-a-name-under-a-prefix-argument ()
  "A prefix argument asks for the name, with the derived one offered."
  (revu-fixture-in-repo root
    (let (prompt offered)
      (cl-letf (((symbol-function 'read-string)
                 (lambda (message &optional _initial _history default)
                   (setq prompt message offered default)
                   "named-by-hand")))
        (let ((current-prefix-arg '(4)))
          (call-interactively #'revu-diff-worktree)))
      (should (string-match-p "worktree" prompt))
      ;; The derived name is the default, so a reviewer who asked for the
      ;; prompt and then changed their mind lands back in the scratch
      ;; bucket rather than beside it.
      (should (equal offered "worktree"))
      (should (get-buffer "*revu: named-by-hand*")))))

(ert-deftest revu-entry-commands-do-not-inherit-a-callers-prefix-argument ()
  "A prefix argument meant for another command never reaches an entry command.
The magit Bridge calls these from inside magit's own commands, where a
prefix argument means whatever magit read it as."
  (revu-fixture-in-repo root
    (cl-letf (((symbol-function 'read-string)
               (lambda (&rest _) (error "A caller's prefix argument leaked"))))
      (let ((current-prefix-arg '(4)))
        (revu-diff-worktree)))
    (should (get-buffer "*revu: worktree*"))))

(ert-deftest revu-entry-command-resumes-the-review-already-there ()
  "Reviewing a Source again picks its Review up; it never clobbers it."
  (revu-fixture-in-repo root
    (let ((review (revu-review-add-annotation
                   (revu-review-create "worktree" (revu-source-worktree "HEAD"))
                   (revu-annotation-create "note"
                                           (revu-target-file "alpha.txt")
                                           "written yesterday"))))
      (make-directory (expand-file-name ".revu/reviews" root) t)
      (with-temp-file (expand-file-name ".revu/reviews/worktree.json" root)
        (insert (revu-review-encode review))))
    (revu-diff-worktree nil "worktree")
    (let ((annotations (revu-review-annotations
                        (revu-fixture-sidecar root "worktree"))))
      (should (equal (seq-length annotations) 1))
      (should (equal (revu-annotation-body (seq-elt annotations 0))
                     "written yesterday")))))

(ert-deftest revu-render-leaves-point-on-the-line-the-reviewer-was-on ()
  "A render puts point back on the reviewer's line, column and all.
The line is named by the `revu-target' it carries, not by where it sat:
the Annotation this render adds is inserted under that very line, so a
buffer line number would already be wrong for the lines below it."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree nil "worktree")
      (revu-fixture-goto-line-matching revu-fixture-worktree-seven)
      (move-to-column 12)
      (revu-annotate-line "question" "Why this line?")
      (should (string-match-p revu-fixture-worktree-seven
                              (buffer-substring-no-properties
                               (line-beginning-position)
                               (line-end-position))))
      (should (equal (current-column) 12)))))

(ert-deftest revu-render-falls-back-to-the-section-when-the-line-is-gone ()
  "A line the Source no longer carries leaves point on its hunk's heading.
The target is gone, so the section it was under is the strongest thing
left; the reviewer lands where their line used to be rather than at the
top of the buffer."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree nil "worktree")
      (revu-fixture-goto-line-matching revu-fixture-worktree-seven)
      ;; The worktree changes elsewhere, so line seven is not in the diff.
      (revu-fixture-write-file
       root "alpha.txt"
       (replace-regexp-in-string "alpha one" "alpha one changed"
                                 revu-fixture-alpha-baseline t t))
      (revu-reload)
      (let ((section (magit-current-section)))
        (should (object-of-class-p section 'revu-hunk-section))
        (should (equal (car (oref section value)) "alpha.txt"))
        (should (equal (point) (oref section start)))))))

(ert-deftest revu-render-puts-the-line-back-at-the-height-it-was-at ()
  "A restored line comes back at the screen row it was on, so the view holds."
  (revu-fixture-in-repo root
    (let ((buffer (revu-diff-worktree nil "worktree")))
      (set-window-buffer (selected-window) buffer)
      (with-current-buffer buffer
        (revu-fixture-goto-line-matching revu-fixture-worktree-seven)
        (recenter 3)
        (revu-annotate-line "question" "Why this line?")
        (should (equal (count-screen-lines (window-start)
                                           (line-beginning-position)
                                           nil (selected-window))
                       3))))))

(ert-deftest revu-render-heading-position-answers-with-the-fold-over-it ()
  "A heading under a fold hands the question to the heading of the fold.
Point in invisible text is pushed out of it at the end of the command,
past everything the fold covers, which is the jump a reviewer sees as a
whole file skipped.  The fold itself is left exactly as it was: it is the
reviewer's own."
  (revu-fixture-in-repo root
    (revu-fixture-two-hunk-alpha root)
    (with-current-buffer (revu-diff-worktree nil "worktree")
      (let ((file (car (revu-fixture-sections 'revu-file-section)))
            (hunk (revu-fixture-hunk-section "alpha.txt" 1)))
        (should (equal (revu-render-heading-position (oref hunk value))
                       (oref hunk start)))
        (magit-section-hide file)
        (should (equal (revu-render-heading-position (oref hunk value))
                       (oref file start)))
        (should (revu-fixture-hidden-on-screen-p file)))
      ;; A value nothing rendered carries has no heading to go to.
      (should-not (revu-render-heading-position '("nowhere.txt" . "@@"))))))

(ert-deftest revu-render-leaves-point-on-a-heading-when-a-mark-folds-the-line ()
  "A render leaves point on the heading of the fold over the line it was on.
The line point was on is still rendered, but a Reviewed mark has folded
the hunk over it: putting point back on it would put the reviewer in text
they cannot see.

Marking moves the reviewer on to the next section, so the test puts them
back on the folded line first -- that is the position this render has to
decide about."
  (revu-fixture-in-repo root
    (revu-fixture-two-hunk-alpha root)
    (with-current-buffer (revu-diff-worktree nil "worktree")
      (revu-fixture-goto-line-matching "^\\+alpha one changed$")
      (revu-reviewed-toggle)
      (revu-fixture-goto-line-matching "^\\+alpha one changed$")
      (revu-render)
      (should-not (invisible-p (point)))
      (let ((section (magit-current-section)))
        (should (object-of-class-p section 'revu-hunk-section))
        (should (equal (point) (oref section start)))))))

(ert-deftest revu-render-leaves-point-on-a-removed-line ()
  "A removed line holds point like any other, under the path it is named by.
A removed line is named under the path the file had before the diff
renamed it, so its Target is not the one the lines around it carry."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree nil "worktree")
      (revu-fixture-goto-line-matching "^-alpha seven$")
      (revu-annotate-line "note" "This is what it said before.")
      (should (string-match-p "^-alpha seven$"
                              (buffer-substring-no-properties
                               (line-beginning-position)
                               (line-end-position)))))))

(ert-deftest revu-render-highlight-leaves-a-hunk-line-its-own-face ()
  "Point in a hunk covers its heading only, so the lines keep their Origin."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree nil "worktree")
      (revu-fixture-put-point-on-and-highlight
       revu-fixture-worktree-seven)
      (should (eq (revu-fixture-face-on-screen "\\+alpha seven in the worktree")
                  'diff-added))
      (should (eq (revu-fixture-face-on-screen "-alpha seven$")
                  'diff-removed)))))

(ert-deftest revu-render-highlight-covers-the-heading-of-the-current-hunk ()
  "The affordance survives: the heading of the section under point is lit.
Point is on a body line, where a reviewer reading a hunk holds it."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree nil "worktree")
      (revu-fixture-put-point-on-and-highlight
       revu-fixture-worktree-seven)
      (should (eq (revu-fixture-face-on-screen "^@@")
                  'magit-section-highlight)))))

(ert-deftest revu-render-highlight-leaves-a-file-s-lines-their-own-face ()
  "Point on a file heading covers that heading only, not the hunks under it."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree nil "worktree")
      (revu-fixture-put-point-on-and-highlight "^modified +alpha\\.txt$")
      (should (eq (revu-fixture-face-on-screen "^modified +alpha\\.txt$")
                  'magit-section-highlight))
      (should (eq (revu-fixture-face-on-screen "\\+alpha seven in the worktree")
                  'diff-added))
      (should (eq (revu-fixture-face-on-screen "^@@")
                  'revu-hunk-heading)))))

(ert-deftest revu-render-highlight-leaves-a-plain-file-s-lines-their-face ()
  "A plain file has no hunk section, so the file section is what covers it."
  (revu-fixture-in-repo root
    (revu-file (expand-file-name "README.md" root) "plain")
    (with-current-buffer (revu-buffer-name "plain")
      ;; A plain file's lines are the file section's own body, so point on
      ;; one of them makes the file section current (ADR-0011).
      (revu-fixture-put-point-on-and-highlight "^# Fixture$")
      (should (eq (revu-fixture-face-on-screen "^README\\.md$")
                  'magit-section-highlight))
      (should (eq (revu-fixture-face-on-screen "# Fixture")
                  'diff-context)))))

(provide 'revu-render-test)
;;; revu-render-test.el ends here
