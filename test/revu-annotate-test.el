;;; revu-annotate-test.el --- Tests for the Annotation commands  -*- lexical-binding: t; -*-

;;; Commentary:

;; Tests for the commands that add, edit and delete Annotations.  Every
;; test drives a command in a review buffer over the fixture repository
;; and asserts on the two things the reviewer and their agent see: the
;; Sidecar on disk, read back as an agent would read it, and the rendered
;; buffer's text and section tree.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'magit-section)
(require 'revu)
(require 'revu-fixture)

(defun revu-annotate-test--annotations (root name)
  "Return the Annotations the Sidecar called NAME under ROOT holds, as a list."
  (append (revu-review-annotations (revu-fixture-sidecar root name)) nil))

(defun revu-annotate-test--only (root name)
  "Return the one Annotation the Sidecar called NAME under ROOT holds."
  (let ((annotations (revu-annotate-test--annotations root name)))
    (should (equal (length annotations) 1))
    (car annotations)))

(ert-deftest revu-annotate-line-records-the-line-at-point ()
  "Annotating the line at point records a line Target and its Anchor.
The Annotation is in the Sidecar on disk when the command returns, and
the reviewer can read it in the buffer under the line it is about."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree nil "worktree")
      (revu-fixture-goto-line-matching "^\\+alpha seven in the worktree$")
      (revu-annotate-line "question" "Is seven the right one?")
      (let* ((annotation (revu-annotate-test--only root "worktree"))
             (target (revu-annotation-target annotation))
             (anchor (revu-annotation-anchor annotation)))
        (should (equal (revu-annotation-kind annotation) "question"))
        (should (equal (revu-annotation-body annotation)
                       "Is seven the right one?"))
        (should (equal (revu-target-kind target) "line"))
        (should (equal (revu-target-path target) "alpha.txt"))
        (should (equal (revu-target-line-number target) 7))
        (should (equal (revu-target-origin target) "added"))
        (should (equal (revu-anchor-line anchor)
                       "alpha seven in the worktree"))
        (should (equal (revu-anchor-digest anchor)
                       (revu-digest (revu-fixture-file-contents root
                                                                "alpha.txt")))))
      (let ((text (revu-fixture-render)))
        (should (string-match-p "question" text))
        (should (string-match-p "Is seven the right one\\?" text))))))

(ert-deftest revu-annotate-anchors-an-added-line-in-what-the-source-shows ()
  "A range Review anchors its lines in the head Revision, not the worktree.
The Anchor has to record the line the reviewer pointed at.  Reading it
out of the worktree would bake in whatever the worktree has drifted to
since -- here, a line that says something else entirely."
  (revu-fixture-in-repo root
    ;; The worktree's alpha.txt already differs from feature's, and now it
    ;; differs on the very line the range review shows as added.
    (revu-fixture-write-file
     root "alpha.txt"
     (replace-regexp-in-string "alpha three" "alpha three drifted"
                               revu-fixture-alpha-baseline t t))
    (with-current-buffer (revu-diff-range "main" "feature" "main..feature")
      (revu-fixture-goto-line-matching "^\\+alpha three on feature$")
      (revu-annotate-line "note" "Anchored in what the range shows")
      (let* ((annotation (revu-annotate-test--only root "main..feature"))
             (anchor (revu-annotation-anchor annotation)))
        (should (equal (revu-anchor-line anchor) "alpha three on feature"))
        (should (equal (revu-anchor-digest anchor)
                       (revu-digest (revu-diff-show-file
                                     root "feature" "alpha.txt"))))
        ;; And emphatically not the worktree's drifted content.
        (should-not (equal (revu-anchor-digest anchor)
                           (revu-digest (revu-fixture-file-contents
                                         root "alpha.txt"))))))))

(ert-deftest revu-annotate-leaves-a-pasted-diff-s-line-unanchored ()
  "A pasted diff records blob ids, and no blob has a file to read inside it.
So its Annotations carry no Anchor and re-locate at the line they were
recorded on.  This is the cost of ADR-0005 having no pasted-diff Source,
tracked in dcr-01m0r9smxsrv; it is pinned here so it stays deliberate --
the Annotation must still be written, valid, and rendered."
  (revu-fixture-in-repo root
    (let ((text (revu-fixture-git-output root "diff" "main..feature")))
      (with-temp-buffer
        (insert text)
        (revu-diff-buffer (current-buffer) "pasted")))
    (with-current-buffer "*revu: pasted*"
      (revu-fixture-goto-line-matching "^\\+alpha three on feature$")
      (revu-annotate-line "note" "No blob to anchor in")
      (let ((annotation (revu-annotate-test--only root "pasted")))
        (should-not (revu-annotation-anchor annotation))
        (should (equal (revu-target-line-number
                        (revu-annotation-target annotation))
                       3)))
      ;; The Sidecar is valid and the Annotation renders where it was made.
      (should (revu-fixture-sidecar root "pasted"))
      (should (string-match-p "No blob to anchor in" (revu-fixture-render))))))

(ert-deftest revu-annotate-names-a-removed-line-by-the-path-it-was-removed-from ()
  "A removed line in a renamed file is recorded under the old path.
That is the only path the line exists under -- it is read back from the
base blob, where the file had not been renamed yet -- and ADR-0004 keeps
a Target's path as recorded rather than rewriting it later."
  (revu-fixture-in-repo root
    ;; Stage a rename that also drops a line, so the file has removals.
    (revu-fixture-git-output root "mv" "alpha.txt" "alpha-renamed.txt")
    (revu-fixture-write-file
     root "alpha-renamed.txt"
     (replace-regexp-in-string "alpha three\n" "" revu-fixture-alpha-baseline))
    (revu-fixture-git-output root "add" "-A")
    (with-current-buffer (revu-diff-staged "staged")
      (revu-fixture-goto-line-matching "^-alpha three$")
      (revu-annotate-line "change" "Why did this go?")
      (let* ((annotation (revu-annotate-test--only root "staged"))
             (target (revu-annotation-target annotation))
             (anchor (revu-annotation-anchor annotation)))
        (should (equal (revu-target-origin target) "removed"))
        (should (equal (revu-target-path target) "alpha.txt"))
        ;; The base blob was readable, so the line really was anchored.
        (should anchor)
        (should (equal (revu-anchor-line anchor) "alpha three"))))))

(ert-deftest revu-annotation-is-in-the-sidecar-when-the-command-returns ()
  "The Sidecar on disk holds the Annotation before the command is over.
No save step, no debounce: the file an agent reads is the review state
itself (ADR-0002)."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree nil "worktree")
      (revu-fixture-goto-line-matching "^\\+alpha seven in the worktree$")
      (revu-annotate-line "note" "Landed before the command returned")
      ;; Read the raw file, not revu's own state: this is what an agent
      ;; starting the moment the command returns would find.
      (let ((text (revu-fixture-sidecar-text root "worktree")))
        (should text)
        (should (string-match-p "Landed before the command returned" text))))))

(ert-deftest revu-annotate-range-records-the-selected-run-of-lines ()
  "Annotating a region records a range Target over the lines it covers."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree nil "worktree")
      (revu-fixture-goto-line-matching "^ alpha eight$")
      (let ((beginning (point)))
        (revu-fixture-goto-line-matching "^ alpha ten$")
        (revu-annotate-range beginning (line-end-position) "change"
                             "Rewrite these three"))
      (let ((target (revu-annotation-target
                     (revu-annotate-test--only root "worktree"))))
        (should (equal (revu-target-kind target) "range"))
        (should (equal (revu-target-path target) "alpha.txt"))
        (should (equal (revu-target-start target) 8))
        (should (equal (revu-target-end target) 10))
        (should (equal (revu-target-origin target) "context"))))))

(ert-deftest revu-annotate-range-takes-the-added-origin-of-a-mixed-selection ()
  "A selection covering both Origins of a change is a range over the added one.
A range is counted in one file's numbers, and the added Origin is the one
the revdiff Export renders a mixed run over."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree nil "worktree")
      (revu-fixture-goto-line-matching "^-alpha seven$")
      (let ((beginning (point)))
        (revu-fixture-goto-line-matching
         "^\\+alpha seven in the worktree$")
        (revu-annotate-range beginning (line-end-position) "note" "Both Origins"))
      (let ((target (revu-annotation-target
                     (revu-annotate-test--only root "worktree"))))
        (should (equal (revu-target-origin target) "added"))
        (should (equal (revu-target-start target) 7))
        (should (equal (revu-target-end target) 7))))))

(ert-deftest revu-annotate-range-passes-over-the-annotations-it-straddles ()
  "A region sweeping across an Annotation section is about the file lines.
The Annotation sections rendered between the lines are not lines of the
Source, and a range drawn over them ignores them (ADR-0011)."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree nil "worktree")
      (revu-fixture-goto-line-matching "^ alpha eight$")
      (revu-annotate-line "note" "An Annotation in the way")
      (revu-fixture-goto-line-matching "^ alpha eight$")
      (let ((beginning (point)))
        (revu-fixture-goto-line-matching "^ alpha nine$")
        (revu-annotate-range beginning (line-end-position) "change"
                             "Across the Annotation"))
      (let* ((annotations (revu-annotate-test--annotations root "worktree"))
             (target (revu-annotation-target
                      (seq-find (lambda (annotation)
                                  (equal (revu-annotation-kind annotation)
                                         "change"))
                                annotations))))
        (should (equal (length annotations) 2))
        (should (equal (revu-target-kind target) "range"))
        ;; The two file lines the region touches, with the Annotation
        ;; section rendered between them passed over.
        (should (equal (revu-target-origin target) "context"))
        (should (equal (revu-target-start target) 8))
        (should (equal (revu-target-end target) 9))))))

(ert-deftest revu-annotate-hunk-records-a-range-over-the-whole-hunk ()
  "Annotating a hunk records a range spanning it, not a Target kind of its own."
  (revu-fixture-in-repo root
    (revu-fixture-write-file
     root "alpha.txt"
     (thread-last revu-fixture-alpha-baseline
                  (replace-regexp-in-string "alpha two" "alpha two edited")
                  (replace-regexp-in-string "alpha three" "alpha three edited")))
    (with-current-buffer (revu-diff-worktree nil "worktree")
      (revu-fixture-goto-line-matching "^\\+alpha two edited$")
      (revu-annotate-hunk "question" "What is this hunk for?")
      (let ((target (revu-annotation-target
                     (revu-annotate-test--only root "worktree"))))
        (should (equal (revu-target-kind target) "range"))
        (should (equal (revu-target-path target) "alpha.txt"))
        (should (equal (revu-target-origin target) "added"))
        (should (equal (revu-target-start target) 2))
        (should (equal (revu-target-end target) 3))))))

(ert-deftest revu-annotate-file-records-a-file-target ()
  "Annotating a file records a file Target, which needs no Anchor."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree nil "worktree")
      (revu-fixture-goto-line-matching "^modified +alpha\\.txt$")
      (revu-annotate-file "note" "This file carries the change")
      (let ((annotation (revu-annotate-test--only root "worktree")))
        (should (equal (revu-target-kind (revu-annotation-target annotation))
                       "file"))
        (should (equal (revu-target-path (revu-annotation-target annotation))
                       "alpha.txt"))
        (should-not (revu-annotation-anchor annotation)))
      (should (string-match-p "This file carries the change"
                              (revu-fixture-render))))))

(ert-deftest revu-annotate-review-records-a-review-target ()
  "Annotating the Review records a Target on the Review as a whole."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree nil "worktree")
      (revu-annotate-review "change" "Split this into two commits")
      (let ((annotation (revu-annotate-test--only root "worktree")))
        (should (equal (revu-target-kind (revu-annotation-target annotation))
                       "review"))
        (should-not (revu-target-path (revu-annotation-target annotation))))
      (should (string-match-p "Split this into two commits"
                              (revu-fixture-render))))))

(ert-deftest revu-annotate-anchors-a-removed-line-in-the-base-blob ()
  "A removed line is anchored in the blob it was removed from.
It is not in the worktree to anchor in, and the Revision the Review
records is what makes it findable (ADR-0003)."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-staged "staged")
      (revu-fixture-goto-line-matching "^-beta two$")
      (revu-annotate-line "question" "Why did this go?")
      (let* ((annotation (revu-annotate-test--only root "staged"))
             (target (revu-annotation-target annotation))
             (anchor (revu-annotation-anchor annotation)))
        (should (equal (revu-target-origin target) "removed"))
        (should (equal (revu-target-line-number target) 2))
        (should (equal (revu-anchor-line anchor) "beta two"))
        ;; The fixture trims what git printed; the blob ends in a newline.
        (should (equal (revu-anchor-digest anchor)
                       (revu-digest (concat (revu-fixture-git-output
                                             root "show" "HEAD:beta.txt")
                                            "\n")))))
      ;; The blob does not move, so the Annotation comes back on its line.
      (should (string-match-p "^-beta two\n +question \\[fresh\\]"
                              (revu-fixture-render))))))

(ert-deftest revu-annotate-edit-rewrites-the-body-in-place ()
  "Editing an Annotation rewrites its body and keeps its Target and Anchor."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree nil "worktree")
      (revu-fixture-goto-line-matching "^\\+alpha seven in the worktree$")
      (revu-annotate-line "question" "First wording")
      (let ((before (revu-annotate-test--only root "worktree")))
        (revu-fixture-goto-line-matching "^ +question")
        (revu-annotate-edit "Second wording")
        (let ((after (revu-annotate-test--only root "worktree")))
          (should (equal (revu-annotation-id after) (revu-annotation-id before)))
          (should (equal (revu-annotation-body after) "Second wording"))
          (should (equal (revu-annotation-target after)
                         (revu-annotation-target before)))
          (should (equal (revu-annotation-anchor after)
                         (revu-annotation-anchor before)))))
      (let ((text (revu-fixture-render)))
        (should (string-match-p "Second wording" text))
        (should-not (string-match-p "First wording" text))))))

(ert-deftest revu-annotate-delete-removes-the-annotation-at-point ()
  "Deleting an Annotation takes that one out of the Sidecar and the buffer."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree nil "worktree")
      (revu-fixture-goto-line-matching "^\\+alpha seven in the worktree$")
      (revu-annotate-line "note" "The one that stays")
      (revu-fixture-goto-line-matching "^\\+alpha seven in the worktree$")
      (revu-annotate-line "change" "The one that goes")
      (revu-fixture-goto-line-matching "^ +change")
      (revu-annotate-delete)
      (let ((annotation (revu-annotate-test--only root "worktree")))
        (should (equal (revu-annotation-body annotation) "The one that stays")))
      (let ((text (revu-fixture-render)))
        (should (string-match-p "The one that stays" text))
        (should-not (string-match-p "The one that goes" text))))))

(ert-deftest revu-annotations-off-the-diff-lines-are-editable-and-deletable ()
  "An Annotation on a file or on the Review is a section like any other.
Point rests on it, editing rewrites it and deleting takes it out."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree nil "worktree")
      (revu-annotate-review "note" "About the change as a whole")
      (revu-fixture-goto-line-matching "^modified +alpha\\.txt$")
      (revu-annotate-file "change" "About this file")
      (revu-fixture-goto-line-matching "^ +change")
      (revu-annotate-edit "About this file, restated")
      (revu-fixture-goto-line-matching "^ +note")
      (revu-annotate-delete)
      (let ((annotation (revu-annotate-test--only root "worktree")))
        (should (equal (revu-target-kind (revu-annotation-target annotation))
                       "file"))
        (should (equal (revu-annotation-body annotation)
                       "About this file, restated")))
      (let ((text (revu-fixture-render)))
        (should (string-match-p "About this file, restated" text))
        (should-not (string-match-p "About the change as a whole" text))))))

(ert-deftest revu-two-annotations-on-one-target-both-render ()
  "A question and a change on the same line are two Annotations, and both show.
The ULID is the identity, so sharing a Target is not sharing a record
\(ADR-0003)."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree nil "worktree")
      (revu-fixture-goto-line-matching "^\\+alpha seven in the worktree$")
      (revu-annotate-line "question" "Why seven?")
      (revu-fixture-goto-line-matching "^\\+alpha seven in the worktree$")
      (revu-annotate-line "change" "Make it eight")
      (should (equal (length (revu-annotate-test--annotations root "worktree")) 2))
      (let ((text (revu-fixture-render)))
        (should (string-match-p "Why seven\\?" text))
        (should (string-match-p "Make it eight" text)))
      (should (equal (length (revu-fixture-sections
                              'revu-annotation-section))
                     2)))))

(ert-deftest revu-annotation-is-a-foldable-section-under-its-line ()
  "An Annotation is a section of its own: point rests on it and TAB folds it."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree nil "worktree")
      (revu-fixture-goto-line-matching "^\\+alpha seven in the worktree$")
      (revu-annotate-line "question" "Folds away")
      (revu-fixture-goto-line-matching "^ +question")
      (let ((section (magit-current-section)))
        (should (object-of-class-p section 'revu-annotation-section))
        ;; The Annotation sits under the line it is about, inside the hunk.
        (should (object-of-class-p (oref section parent) 'revu-hunk-section))
        (should (save-excursion (forward-line -1)
                                (get-text-property (point) 'revu-target)))
        (let ((body (save-excursion (forward-line 1) (point))))
          (revu-fixture-press-tab)
          (should (invisible-p body))
          (should-not (invisible-p (oref section start)))
          (revu-fixture-press-tab)
          (should-not (invisible-p body)))))))

(ert-deftest revu-resume-badges-an-annotation-whose-line-moved ()
  "Yesterday's Annotation comes back on the line its Anchor was re-found on.
The state is derived from today's content on every render, and is not in
the Sidecar: a stored state is a lie as soon as the file is edited."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree nil "worktree")
      (revu-fixture-goto-line-matching "^\\+alpha seven in the worktree$")
      (revu-annotate-line "question" "Still about this line"))
    (revu-fixture-kill-review-buffers)
    ;; The reviewer's colleague adds a line above it and the numbers shift.
    (revu-fixture-write-file
     root "alpha.txt"
     (concat "alpha zero\n"
             (replace-regexp-in-string "alpha seven" "alpha seven in the worktree"
                                       revu-fixture-alpha-baseline t t)))
    (with-current-buffer (revu-diff-worktree nil "worktree")
      (let ((text (revu-fixture-render)))
        (should (string-match-p "\\[moved\\]" text))
        (should (string-match-p "Still about this line" text))
        ;; It is rendered under the line it was re-found on, which is one
        ;; further down than the one it was written on.
        (should (string-match-p
                 "^\\+alpha seven in the worktree\n +question \\[moved\\]"
                 text))))
    (should-not (string-match-p "moved" (revu-fixture-sidecar-text root "worktree")))
    (should-not (string-match-p "state" (revu-fixture-sidecar-text root "worktree")))))

(ert-deftest revu-resume-badges-an-annotation-whose-line-is-gone ()
  "An Annotation whose line and neighbours are gone comes back orphaned.
It is not dropped: it renders under its file's heading, where the
reviewer can read it and decide."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree nil "worktree")
      (revu-fixture-goto-line-matching "^\\+alpha seven in the worktree$")
      (revu-annotate-line "change" "About a line that will go"))
    (revu-fixture-kill-review-buffers)
    (revu-fixture-write-file root "alpha.txt"
                             "wholly\ndifferent\ncontent\nnow\n")
    (with-current-buffer (revu-diff-worktree nil "worktree")
      (let ((text (revu-fixture-render)))
        (should (string-match-p "\\[orphaned\\]" text))
        (should (string-match-p "About a line that will go" text))
        (should (string-match-p
                 "^modified +alpha\\.txt\n +change \\[orphaned\\]" text))))))

(ert-deftest revu-annotate-asks-for-the-kind-and-the-body ()
  "Called as a command, annotating asks for the Kind and opens a body buffer.
The Kind is asked outright, with no default hiding the choice."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree nil "worktree")
      (revu-fixture-goto-line-matching "^\\+alpha seven in the worktree$")
      (let ((offered nil))
        (cl-letf (((symbol-function 'completing-read)
                   (lambda (_prompt collection &rest _)
                     (setq offered collection)
                     "note"))
                  ((symbol-function 'read-string-from-buffer)
                   (lambda (_prompt string)
                     (concat string "Written in a buffer"))))
          (call-interactively #'revu-annotate))
        (should (equal offered revu-annotation-kinds)))
      (let ((annotation (revu-annotate-test--only root "worktree")))
        (should (equal (revu-annotation-kind annotation) "note"))
        (should (equal (revu-annotation-body annotation)
                       "Written in a buffer"))))))

(provide 'revu-annotate-test)
;;; revu-annotate-test.el ends here
