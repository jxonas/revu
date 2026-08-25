;;; revu-render-cost-test.el --- What a render costs, render after render  -*- lexical-binding: t; -*-

;;; Commentary:

;; Every change to a Review is a full re-render (ADR-0008), so the cost of
;; a render is paid on every annotate, every toggle and every reload.  It
;; has to stay the same cost each time.  It did not: a section held its
;; positions as markers into the review buffer, `erase-buffer' left them
;; where they were, and every render's insertions then had to adjust the
;; markers of every render before it.
;;
;; These tests hold that shut from both sides -- what the sections carry,
;; and what a dozen renders in one buffer cost.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'magit-section)
(require 'revu)
(require 'revu-fixture)

;; The Source is shaped for what the tax is charged on rather than for
;; size: a render pays it once per position a section left behind, per
;; insertion the next render makes, so many small sections show it far
;; sooner than the same text under a few large ones.  Five hundred files
;; -- the size the bug was reported against -- of six short hunks is 3501
;; sections in an eighth of a megabyte, and it renders in a fifth of a
;; second.
(defconst revu-render-cost-test-files 500
  "Files in the synthetic Source the timing test renders.")

(defconst revu-render-cost-test-hunks 6
  "Hunks in each file of the synthetic Source.")

(defconst revu-render-cost-test-lines 4
  "Lines in each hunk of the synthetic Source.")

(defconst revu-render-cost-test-renders 12
  "Renders the timing test runs into one buffer.")

(defconst revu-render-cost-test-growth 2.0
  "How much more than the first render the twelfth is allowed to cost.
The bug this guards had the twelfth render cost 3.5 times the first on
the Source below, and 3 to 5 times on the 502-file diff it was reported
against.  With it fixed the twelfth costs 1.4 times the first, and that
is not growth: the step is between the first render and the second, and
renders two to twelve are flat to within a twentieth of each other.  The
first render is the only one building into a buffer nothing has rendered
into before, and it is the cheaper one.  The margin sits between the two
populations, clear of both.")

(defun revu-render-cost-test--hunk (index)
  "Return hunk INDEX of a synthetic file, as a `revu-diff-hunk'."
  (let* ((start (1+ (* index revu-render-cost-test-lines)))
         (lines (cl-loop for offset below revu-render-cost-test-lines
                         for number = (+ start offset)
                         collect (list (if (zerop (% offset 3)) "added" "context")
                                       number
                                       (format " line %d of hunk %d"
                                               number index)))))
    (revu-diff-hunk-create
     :header (format "@@ -%d,%d +%d,%d @@"
                     start revu-render-cost-test-lines
                     start revu-render-cost-test-lines)
     :old-start start :new-start start :lines lines)))

(defun revu-render-cost-test--files ()
  "Return a synthetic Source large enough for a render's cost to be visible.
It is built in memory rather than taken from a git fixture: the seam
under test is `revu-render-diff', which is handed files and renders
them."
  (cl-loop for index below revu-render-cost-test-files
           collect (revu-diff-file-create
                    :path (format "src/file-%03d.el" index)
                    :old-path (format "src/file-%03d.el" index)
                    :status "modified"
                    :hunks (cl-loop for hunk below revu-render-cost-test-hunks
                                    collect (revu-render-cost-test--hunk hunk)))))

(defconst revu-render-cost-test-header-share 0.05
  "The most of a render\='s drawing the header is allowed to cost beside it.
The header is a summary of state the render already walks -- how many
hunks are read, how many Annotations there are -- so it has no business
costing like a second render.  It twice did: asking the Reviewed question
through section values looked each value up again in every file there is,
which on the Source below is a fifth of a second per render once one hunk
is marked, and a third of what drawing the whole buffer costs.  With the
walk over the files themselves it is a four-hundredth of that.  The
margin sits between the two populations, clear of both.

Measured against the render without the header rather than against the
whole, because the whole contains the header: a share of it is bounded
above by one however far the header runs away.")

(defun revu-render-cost-test--seconds (thunk)
  "Call THUNK and return the seconds it took.
Nothing is collected between calls: what is being measured is the cost a
render carries from the renders before it, and forcing a collection would
drop part of it."
  (let ((started (current-time)))
    (funcall thunk)
    (float-time (time-since started))))

(defmacro revu-render-cost-test-in-review (root files &rest body)
  "Run BODY in a review buffer over FILES, in the fixture repository at ROOT.
The buffer is the one `revu-render' renders: the Review, the Sidecar and
the Source are all where that command reads them from, so what a test
times here is the render the reviewer pays for and not a stripped-down
one.  The Source is synthetic and the repository is real, because the
header names a Revision and asks git what it says."
  (declare (indent 2) (debug (symbolp form body)))
  `(revu-fixture-in-repo ,root
     (with-temp-buffer
       (revu-mode)
       (setq default-directory ,root
             revu--files ,files
             revu--sidecar
             (revu-sidecar-open
              (revu-sidecar-file-name "cost" ,root)
              (revu-review-create
               "cost"
               (revu-source-worktree (revu-diff-head-revision ,root)))))
       ,@body)))

(ert-deftest revu-render-cost-does-not-grow-with-the-renders-before-it ()
  "The twelfth render of a Source costs what the first one did.
A render that had to carry the renders before it would climb here, and
the reviewer would feel it on every annotate and every reload of a large
diff."
  (let ((files (revu-render-cost-test--files))
        (seconds nil))
    (garbage-collect)
    (revu-render-cost-test-in-review root files
      (dotimes (_ revu-render-cost-test-renders)
        (push (revu-render-cost-test--seconds #'revu-render) seconds)))
    (setq seconds (nreverse seconds))
    (should (< (car (last seconds))
               (* revu-render-cost-test-growth (car seconds))))))

(ert-deftest revu-render-cost-of-the-header-is-a-fraction-of-the-render ()
  "Deciding the header costs a fraction of drawing the buffer.
A share rather than a time, so the bound says the same thing on a fast
machine and a slow one.  The Reviewed figure is the part that can run
away: it is over the whole Source, and one Reviewed mark is enough to
make it ask the question of every hunk there is."
  (let ((files (revu-render-cost-test--files)))
    (garbage-collect)
    (revu-render-cost-test-in-review root files
      ;; The first render warms what the buffer memoises -- the Revision
      ;; git is asked about once -- so neither figure is paying for it.
      (revu-render)
      ;; One hunk marked, which is what takes the Reviewed figure off the
      ;; path an unmarked Review is answered by counting alone.
      (let* ((hunk (car (revu-diff-file-hunks (car files))))
             (review (revu-review-add-mark
                      (revu-review)
                      (revu-mark-create (revu-diff-file-path (car files))
                                        (revu-reviewed-hunk-digest hunk)
                                        (revu-reviewed-hunk-span hunk))))
             (drawing (revu-render-cost-test--seconds
                       (lambda ()
                         (revu-render-diff
                          files
                          (revu-reviewed-hidden-p review files)
                          nil
                          (revu-reviewed-keep-p review files)
                          (revu-reviewed-state-p review files)))))
             (header (revu-render-cost-test--seconds
                      (lambda () (revu--header review nil)))))
        (should (< header (* revu-render-cost-test-header-share drawing)))))))

(ert-deftest revu-render-gives-a-section-positions-that-cannot-outlive-it ()
  "Every section of a review buffer holds plain positions, not markers.
This is the mechanism the timing test measures, asserted where noise
cannot hide it: a marker stays in the buffer after the render that made
it is gone, and every later insertion pays to move it."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree nil "worktree")
      (let ((sections (revu-fixture-sections)))
        (should sections)
        (dolist (section sections)
          (should (integerp (oref section start)))
          (should (integerp (oref section end)))
          (when (oref section content)
            (should (integerp (oref section content)))))))))

(provide 'revu-render-cost-test)
;;; revu-render-cost-test.el ends here
