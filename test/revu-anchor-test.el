;;; revu-anchor-test.el --- Tests for the revu anchoring engine  -*- lexical-binding: t; -*-

;;; Commentary:

;; Tests the anchoring engine at its pure seam: file content plus an
;; Anchor in, a position and a derived state out.  The content is passed
;; as a string, so every rung of the re-location ladder is exercised
;; without a repository.
;;
;; The tests that need git -- removed lines re-located in a base blob,
;; renamed paths, deleted files -- drive the plumbing in `revu-diff.el'
;; over the fixture repository and feed what git returns to the same
;; pure function.

;;; Code:

(require 'ert)
(require 'revu-anchor)
(require 'revu-diff)
(require 'revu-record)
(require 'revu-fixture)

(defconst revu-anchor-test-content
  "one\ntwo\nthree\nfour\nfive\nsix\nseven\neight\nnine\nten\n"
  "Ten numbered lines: the file every ladder test anchors into.")

(defun revu-anchor-test--anchor (line &optional content)
  "Return the Anchor for LINE of CONTENT, defaulting to the ten-line file."
  (revu-anchor-create (or content revu-anchor-test-content) line))

;;;; The ladder

(ert-deftest revu-anchor-trusts-the-recorded-line-when-the-digest-matches ()
  "Rung one: an unchanged file makes the recorded line number the answer."
  (let ((anchor (revu-anchor-test--anchor 4)))
    (should (equal (revu-anchor-locate revu-anchor-test-content anchor 4)
                   '(4 . fresh)))))

(ert-deftest revu-anchor-finds-the-line-text-when-the-file-changed ()
  "Rung two: an exact line-text match moves the Annotation to where it is now."
  (let ((anchor (revu-anchor-test--anchor 4))
        (content (concat "zero\nhalf\n" revu-anchor-test-content)))
    (should (equal (revu-anchor-locate content anchor 4) '(6 . moved)))))

(ert-deftest revu-anchor-stays-fresh-when-the-line-text-did-not-move ()
  "A file that changed elsewhere leaves the line where it was recorded."
  (let ((anchor (revu-anchor-test--anchor 4))
        (content (concat revu-anchor-test-content "eleven\n")))
    (should (equal (revu-anchor-locate content anchor 4) '(4 . fresh)))))

(ert-deftest revu-anchor-takes-the-line-text-match-nearest-the-recorded-line ()
  "Rung two picks the nearest candidate, not the first in the file."
  (let ((anchor (revu-anchor-test--anchor 4))
        (content "four\none\ntwo\nthree\nfour\nfive\nsix\n"))
    (should (equal (revu-anchor-locate content anchor 4) '(5 . moved)))))

(ert-deftest revu-anchor-finds-the-line-through-changed-whitespace ()
  "Rung three: re-indenting a line does not lose its Annotation."
  (let ((anchor (revu-anchor-test--anchor 4))
        (content "one\ntwo\nthree\n      four  \nfive\nsix\nseven\n"))
    (should (equal (revu-anchor-locate content anchor 4) '(4 . fresh)))))

(ert-deftest revu-anchor-finds-a-rewritten-line-by-its-context ()
  "Rung four: the line itself changed, but its neighbours still name the place."
  (let ((anchor (revu-anchor-test--anchor 4))
        (content
         "one\ntwo\nthree\nfour rewritten\nfive\nsix\nseven\neight\nnine\nten\n"))
    (should (equal (revu-anchor-locate content anchor 4) '(4 . fresh)))))

(ert-deftest revu-anchor-orphans-a-line-that-is-gone ()
  "Nothing on the ladder matches, so the Annotation orphans rather than guess."
  (let ((anchor (revu-anchor-test--anchor 4))
        (content "wholly\ndifferent\nfile\ncontents\nentirely\n"))
    (should (equal (revu-anchor-locate content anchor 4) '(nil . orphaned)))))

(ert-deftest revu-anchor-orphans-a-tie-rather-than-guess ()
  "Two candidates the same distance away are a coin flip, so neither wins."
  (let ((anchor (revu-anchor-test--anchor 4))
        (content "one\nfour\nthree\nxxxx\nfive\nfour\nseven\n"))
    (should (equal (revu-anchor-locate content anchor 4) '(nil . orphaned)))))

(ert-deftest revu-anchor-lets-a-lower-rung-break-a-tie ()
  "A rung that ties names no line, so the ladder goes on to one that can.
ADR-0003 puts the tie that orphans at the context window; a rung above it
that cannot tell two candidates apart has decided nothing, and stopping
there would orphan an Annotation whose context still says where it went."
  (let* ((content "a\nb\nc\ntgt\nd\ne\nf\n")
         (anchor (revu-anchor-create content 4))
         ;; `tgt' now sits the same distance above and below its recorded
         ;; line, so matching the text alone is a coin flip -- but only the
         ;; lower one carries the recorded context, which settles it.
         (moved "z\ntgt\na\nb\nc\ntgt\nd\ne\nf\n"))
    (should (equal (revu-anchor-locate moved anchor 4) '(6 . moved)))))

(ert-deftest revu-anchor-orphans-a-context-window-tie ()
  "A context window that matches twice orphans too: the window is ambiguous."
  (let* ((content "a\nb\nc\ntarget\nd\ne\nf\n")
         (anchor (revu-anchor-create content 4))
         (moved "a\nb\nc\ngone\nd\ne\nf\na\nb\nc\ngone\nd\ne\nf\n"))
    (should (equal (revu-anchor-locate moved anchor 4) '(nil . orphaned)))))

(ert-deftest revu-anchor-does-not-search-past-the-search-radius ()
  "The radius bounds the degraded path: a line moved further away orphans."
  (let* ((anchor (revu-anchor-test--anchor 4))
         (revu-anchor-search-radius 5)
         (content (concat (mapconcat (lambda (n) (format "filler %d" n))
                                     (number-sequence 1 20) "\n")
                          "\n" revu-anchor-test-content)))
    (should (equal (revu-anchor-locate content anchor 4) '(nil . orphaned)))
    (let ((revu-anchor-search-radius 500))
      (should (equal (revu-anchor-locate content anchor 4) '(24 . moved))))))

;;;; Ranges

(ert-deftest revu-anchor-locates-both-endpoints-of-a-range ()
  "A range anchors its endpoints independently and moves as a whole."
  (let* ((anchor (revu-anchor-create-range revu-anchor-test-content 3 5))
         (content (concat "zero\n" revu-anchor-test-content)))
    (should (equal (revu-anchor-locate-range content anchor 3 5)
                   '((4 . 6) . moved)))))

(ert-deftest revu-anchor-orphans-a-range-whose-endpoint-is-gone ()
  "Losing one endpoint orphans the range: half a range is not a range."
  (let* ((anchor (revu-anchor-create-range revu-anchor-test-content 3 5))
         (content "one\ntwo\nthree\nfour\n"))
    (should (equal (revu-anchor-locate-range content anchor 3 5)
                   '(nil . orphaned)))))

;;;; Anchors as records

(ert-deftest revu-anchor-records-the-line-with-three-lines-of-context ()
  "The Anchor carries what an agent needs to re-find the line without Emacs."
  (let ((anchor (revu-anchor-test--anchor 5)))
    (should (equal (revu-anchor-line anchor) "five"))
    (should (equal (revu-anchor-before anchor) ["two" "three" "four"]))
    (should (equal (revu-anchor-after anchor) ["six" "seven" "eight"]))
    (should (equal (revu-anchor-digest anchor)
                   (revu-digest revu-anchor-test-content)))))

(ert-deftest revu-anchor-records-what-context-the-file-edges-leave ()
  "A line at the top of the file has less leading context, not padded context."
  (let ((anchor (revu-anchor-test--anchor 2)))
    (should (equal (revu-anchor-before anchor) ["one"]))))

(ert-deftest revu-anchor-survives-a-round-trip-through-json ()
  "An Anchor decoded from a Sidecar is the Anchor that was written."
  (let ((anchor (revu-anchor-create-range revu-anchor-test-content 3 5)))
    (should (equal (json-parse-string (json-serialize anchor)
                                      :object-type 'alist :array-type 'array)
                   anchor))
    (should (equal (revu-anchor-count anchor) 3))))

;;;; Removed lines

(ert-deftest revu-anchor-re-locates-a-removed-line-in-the-base-blob ()
  "A line the diff removed is gone from the worktree but is in the base blob."
  (revu-fixture-with-repo root
    (let* ((base (revu-diff-show-file root "HEAD" "gamma.txt"))
           (anchor (revu-anchor-create base 1)))
      (should (equal base "gamma one\ngamma two\n"))
      (should (equal (revu-anchor-locate-removed
                      (revu-diff-show-file root "HEAD" "gamma.txt")
                      nil anchor 1)
                     '(1 . fresh))))))

(ert-deftest revu-anchor-reports-no-base-blob-for-a-file-the-revision-lacks ()
  "A path the base Revision does not carry has no blob to search."
  (revu-fixture-with-repo root
    (should-not (revu-diff-show-file root "HEAD" "delta-renamed.txt"))))

(ert-deftest revu-anchor-keeps-a-worktree-removed-line-while-the-file-stands ()
  "With no base blob, a removed line is fresh until the file it left changes."
  (let* ((content revu-anchor-test-content)
         (anchor (revu-anchor-create content 4)))
    (should (equal (revu-anchor-locate-removed nil content anchor 4)
                   '(4 . fresh)))
    (should (equal (revu-anchor-locate-removed
                    nil (concat content "eleven\n") anchor 4)
                   '(nil . orphaned)))))

;;;; Editing the Source under the Review

(ert-deftest revu-anchor-re-finds-an-edited-file-s-line-as-moved ()
  "Editing the file above an Annotation moves it; deleting its line orphans it."
  (revu-fixture-with-repo root
    (let* ((baseline (revu-fixture-file-contents root "alpha.txt"))
           (anchor (revu-anchor-create baseline 7)))
      (revu-fixture-write-file root "alpha.txt"
                               (concat "alpha zero\n" baseline))
      (should (equal (revu-anchor-locate
                      (revu-fixture-file-contents root "alpha.txt") anchor 7)
                     '(8 . moved)))
      (revu-fixture-write-file
       root "alpha.txt"
       (replace-regexp-in-string "alpha seven[^\n]*\n" "" baseline))
      (should (equal (revu-anchor-locate
                      (revu-fixture-file-contents root "alpha.txt") anchor 7)
                     '(nil . orphaned))))))

;;;; Path resolution

(ert-deftest revu-anchor-resolves-a-renamed-path-and-keeps-its-line ()
  "A renamed file resolves to its new path with its Annotations intact."
  (revu-fixture-with-repo root
    (let* ((source (revu-source-staged "HEAD"))
           (anchor (revu-anchor-create
                    (revu-diff-show-file root "HEAD" "delta.txt") 2))
           (resolutions (revu-diff-resolve-paths
                         root source '("delta.txt" "gamma.txt" "beta.txt"))))
      (should (equal (alist-get "delta.txt" resolutions nil nil #'equal)
                     '(renamed . "delta-renamed.txt")))
      (should (equal (alist-get "gamma.txt" resolutions nil nil #'equal)
                     'deleted))
      (should (equal (alist-get "beta.txt" resolutions nil nil #'equal)
                     'present))
      (should (equal (revu-anchor-locate
                      (revu-fixture-file-contents root "delta-renamed.txt")
                      anchor 2)
                     '(2 . fresh))))))

(ert-deftest revu-anchor-never-follows-a-rename-for-a-plain-file-review ()
  "A plain-file Review's missing path is deleted, repository or not."
  (revu-fixture-with-repo root
    (let ((source (revu-source-file "delta.txt")))
      (should (equal (alist-get "delta.txt"
                                (revu-diff-resolve-paths root source
                                                         '("delta.txt"))
                                nil nil #'equal)
                     'deleted)))))

(ert-deftest revu-anchor-resolves-a-range-source-against-its-two-revisions ()
  "A range Review resolves paths between the Revisions it was taken over."
  (revu-fixture-with-repo root
    (let ((source (revu-source-range "main" "feature")))
      (should (equal (revu-diff-resolve-paths root source '("alpha.txt"))
                     '(("alpha.txt" . present)))))))

(ert-deftest revu-anchor-follows-a-rename-made-after-a-range-s-head ()
  "Path resolution asks what became of a path by now, not by the head.
ADR-0004 spells the question `base..worktree' for every git Source.  A
file renamed after the head a range was taken at is still missing from
the worktree, and calling it deleted would badge a whole file's
Annotations wrong."
  (revu-fixture-with-repo root
    ;; Both ends of the range are pinned to commits that predate the rename,
    ;; so asking `base..head' could not see it and `base..worktree' must.
    (let ((base (revu-fixture-git-output root "rev-parse" "main"))
          (head (revu-fixture-git-output root "rev-parse" "feature")))
      (revu-fixture-git-output root "checkout" "-q" "main")
      (revu-fixture-git-output root "mv" "alpha.txt" "alpha-moved.txt")
      (revu-fixture-git-output root "commit" "-m" "Rename alpha after the head")
      (let ((source (revu-source-range base head)))
        (should (equal (revu-diff-resolve-paths root source '("alpha.txt"))
                       '(("alpha.txt" renamed . "alpha-moved.txt"))))))))

(provide 'revu-anchor-test)
;;; revu-anchor-test.el ends here
