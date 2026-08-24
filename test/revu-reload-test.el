;;; revu-reload-test.el --- Tests for the reload round trip  -*- lexical-binding: t; -*-

;;; Commentary:

;; Tests for the return leg (ADR-0007): the reload command re-reads the
;; Sidecar and the Source in one pass, so an agent's Reply and the
;; Annotations it appended appear in the review buffer, and a Sidecar
;; revu cannot read refuses loudly without touching the buffer or the
;; file.  Every test drives a command in a review buffer over the fixture
;; repository and asserts on what the reviewer and their agent see: the
;; Sidecar on disk, read back as an agent would read it, and the rendered
;; buffer.
;;
;; An agent is played by writing the Sidecar file directly, never through
;; revu's own Sidecar: that is the whole point of the write guard.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'magit-section)
(require 'revu)
(require 'revu-fixture)

(defun revu-reload-test--sidecar-file (root name)
  "Return the path of the Sidecar called NAME under ROOT."
  (expand-file-name (format ".revu/reviews/%s.json" name) root))

(defun revu-reload-test--write-sidecar (root name text)
  "Write TEXT as the Sidecar called NAME under ROOT, as an agent would.
The file is written behind revu's back, so the write guard sees what it
would see after an agent had edited the Sidecar."
  (let ((coding-system-for-write 'utf-8-unix))
    (write-region text nil (revu-reload-test--sidecar-file root name)
                  nil 'silent)))

(defun revu-reload-test--agent-edit (root name edit)
  "Apply EDIT to the Review in the Sidecar called NAME under ROOT.
EDIT is called with the decoded Review and returns the Review to write
back.  The file is rewritten directly, the way an agent rewrites it."
  (let ((review (funcall edit (revu-fixture-sidecar root name))))
    (revu-reload-test--write-sidecar root name (revu-review-encode review))
    review))

(defun revu-reload-test--set-reply (review reply)
  "Return REVIEW with REPLY set on its first Annotation."
  (let* ((annotations (revu-review-annotations review))
         (annotation (aref annotations 0)))
    (aset annotations 0 (cons (cons 'reply reply) annotation))
    review))

(defun revu-reload-test--appended (review kind body &optional line origin)
  "Return REVIEW with an Annotation of KIND carrying BODY appended.
The Annotation is the shape an agent writes: a fresh ULID, a Target and
no Anchor, because an agent has no file content to take one from.  It is
on LINE of Origin ORIGIN of alpha.txt, the changed line by default."
  (let ((annotation
         `((id . "01ZZZZZZZZZZZZZZZZZZZZZZZZ")
           (kind . ,kind)
           (target . ((kind . "line") (path . "alpha.txt")
                      (line . ,(or line 7))
                      (origin . ,(or origin "added"))))
           (body . ,body)
           (created . "2026-08-23T21:00:00Z")
           (updated . "2026-08-23T21:00:00Z"))))
    (setf (alist-get 'annotations review)
          (vconcat (revu-review-annotations review) (vector annotation)))
    review))

(defun revu-reload-test--open-worktree (root)
  "Open the worktree Review of ROOT with one question on a line of it.
Return the review buffer, with point left on the annotated line."
  (let ((buffer (revu-diff-worktree "worktree")))
    (with-current-buffer buffer
      (revu-fixture-goto-line-matching "alpha seven in the worktree")
      (revu-annotate-line "question" "Why this line?"))
    buffer))

(ert-deftest revu-reload-shows-an-agent-reply-under-the-body ()
  "A Reply written by an agent renders inline under the Annotation's body."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-reload-test--open-worktree root)
      (should-not (string-match-p "It guards the seventh line"
                                  (revu-fixture-render)))
      (revu-reload-test--agent-edit
       root "worktree"
       (lambda (review)
         (revu-reload-test--set-reply review "It guards the seventh line.")))
      (revu-reload)
      (let ((text (revu-fixture-render)))
        (should (string-match-p "Why this line?" text))
        (should (string-match-p "It guards the seventh line\\." text))
        ;; The Reply comes under the body it answers.
        (should (< (string-match "Why this line?" text)
                   (string-match "It guards the seventh line\\." text))))
      (should (eq (revu-fixture-face-on-screen "It guards the seventh line")
                  'revu-reply)))))

(ert-deftest revu-reload-highlight-keeps-a-reply-apart-from-the-body ()
  "Point on an Annotation covers its heading only.
The Reply's face is the answered signal (ADR-0007), so it has to stay
readable while the reviewer stands on the Annotation it answers."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-reload-test--open-worktree root)
      (revu-reload-test--agent-edit
       root "worktree"
       (lambda (review)
         (revu-reload-test--set-reply review "It guards the seventh line.")))
      (revu-reload)
      (revu-fixture-put-point-on-and-highlight "^ +question")
      (should (eq (revu-fixture-face-on-screen "^ +question")
                  'magit-section-highlight))
      (should (eq (revu-fixture-face-on-screen "Why this line\\?")
                  'revu-annotation-body))
      (should (eq (revu-fixture-face-on-screen "It guards the seventh line")
                  'revu-reply)))))

(defun revu-reload-test--annotation-sections ()
  "Return the ULID of every Annotation section rendered, in render order."
  (let ((found nil))
    (cl-labels ((walk (section)
                  (when (object-of-class-p section 'revu-annotation-section)
                    (push (oref section value) found))
                  (mapc #'walk (oref section children))))
      (walk magit-root-section))
    (nreverse found)))

(ert-deftest revu-reload-shows-an-annotation-the-agent-appended ()
  "An Annotation an agent appended renders as an ordinary section."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-reload-test--open-worktree root)
      (should (= (length (revu-reload-test--annotation-sections)) 1))
      (revu-reload-test--agent-edit
       root "worktree"
       (lambda (review)
         (revu-reload-test--appended review "note" "The agent read this too.")))
      (revu-reload)
      (should (member "01ZZZZZZZZZZZZZZZZZZZZZZZZ"
                      (revu-reload-test--annotation-sections)))
      (should (string-match-p "The agent read this too\\."
                              (revu-fixture-render))))))

(ert-deftest revu-reload-reads-the-source-again-in-the-same-pass ()
  "Reload re-reads the Source, so a change made since opening is rendered."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-reload-test--open-worktree root)
      (should-not (string-match-p "alpha two in the worktree"
                                  (revu-fixture-render)))
      (revu-fixture-write-file
       root "alpha.txt"
       (thread-last revu-fixture-alpha-baseline
                    (replace-regexp-in-string "alpha two" "alpha two in the worktree")
                    (replace-regexp-in-string "alpha seven"
                                              "alpha seven in the worktree")))
      (revu-reload)
      (let ((text (revu-fixture-render)))
        (should (string-match-p "alpha two in the worktree" text))
        ;; The Annotation is re-anchored against the Source as it is now.
        (should (string-match-p "Why this line?" text))))))

(defun revu-reload-test--refusal (root name text)
  "Write TEXT as the Sidecar NAME under ROOT and reload; return the message.
The rendered buffer and the file on disk are asserted to be exactly what
they were before the refusal: revu refuses a Sidecar whole and changes
nothing, so the reviewer can go and look at what their agent wrote."
  (let ((before (revu-fixture-render)))
    (revu-reload-test--write-sidecar root name text)
    (let ((message
           (should-error (revu-reload) :type 'revu-invalid-sidecar)))
      (should (equal (revu-fixture-render) before))
      (should (equal (revu-fixture-sidecar-text root name) text))
      (error-message-string message))))

(ert-deftest revu-reload-refuses-malformed-json-and-names-where ()
  "Malformed JSON refuses the Sidecar, naming the line and column it broke at."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-reload-test--open-worktree root)
      (let ((message (revu-reload-test--refusal
                      root "worktree"
                      "{\"schema\": 1,\n \"name\": \"worktree\",\n }")))
        (should (string-match-p "line 3" message))
        (should (string-match-p "column" message))))))

(ert-deftest revu-reload-refuses-a-broken-record-and-names-which ()
  "A record revu cannot read refuses the Sidecar, naming the record.
A `reply' of JSON null is the shape of the mistake: an unanswered
Annotation has no `reply' at all, so null is malformed rather than
another way of saying nothing."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-reload-test--open-worktree root)
      (let* ((broken (revu-review-encode
                      (revu-reload-test--set-reply
                       (revu-fixture-sidecar root "worktree") :null)))
             (message (revu-reload-test--refusal root "worktree" broken)))
        (should (string-match-p "annotations\\[0\\]" message))
        (should (string-match-p "reply" message))))))

(defun revu-reload-test--annotate-another ()
  "Annotate a second line of the rendered worktree diff."
  (revu-fixture-goto-line-matching "alpha five")
  (revu-annotate-line "note" "And this one."))

(ert-deftest revu-reload-blocks-a-mutation-after-an-agent-wrote ()
  "A Sidecar an agent changed blocks the next Annotation and says what to do."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-reload-test--open-worktree root)
      (revu-reload-test--agent-edit
       root "worktree"
       (lambda (review) (revu-reload-test--set-reply review "Because of X.")))
      (let* ((before (revu-fixture-sidecar-text root "worktree"))
             (message (error-message-string
                       (should-error (revu-reload-test--annotate-another)
                                     :type 'revu-sidecar-changed))))
        ;; The message names the way out, and the escape hatch beside it.
        (should (string-match-p "revu-reload" message))
        (should (string-match-p "revu-force-write" message))
        ;; What the agent wrote is still there, whole.
        (should (equal (revu-fixture-sidecar-text root "worktree") before))
        (should (= (seq-length (revu-review-annotations
                                (revu-fixture-sidecar root "worktree")))
                   1))
        (should (equal (revu-annotation-reply
                        (aref (revu-review-annotations
                               (revu-fixture-sidecar root "worktree"))
                              0))
                       "Because of X."))))))

(ert-deftest revu-reload-clears-the-block-and-force-write-overrides-it ()
  "Reload lets the next Annotation through; force-write overwrites instead."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-reload-test--open-worktree root)
      (revu-reload-test--agent-edit
       root "worktree"
       (lambda (review) (revu-reload-test--set-reply review "Because of X.")))
      (revu-reload)
      (revu-reload-test--annotate-another)
      (let ((annotations (revu-review-annotations
                          (revu-fixture-sidecar root "worktree"))))
        (should (= (seq-length annotations) 2))
        ;; The reload kept the agent's Reply, and the new Annotation joined it.
        (should (equal (revu-annotation-reply (aref annotations 0))
                       "Because of X."))))))

(ert-deftest revu-force-write-overwrites-what-the-agent-wrote ()
  "Force-write puts the buffer's Review on disk, agent's edits and all gone."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-reload-test--open-worktree root)
      (revu-reload-test--agent-edit
       root "worktree"
       (lambda (review)
         (revu-reload-test--appended
          (revu-reload-test--set-reply review "Because of X.")
          "change" "Rewrite all of it.")))
      (revu-force-write)
      (let ((annotations (revu-review-annotations
                          (revu-fixture-sidecar root "worktree"))))
        (should (= (seq-length annotations) 1))
        (should-not (revu-annotation-reply (aref annotations 0))))
      ;; The guard is clear again, so the reviewer carries on annotating.
      (revu-reload-test--annotate-another)
      (should (= (seq-length (revu-review-annotations
                              (revu-fixture-sidecar root "worktree")))
                 2)))))

(ert-deftest revu-reload-keeps-point-on-the-line-when-lines-are-added-above-it ()
  "An Annotation the agent put above the reviewer does not move their line.
Reload renders the agent's Annotation under a line above the reviewer's,
which pushes every buffer line below it down.  The reviewer is on the
line, not on the row, and the reload leaves them there."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-reload-test--open-worktree root)
      (revu-fixture-goto-line-matching revu-fixture-worktree-seven)
      (let ((row (line-number-at-pos)))
        (revu-reload-test--agent-edit
         root "worktree"
         (lambda (review)
           (revu-reload-test--appended review "note" "Look at this first."
                                       5 "context")))
        (revu-reload)
        (should (string-match-p revu-fixture-worktree-seven
                                (buffer-substring-no-properties
                                 (line-beginning-position)
                                 (line-end-position))))
        ;; The line is where it was; the row it sits on is not.
        (should (> (line-number-at-pos) row))))))

(provide 'revu-reload-test)
;;; revu-reload-test.el ends here
