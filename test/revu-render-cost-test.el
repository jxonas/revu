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

(defun revu-render-cost-test--render-seconds (files)
  "Render FILES into the current buffer and return the seconds it took.
Nothing is collected between renders: what is being measured is the cost
a render carries from the renders before it, and forcing a collection
would drop part of it."
  (let ((started (current-time)))
    (revu-render-diff files)
    (float-time (time-since started))))

(ert-deftest revu-render-cost-does-not-grow-with-the-renders-before-it ()
  "The twelfth render of a Source costs what the first one did.
A render that had to carry the renders before it would climb here, and
the reviewer would feel it on every annotate and every reload of a large
diff."
  (let ((files (revu-render-cost-test--files))
        (seconds nil))
    (garbage-collect)
    (with-temp-buffer
      (magit-section-mode)
      (dotimes (_ revu-render-cost-test-renders)
        (push (revu-render-cost-test--render-seconds files) seconds)))
    (setq seconds (nreverse seconds))
    (should (< (car (last seconds))
               (* revu-render-cost-test-growth (car seconds))))))

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
