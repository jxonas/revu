;;; revu-header-test.el --- Tests for the header at the top of a Review  -*- lexical-binding: t; -*-

;;; Commentary:

;; The review buffer opens with a header naming the Review, the Source
;; under it, the Narrowing that limits it, and how far along the reviewer
;; is.  These tests assert on what the header says, on the section it is,
;; and on what `a' does when point is in it.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'magit-section)
(require 'revu)
(require 'revu-fixture)

(defun revu-header-test--line (label)
  "Return the header line LABEL opens, without its label or padding.
Nil when the header draws no such line."
  (save-excursion
    (goto-char (point-min))
    (when (re-search-forward (format "^%s: *\\(.*\\)$" label) nil t)
      (match-string-no-properties 1))))

(defun revu-header-test--section ()
  "Return the header section of the buffer as it stands now."
  (car (revu-fixture-sections 'revu-header-section)))

(defun revu-header-test--targets ()
  "Return the Target kind and path of every Annotation of the Review."
  (seq-map (lambda (annotation)
             (let ((target (revu-annotation-target annotation)))
               (cons (revu-target-kind target) (revu-target-path target))))
           (append (revu-review-annotations (revu-review)) nil)))

;;;; What the header says

(ert-deftest revu-header-opens-the-buffer-of-a-diff-review ()
  "The header is the first thing in the buffer, above the first file."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree nil "worktree")
      (let ((text (revu-fixture-render)))
        (should (string-prefix-p "Review:    worktree (scratch)\n" text))
        (should (string-match-p
                 (concat "\\`Review: .*\nSource: .*\nAnnotations: .*\n"
                         "Reviewed: .*\n\nmodified")
                 (replace-regexp-in-string "^\\([A-Za-z]+:\\) +" "\\1 " text))))
      (should (equal (revu-header-test--line "Source")
                     (format "worktree vs %s Baseline"
                             (revu-fixture-git-output root "rev-parse" "--short"
                                                      "HEAD"))))
      (should (equal (revu-header-test--line "Annotations") "0"))
      (should (equal (revu-header-test--line "Reviewed") "0/3 hunks")))))

(ert-deftest revu-header-opens-the-buffer-of-a-plain-file-review ()
  "A plain file has no hunks to be counted in, so it says the word it is in."
  (revu-fixture-in-repo root
    (revu-file (expand-file-name "README.md" root) "plain")
    (with-current-buffer (revu-buffer-name "plain")
      (should (equal (revu-header-test--line "Review") "plain"))
      (should (equal (revu-header-test--line "Source") "file README.md"))
      (should (equal (revu-header-test--line "Reviewed") "unreviewed"))
      (revu-fixture-goto-line-matching "^# Fixture$")
      (revu-reviewed-toggle)
      (should (equal (revu-header-test--line "Reviewed") "reviewed"))
      (revu-fixture-write-file root "README.md" "# Fixture\n\nEdited since.\n")
      (revu-reload)
      (should (equal (revu-header-test--line "Reviewed") "stale")))))

(ert-deftest revu-header-names-both-revisions-of-a-range ()
  "A range is named by the two Revisions it spans, each with its subject."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-range "main" "feature" "main..feature")
      (should (equal (revu-header-test--line "Source")
                     (format "%s Baseline .. %s Change alpha on feature"
                             (revu-fixture-git-output root "rev-parse" "--short"
                                                      "main")
                             (revu-fixture-git-output root "rev-parse" "--short"
                                                      "feature")))))))

(ert-deftest revu-header-names-the-revision-the-index-is-against ()
  "A staged Source is the index against a Revision, and says so."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-staged "staged")
      (should (string-prefix-p "staged vs "
                               (revu-header-test--line "Source"))))))

(ert-deftest revu-header-falls-back-to-a-revision-git-cannot-look-up ()
  "A Revision git knows nothing about still names what the Review was over.
A commit rebased away, and the blob ids a pasted diff names, are gone
from the repository; the header says the id it has rather than refusing
to draw."
  (revu-fixture-in-repo root
    (let ((absent "0123456789012345678901234567890123456789"))
      (should-not (revu-diff-describe-revision root absent))
      (with-current-buffer (revu-diff-worktree nil "worktree")
        (should (equal (revu--source-description
                        (revu-source-range absent (revu-diff-head-revision root)))
                       (format "%s .. %s Baseline"
                               absent
                               (revu-fixture-git-output root "rev-parse"
                                                        "--short" "HEAD"))))))))

(ert-deftest revu-header-shows-a-narrowing-only-when-there-is-one ()
  "A narrowed Source is a different Source, and the header tells them apart."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree nil "full")
      (should-not (revu-header-test--line "Narrowing")))
    (with-current-buffer (revu-diff-worktree nil "narrow" (list "alpha.txt"))
      (should (equal (revu-header-test--line "Narrowing") "alpha.txt")))))

(ert-deftest revu-header-badges-only-the-scratch-bucket ()
  "The badge mirrors what `revu-open' offers: a named Review is not scratch."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree nil nil)
      (should (equal (revu-header-test--line "Review") "worktree (scratch)"))
      (revu-rename "the-seventh-line")
      (should (equal (revu-header-test--line "Review") "the-seventh-line")))))

;;;; The Annotations figure

(ert-deftest revu-header-breaks-the-annotations-down-by-kind ()
  "The header counts every Annotation and says what the reviewer meant by them."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree nil "worktree")
      (revu-annotate-review "note" "One note.")
      (should (equal (revu-header-test--line "Annotations") "1 (1 note)"))
      (revu-fixture-goto-line-matching "^\\+alpha seven in the worktree$")
      (revu-annotate-line "question" "Why this line?")
      (revu-annotate-line "question" "And why now?")
      (should (equal (revu-header-test--line "Annotations")
                     "3 (2 questions \N{MIDDLE DOT} 1 note)")))))

(ert-deftest revu-header-counts-what-an-agent-has-answered ()
  "A Reply is the answered signal (ADR-0007), and the header totals them."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree nil "worktree")
      (revu-fixture-goto-line-matching "^\\+alpha seven in the worktree$")
      (revu-annotate-line "question" "Why this line?")
      (should (equal (revu-header-test--line "Annotations") "1 (1 question)"))
      (let ((review (revu-fixture-sidecar root "worktree")))
        (let ((annotations (revu-review-annotations review)))
          (aset annotations 0 (cons '(reply . "It guards the seventh line.")
                                    (aref annotations 0))))
        (let ((coding-system-for-write 'utf-8-unix))
          (write-region (revu-review-encode review) nil
                        (expand-file-name ".revu/reviews/worktree.json" root)
                        nil 'silent)))
      (revu-reload)
      (should (equal (revu-header-test--line "Annotations")
                     "1 (1 question), 1 answered")))))

(ert-deftest revu-header-counts-the-anchors-that-were-not-found-again ()
  "An orphaned Anchor is what the reviewer has lost, and the header says so."
  (revu-fixture-in-repo root
    (revu-file (expand-file-name "README.md" root) "plain")
    (with-current-buffer (revu-buffer-name "plain")
      (revu-fixture-goto-line-matching "^# Fixture$")
      (revu-annotate-line "note" "The title.")
      (should (equal (revu-header-test--line "Annotations") "1 (1 note)")))
    (revu-fixture-git-output root "mv" "README.md" "READTHIS.md")
    (revu-fixture-git-output root "commit" "-q" "-m" "Rename the readme")
    (with-current-buffer (revu-buffer-name "plain")
      (revu-reload)
      (should (equal (revu-header-test--line "Annotations")
                     "1 (1 note), 1 orphaned")))))

;;;; The Reviewed figure

(ert-deftest revu-header-counts-the-whole-source-whatever-the-filters-leave-out ()
  "A view filter is a lens on a Source and never a change of Source.
Hiding what has been read cannot make the reviewer look further along
than they are."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-staged "staged")
      (should (equal (revu-header-test--line "Reviewed") "0/2 hunks"))
      (revu-fixture-goto-line-matching "^modified +beta\\.txt$")
      (revu-reviewed-toggle)
      (should (equal (revu-header-test--line "Reviewed") "1/2 hunks"))
      (revu-reviewed-toggle-hide-reviewed)
      (should-not (string-match-p "beta\\.txt" (revu-fixture-render)))
      (should (equal (revu-header-test--line "Reviewed") "1/2 hunks"))
      (revu-reviewed-toggle-annotated-only)
      (should (equal (revu-header-test--line "Reviewed") "1/2 hunks")))))

(ert-deftest revu-header-counts-the-hunks-that-changed-since-they-were-read ()
  "Rework told from new work is the whole point of the stale count."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree nil "worktree")
      (revu-fixture-goto-line-matching "^\\+alpha seven in the worktree$")
      (revu-reviewed-toggle)
      (should (equal (revu-header-test--line "Reviewed") "1/3 hunks")))
    (revu-fixture-write-file
     root "alpha.txt"
     (replace-regexp-in-string "alpha four" "alpha four edited"
                               (revu-fixture-file-contents root "alpha.txt")
                               t t))
    (with-current-buffer (revu-buffer-name "worktree")
      (revu-reload)
      (should (equal (revu-header-test--line "Reviewed") "0/3 hunks, 1 stale")))))

(ert-deftest revu-header-faces-the-labels-and-the-figures-that-want-attention ()
  "The labels are the eye\='s way down the header; the values are plain.
The two figures that are not plain are the ones a reviewer must not read
past: what they read and lost, and what they read and has changed."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree nil nil)
      (should (eq (revu-fixture-face-on-screen "^Review:") 'revu-header-label))
      (should (eq (revu-fixture-face-on-screen "(scratch)") 'shadow))
      (should-not (revu-fixture-face-on-screen "0/3 hunks"))
      (revu-fixture-goto-line-matching "^\\+alpha seven in the worktree$")
      (revu-reviewed-toggle))
    (revu-fixture-write-file
     root "alpha.txt"
     (replace-regexp-in-string "alpha four" "alpha four edited"
                               (revu-fixture-file-contents root "alpha.txt")
                               t t))
    (with-current-buffer (revu-buffer-name "worktree")
      (revu-reload)
      (should (eq (revu-fixture-face-on-screen "1 stale") 'warning)))))

(ert-deftest revu-header-faces-the-orphaned-figure-as-a-warning ()
  "An Anchor that was not found again is what the reviewer has lost."
  (revu-fixture-in-repo root
    (revu-file (expand-file-name "README.md" root) "plain")
    (with-current-buffer (revu-buffer-name "plain")
      (revu-fixture-goto-line-matching "^# Fixture$")
      (revu-annotate-line "note" "The title."))
    (revu-fixture-git-output root "mv" "README.md" "READTHIS.md")
    (revu-fixture-git-output root "commit" "-q" "-m" "Rename the readme")
    (with-current-buffer (revu-buffer-name "plain")
      (revu-reload)
      (should (eq (revu-fixture-face-on-screen "1 orphaned") 'warning)))))

;;;; The header as a section

(ert-deftest revu-header-holds-the-annotations-on-the-review ()
  "What the reviewer has to say about the change sits under the header.
An Annotation on a file the Source does not carry belongs to no section
at all and stays loose, between the header and the first file."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree nil "worktree")
      (revu-annotate-review "note" "About the change as a whole.")
      (let ((header (revu-header-test--section)))
        (should (= (length (oref header children)) 1))
        (should (object-of-class-p (car (oref header children))
                                   'revu-annotation-section)))
      ;; An Annotation on README.md, which no worktree diff carries.
      (let ((review (revu-fixture-sidecar root "worktree")))
        (setf (alist-get 'annotations review)
              (vconcat (revu-review-annotations review)
                       (vector '((id . "01ZZZZZZZZZZZZZZZZZZZZZZZZ")
                                 (kind . "note")
                                 (target . ((kind . "file")
                                            (path . "README.md")))
                                 (body . "Nothing in the Source is about this.")
                                 (created . "2026-08-23T21:00:00Z")
                                 (updated . "2026-08-23T21:00:00Z")))))
        (let ((coding-system-for-write 'utf-8-unix))
          (write-region (revu-review-encode review) nil
                        (expand-file-name ".revu/reviews/worktree.json" root)
                        nil 'silent)))
      (revu-reload)
      (let ((header (revu-header-test--section)))
        (should (= (length (oref header children)) 1))
        (should (string-match-p
                 "Nothing in the Source is about this\\.\nmodified"
                 (revu-fixture-render)))))))

(ert-deftest revu-header-folds-with-tab-and-stays-folded ()
  "TAB folds the header, and the fold outlives the render that rebuilds it."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree nil "worktree")
      (revu-fixture-goto-line-matching "^Review:")
      (revu-fixture-press-tab)
      (should (revu-fixture-hidden-on-screen-p (revu-header-test--section)))
      ;; The Source is not folded away with the header: the header is a
      ;; section of its own and not the root's heading.
      (should (string-match-p "^modified +alpha\\.txt$" (revu-fixture-render)))
      (revu-reload)
      (should (revu-fixture-hidden-on-screen-p (revu-header-test--section))))))

(ert-deftest revu-header-is-current-after-every-change ()
  "The header is rendered from state, so it can never drift from it."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree nil nil)
      (should (equal (revu-header-test--line "Annotations") "0"))
      (revu-annotate-review "change" "Rename this.")
      (should (equal (revu-header-test--line "Annotations") "1 (1 change)"))
      (revu-fixture-goto-line-matching "^ +change")
      (revu-annotate-delete)
      (should (equal (revu-header-test--line "Annotations") "0")))))

;;;; What `a' does

(ert-deftest revu-annotate-on-the-header-annotates-the-review ()
  "Point in the header is the Review as a whole."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree nil "worktree")
      (revu-fixture-goto-line-matching "^Source:")
      (revu-annotate "note" "About the change.")
      (should (equal (revu-header-test--targets) '(("review" . nil)))))))

(ert-deftest revu-annotate-on-a-review-annotation-annotates-the-review ()
  "An Annotation is no Target, so point on one is whatever it sits under.
Point on an Annotation under the header is still squarely in the header."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree nil "worktree")
      (revu-annotate-review "note" "About the change.")
      (revu-fixture-goto-line-matching "^ +About the change\\.$")
      (revu-annotate "question" "And what about this?")
      (should (equal (revu-header-test--targets)
                     '(("review" . nil) ("review" . nil)))))))

(ert-deftest revu-annotate-on-a-file-heading-annotates-the-file ()
  "Point on a file heading is that file and not the line under it."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree nil "worktree")
      (revu-fixture-goto-line-matching "^modified +alpha\\.txt$")
      (revu-annotate "note" "About this file.")
      (should (equal (revu-header-test--targets) '(("file" . "alpha.txt")))))))

(ert-deftest revu-annotate-on-a-line-still-annotates-the-line ()
  "The Source line is what it always was, header or no header."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree nil "worktree")
      (revu-fixture-goto-line-matching "^\\+alpha seven in the worktree$")
      (revu-annotate "note" "About this line.")
      (should (equal (revu-header-test--targets) '(("line" . "alpha.txt")))))))

(ert-deftest revu-annotate-on-a-hunk-heading-still-asks-for-a-line ()
  "A hunk heading is no Target of its own, so `a' says what it needs.
`h' is the route to the hunk, and widening to the file behind the
reviewer's back would annotate more than they are looking at."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree nil "worktree")
      (revu-fixture-goto-line-matching "^@@")
      (should-error (revu-annotate "note" "About what?") :type 'user-error))))

(provide 'revu-header-test)
;;; revu-header-test.el ends here
