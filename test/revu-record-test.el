;;; revu-record-test.el --- Tests for revu records and Sidecar I/O  -*- lexical-binding: t; -*-

;;; Commentary:

;; Tests the Record and Sidecar layers at the file boundary: build a
;; Review programmatically, mutate it, write it, and read the JSON back
;; from disk with a plain JSON parser.  Nothing here asserts on revu's
;; in-memory shapes; the on-disk Sidecar is the contract agents read and
;; therefore the contract these tests hold revu to.

;;; Code:

(require 'ert)
(require 'revu)
(require 'revu-anchor)
(require 'revu-record)
(require 'revu-sidecar)
(require 'revu-fixture)

(defun revu-record-test--json (file)
  "Return the JSON in FILE parsed with a plain parser, arrays as vectors."
  (with-temp-buffer
    (insert-file-contents file)
    (json-parse-string (buffer-string) :object-type 'alist)))

(defun revu-record-test--annotation (review index)
  "Return the parsed annotation at INDEX of the Sidecar JSON REVIEW."
  (aref (alist-get 'annotations review) index))

(defmacro revu-record-test--with-sidecar (root file &rest body)
  "Bind ROOT to a fixture repository and FILE to a Sidecar path under it.
The directory is made, which naming the Sidecar no longer does: a test
that writes one by hand writes where revu would have."
  (declare (indent 2))
  `(revu-fixture-with-repo ,root
     (let ((,file (revu-sidecar-file-name "worktree" ,root)))
       (make-directory (file-name-directory ,file) t)
       ,@body)))

(ert-deftest revu-sidecar-round-trips-a-review-through-disk ()
  "A Review written to its Sidecar reads back equal, in schema v1 shape."
  (revu-record-test--with-sidecar root file
    (let* ((review (revu-review-create
                    "worktree" (revu-source-worktree "HEAD")))
           (handle (revu-sidecar-open file review)))
      (revu-sidecar-write
       handle
       (revu-review-add-annotation
        (revu-sidecar-review handle)
        (revu-annotation-create
         "question"
         (revu-target-line "alpha.txt" 3 "added")
         "Why three?")))
      (let* ((json (revu-record-test--json file))
             (annotation (revu-record-test--annotation json 0)))
        (should (equal (alist-get 'schema json) 1))
        (should (equal (alist-get 'name json) "worktree"))
        (should (equal (alist-get 'kind (alist-get 'source json)) "worktree"))
        (should (equal (alist-get 'base (alist-get 'source json)) "HEAD"))
        (should (equal (alist-get 'kind annotation) "question"))
        (should (equal (alist-get 'body annotation) "Why three?"))
        (should (equal (alist-get 'kind (alist-get 'target annotation)) "line"))
        (should (equal (alist-get 'path (alist-get 'target annotation)) "alpha.txt"))
        (should (equal (alist-get 'line (alist-get 'target annotation)) 3))
        (should (equal (alist-get 'origin (alist-get 'target annotation)) "added")))
      ;; Re-reading the Sidecar yields the same Review the writer held.
      (should (equal (revu-sidecar-review (revu-sidecar-load file))
                     (revu-sidecar-review handle))))))

(ert-deftest revu-sidecar-keeps-fields-it-does-not-understand ()
  "Fields revu has no use for survive a read, a mutation and a write.
The `reviewed' array is the case that matters: it is additive and lands
in a later revu, and this one must carry it rather than eat it."
  (revu-record-test--with-sidecar root file
    (let ((text "{\"schema\":1,\"name\":\"worktree\",\
\"source\":{\"kind\":\"worktree\",\"base\":\"HEAD\",\"future\":\"kept\"},\
\"created\":\"2026-08-23T10:00:00Z\",\"updated\":\"2026-08-23T10:00:00Z\",\
\"reviewed\":[{\"path\":\"alpha.txt\",\"digest\":\"abc\",\
\"created\":\"2026-08-23T10:00:00Z\"}],\
\"annotations\":[{\"id\":\"01AAAAAAAAAAAAAAAAAAAAAAAA\",\"kind\":\"note\",\
\"target\":{\"kind\":\"file\",\"path\":\"beta.txt\"},\"body\":\"kept\",\
\"created\":\"2026-08-23T10:00:00Z\",\"updated\":\"2026-08-23T10:00:00Z\",\
\"agent_hint\":\"kept too\"}]}\n"))
      (write-region text nil file nil 'silent)
      (let ((handle (revu-sidecar-load file)))
        (revu-sidecar-write
         handle
         (revu-review-add-annotation
          (revu-sidecar-review handle)
          (revu-annotation-create "change" (revu-target-file "beta.txt") "New"))))
      (let ((json (revu-record-test--json file)))
        (should (equal (alist-get 'reviewed json)
                       (vector '((path . "alpha.txt")
                                 (digest . "abc")
                                 (created . "2026-08-23T10:00:00Z")))))
        (should (equal (alist-get 'future (alist-get 'source json)) "kept"))
        (should (equal (alist-get 'agent_hint
                                  (revu-record-test--annotation json 0))
                       "kept too"))
        (should (equal (length (alist-get 'annotations json)) 2))))))

(ert-deftest revu-sidecar-keeps-the-types-of-fields-it-does-not-understand ()
  "An unknown field keeps its JSON type, not just its presence.
A `reviewed' mark carrying a boolean, or an agent writing null or an
empty object, has to come back the shape it went in: rewriting the whole
file on every mutation means a type revu flattens is a type revu loses."
  (revu-record-test--with-sidecar root file
    (let ((text "{\"schema\":1,\"name\":\"worktree\",\
\"source\":{\"kind\":\"worktree\",\"base\":\"HEAD\"},\
\"created\":\"2026-08-23T10:00:00Z\",\"updated\":\"2026-08-23T10:00:00Z\",\
\"reviewed\":[{\"digest\":\"abc\",\"collapsed\":false,\"note\":null}],\
\"meta\":{},\"tags\":[],\"deep\":{\"nested\":true},\
\"annotations\":[]}\n"))
      (write-region text nil file nil 'silent)
      (let ((handle (revu-sidecar-load file)))
        (revu-sidecar-write
         handle
         (revu-review-add-annotation
          (revu-sidecar-review handle)
          (revu-annotation-create "note" (revu-target-file "beta.txt") "New"))))
      (let* ((json (revu-record-test--json file))
             (mark (aref (alist-get 'reviewed json) 0)))
        (should (eq (alist-get 'collapsed mark) :false))
        (should (eq (alist-get 'note mark) :null))
        (should (equal (alist-get 'meta json) nil))
        (should (equal (alist-get 'tags json) []))
        (should (eq (alist-get 'nested (alist-get 'deep json)) t))
        ;; The bytes of every field revu does not own are the bytes it read.
        (with-temp-buffer
          (insert-file-contents file)
          (should (string-search "\"collapsed\":false" (buffer-string)))
          (should (string-search "\"note\":null" (buffer-string)))
          (should (string-search "\"meta\":{}" (buffer-string)))
          (should (string-search "\"tags\":[]" (buffer-string))))))))

(ert-deftest revu-sidecar-allows-a-write-after-a-rewrite-with-the-same-bytes ()
  "A file rewritten with the bytes it already had has not changed.
The digest is in the guard precisely so that a touch, or a checkout that
restores what was already there, does not cost the reviewer a reload."
  (revu-record-test--with-sidecar root file
    (let ((handle (revu-sidecar-open
                   file (revu-review-create
                         "worktree" (revu-source-worktree "HEAD")))))
      (revu-sidecar-write
       handle
       (revu-review-add-annotation
        (revu-sidecar-review handle)
        (revu-annotation-create "note" (revu-target-file "alpha.txt") "First")))
      (let ((bytes (with-temp-buffer
                     (insert-file-contents file)
                     (buffer-string))))
        ;; Same bytes, later modification time — what a checkout leaves behind.
        (write-region bytes nil file nil 'silent)
        (set-file-times file (time-add (current-time) 2))
        (should-not (revu-sidecar-changed-p handle))
        (revu-sidecar-write
         handle
         (revu-review-add-annotation
          (revu-sidecar-review handle)
          (revu-annotation-create "note" (revu-target-file "alpha.txt") "Second")))
        (should (equal (length (alist-get 'annotations
                                          (revu-record-test--json file)))
                       2))))))

(ert-deftest revu-sidecar-refuses-a-target-that-names-no-line ()
  "A Target whose kind promises a line and does not carry one is refused.
Nothing can re-anchor such a record, so it is a broken record and the
Sidecar it sits in is refused whole, like any other."
  (revu-record-test--with-sidecar root file
    (dolist (case '(("{\"kind\":\"line\",\"path\":\"a.txt\"}" . "no line")
                    ("{\"kind\":\"range\",\"path\":\"a.txt\",\"start\":3}" . "no start and end")
                    ("{\"kind\":\"line\",\"line\":3}" . "no path")
                    ("{\"kind\":\"line\",\"path\":\"a.txt\",\"line\":3,\"origin\":\"sideways\"}"
                     . "unknown Origin")))
      (let ((text (format "{\"schema\":1,\"name\":\"worktree\",\
\"source\":{\"kind\":\"worktree\",\"base\":\"HEAD\"},\
\"created\":\"2026-08-23T10:00:00Z\",\"updated\":\"2026-08-23T10:00:00Z\",\
\"annotations\":[{\"id\":\"01AAAAAAAAAAAAAAAAAAAAAAAA\",\"kind\":\"note\",\
\"target\":%s,\"body\":\"b\",\
\"created\":\"2026-08-23T10:00:00Z\",\"updated\":\"2026-08-23T10:00:00Z\"}]}\n"
                          (car case))))
        (write-region text nil file nil 'silent)
        (let ((error (should-error (revu-sidecar-load file)
                                   :type 'revu-invalid-sidecar)))
          (should (string-search (cdr case) (cadr error))))))))

(ert-deftest revu-sidecar-keeps-annotations-in-ulid-order ()
  "Annotations are stored in ULID order, which is the order they were made."
  (revu-record-test--with-sidecar root file
    (let ((handle (revu-sidecar-open
                   file (revu-review-create
                         "worktree" (revu-source-worktree "HEAD"))))
          (bodies '("first" "second" "third" "fourth" "fifth")))
      (dolist (body bodies)
        (revu-sidecar-write
         handle
         (revu-review-add-annotation
          (revu-sidecar-review handle)
          (revu-annotation-create "note" (revu-target-review) body))))
      (let* ((json (revu-record-test--json file))
             (annotations (append (alist-get 'annotations json) nil)))
        (should (equal (mapcar (lambda (a) (alist-get 'body a)) annotations)
                       bodies))
        (should (equal (mapcar (lambda (a) (alist-get 'id a)) annotations)
                       (sort (mapcar (lambda (a) (alist-get 'id a)) annotations)
                             #'string<)))))))

(ert-deftest revu-sidecar-writes-iso-8601-utc-timestamps ()
  "Timestamps in a Sidecar are ISO-8601 UTC to the second."
  (revu-record-test--with-sidecar root file
    (let ((handle (revu-sidecar-open
                   file (revu-review-create
                         "worktree" (revu-source-worktree "HEAD")))))
      (revu-sidecar-write
       handle
       (revu-review-add-annotation
        (revu-sidecar-review handle)
        (revu-annotation-create "note" (revu-target-review) "When?")))
      (let ((json (revu-record-test--json file))
            (shape (rx string-start
                       (= 4 digit) "-" (= 2 digit) "-" (= 2 digit) "T"
                       (= 2 digit) ":" (= 2 digit) ":" (= 2 digit) "Z"
                       string-end)))
        (should (string-match-p shape (alist-get 'created json)))
        (should (string-match-p shape (alist-get 'updated json)))
        (should (string-match-p
                 shape
                 (alist-get 'created (revu-record-test--annotation json 0))))))))

(ert-deftest revu-review-name-derives-from-the-source ()
  "The default Review name is derived from the Source, not invented."
  (should (equal (revu-review-name-for-source (revu-source-worktree "HEAD"))
                 "worktree"))
  (should (equal (revu-review-name-for-source (revu-source-staged "HEAD"))
                 "staged"))
  (should (equal (revu-review-name-for-source
                  (revu-source-range "main" "feature"))
                 "main..feature"))
  (should (equal (revu-review-name-for-source
                  (revu-source-range "main" "topic/one"))
                 "main..topic-one"))
  (should (equal (revu-review-name-for-source (revu-source-file "src/alpha.txt"))
                 "file-src-alpha.txt")))

(ert-deftest revu-review-name-tells-a-worktree-base-apart ()
  "A worktree taken against a Revision is its own Review, HEAD keeps its own.
The name of the worktree against HEAD ignores the commit, so the Review
does not fork every time HEAD moves; a worktree against anything else
carries the Revision as the reviewer named it, so it never resumes that
Review by mistake."
  (should (equal (revu-review-name-for-source (revu-source-worktree nil))
                 "worktree"))
  (should (equal (revu-review-name-for-source (revu-source-worktree "HEAD"))
                 "worktree"))
  (should (equal (revu-review-name-for-source
                  (revu-source-worktree "qa-2026-08-17"))
                 "worktree-vs-qa-2026-08-17"))
  (should (equal (revu-review-name-for-source
                  (revu-source-worktree "topic/one"))
                 "worktree-vs-topic-one"))
  (should-not (equal (revu-review-name-for-source
                      (revu-source-worktree "qa-2026-08-17"))
                     (revu-review-name-for-source
                      (revu-source-worktree nil)))))

(defun revu-record-test--refusal (file text)
  "Write TEXT to FILE, load it expecting a refusal, and return the message."
  (write-region text nil file nil 'silent)
  (let ((error-data (should-error (revu-sidecar-load file) :type 'error)))
    (should (eq (car error-data) 'revu-invalid-sidecar))
    (should (equal (revu-fixture-file-contents (file-name-directory file)
                                               (file-name-nondirectory file))
                   text))
    (format "%s" (cadr error-data))))

(ert-deftest revu-sidecar-refuses-malformed-json-and-says-where ()
  "Malformed JSON refuses the whole Sidecar, naming where it broke."
  (revu-record-test--with-sidecar root file
    (let ((message (revu-record-test--refusal
                    file "{\"schema\": 1,\n \"name\": }\n")))
      (should (string-match-p "line 2, column [0-9]+\\'" message)))))

(ert-deftest revu-sidecar-refuses-a-schema-it-does-not-understand ()
  "A Sidecar written by a newer revu is refused rather than guessed at."
  (revu-record-test--with-sidecar root file
    (let ((message (revu-record-test--refusal
                    file "{\"schema\":2,\"name\":\"worktree\",\
\"source\":{\"kind\":\"worktree\"},\"created\":\"2026-08-23T10:00:00Z\",\
\"updated\":\"2026-08-23T10:00:00Z\",\"annotations\":[]}\n")))
      (should (string-match-p "schema 2" message)))))

(ert-deftest revu-sidecar-refuses-a-whole-file-for-one-broken-record ()
  "One invalid Annotation refuses the Sidecar; no record is salvaged."
  (revu-record-test--with-sidecar root file
    (let ((message (revu-record-test--refusal
                    file "{\"schema\":1,\"name\":\"worktree\",\
\"source\":{\"kind\":\"worktree\"},\"created\":\"2026-08-23T10:00:00Z\",\
\"updated\":\"2026-08-23T10:00:00Z\",\"annotations\":[\
{\"id\":\"01AAAAAAAAAAAAAAAAAAAAAAAA\",\"kind\":\"note\",\
\"target\":{\"kind\":\"file\",\"path\":\"a\"},\"body\":\"fine\",\
\"created\":\"2026-08-23T10:00:00Z\",\"updated\":\"2026-08-23T10:00:00Z\"},\
{\"id\":\"01BBBBBBBBBBBBBBBBBBBBBBBB\",\"kind\":\"shout\",\
\"target\":{\"kind\":\"file\",\"path\":\"b\"},\"body\":\"broken\",\
\"created\":\"2026-08-23T10:00:00Z\",\"updated\":\"2026-08-23T10:00:00Z\"}]}\n")))
      (should (string-match-p "annotations\\[1\\]" message))
      (should (string-match-p "shout" message)))))

(ert-deftest revu-sidecar-refusal-keeps-the-last-good-review-in-memory ()
  "A broken Sidecar leaves the open Review and the file on disk alone."
  (revu-record-test--with-sidecar root file
    (let* ((handle (revu-sidecar-open
                    file (revu-review-create
                          "worktree" (revu-source-worktree "HEAD")))))
      (revu-sidecar-write
       handle
       (revu-review-add-annotation
        (revu-sidecar-review handle)
        (revu-annotation-create "note" (revu-target-review) "Last good")))
      (let ((good (revu-sidecar-review handle))
            (broken "{\"schema\":1,\"name\":\n"))
        (write-region broken nil file nil 'silent)
        (should-error (revu-sidecar-reload handle) :type 'revu-invalid-sidecar)
        ;; The Review revu holds is untouched, and so is the broken file.
        (should (equal (revu-sidecar-review handle) good))
        (should (equal (revu-fixture-file-contents root ".revu/reviews/worktree.json")
                       broken))))))

(defun revu-record-test--open (file)
  "Open the Sidecar at FILE on a fresh worktree Review over HEAD."
  (revu-sidecar-open file (revu-review-create
                           "worktree" (revu-source-worktree "HEAD"))))

(defun revu-record-test--annotate (handle body)
  "Add an Annotation carrying BODY to HANDLE's Review and write it."
  (revu-sidecar-write
   handle
   (revu-review-add-annotation
    (revu-sidecar-review handle)
    (revu-annotation-create "note" (revu-target-review) body))))

(ert-deftest revu-sidecar-blocks-writes-after-an-outside-change ()
  "A Sidecar changed on disk blocks writes until it is reloaded."
  (revu-record-test--with-sidecar root file
    (let ((handle (revu-record-test--open file)))
      (revu-record-test--annotate handle "Mine")
      ;; An agent answers the Annotation and appends one of its own.
      (let ((agent (revu-review-add-annotation
                    (revu-sidecar-review handle)
                    (revu-annotation-create
                     "note" (revu-target-review) "From the agent"))))
        (write-region (revu-review-encode agent) nil file nil 'silent))
      (let ((blocked (should-error
                      (revu-record-test--annotate handle "Blocked")
                      :type 'error)))
        (should (eq (car blocked) 'revu-sidecar-changed))
        (should (string-match-p "reload" (format "%s" (cadr blocked)))))
      ;; The agent's work is still on disk: the blocked write wrote nothing.
      (should (equal (length (alist-get 'annotations
                                        (revu-record-test--json file)))
                     2))
      ;; Reloading clears the block and keeps what the agent wrote.
      (revu-sidecar-reload handle)
      (revu-record-test--annotate handle "After the reload")
      (let ((bodies (mapcar (lambda (a) (alist-get 'body a))
                            (append (alist-get 'annotations
                                               (revu-record-test--json file))
                                    nil))))
        (should (member "From the agent" bodies))
        (should (member "After the reload" bodies))))))

(ert-deftest revu-sidecar-force-write-overwrites-an-outside-change ()
  "Force-write is the deliberate way past the guard, and it overwrites."
  (revu-record-test--with-sidecar root file
    (let ((handle (revu-record-test--open file)))
      (revu-record-test--annotate handle "Mine")
      (write-region "{\"schema\":1,\"name\":\"worktree\",\
\"source\":{\"kind\":\"worktree\"},\"created\":\"2026-08-23T10:00:00Z\",\
\"updated\":\"2026-08-23T10:00:00Z\",\"annotations\":[]}\n"
                    nil file nil 'silent)
      (should-error (revu-record-test--annotate handle "Blocked") :type 'error)
      (revu-sidecar-force-write handle (revu-sidecar-review handle))
      (let ((json (revu-record-test--json file)))
        (should (equal (alist-get 'body (revu-record-test--annotation json 0))
                       "Mine")))
      ;; The guard is clear again after a force-write.
      (revu-record-test--annotate handle "And on")
      (should (equal (length (alist-get 'annotations
                                        (revu-record-test--json file)))
                     2)))))

(ert-deftest revu-sidecar-open-resumes-an-existing-review ()
  "Opening a Source that already has a Sidecar resumes it, never clobbers it."
  (revu-record-test--with-sidecar root file
    (revu-record-test--annotate (revu-record-test--open file) "Yesterday")
    (let ((handle (revu-record-test--open file)))
      (should (equal (mapcar #'revu-annotation-body
                             (revu-review-annotations
                              (revu-sidecar-review handle)))
                     '("Yesterday")))
      (revu-record-test--annotate handle "Today")
      (should (equal (mapcar (lambda (a) (alist-get 'body a))
                             (append (alist-get 'annotations
                                                (revu-record-test--json file))
                                     nil))
                     '("Yesterday" "Today"))))))

(ert-deftest revu-sidecar-records-an-edit-and-a-deletion ()
  "Editing a body and deleting an Annotation land on disk as they are made."
  (revu-record-test--with-sidecar root file
    (let ((handle (revu-record-test--open file)))
      (revu-record-test--annotate handle "First")
      (revu-record-test--annotate handle "Second")
      (let* ((review (revu-sidecar-review handle))
             (first (seq-elt (revu-review-annotations review) 0))
             (second (seq-elt (revu-review-annotations review) 1)))
        (revu-sidecar-write
         handle
         (revu-review-replace-annotation
          review (revu-annotation-set-body first "First, rewritten")))
        (should (equal (alist-get 'body (revu-record-test--annotation
                                         (revu-record-test--json file) 0))
                       "First, rewritten"))
        (revu-sidecar-write
         handle
         (revu-review-remove-annotation
          (revu-sidecar-review handle) (revu-annotation-id second)))
        (let ((json (revu-record-test--json file)))
          (should (equal (length (alist-get 'annotations json)) 1))
          (should (equal (alist-get 'id (revu-record-test--annotation json 0))
                         (revu-annotation-id first))))))))

(ert-deftest revu-sidecar-file-carries-no-derived-state ()
  "Anchor state and path resolution are derived on load, never persisted."
  (revu-record-test--with-sidecar root file
    (let ((handle (revu-record-test--open file)))
      (revu-sidecar-write
       handle
       (revu-review-add-annotation
        (revu-sidecar-review handle)
        (revu-annotation-create
         "change" (revu-target-range "alpha.txt" 3 5 "added") "Rework this"
         (revu-anchor-create-range
          (revu-fixture-file-contents root "alpha.txt") 3 5))))
      (let* ((text (revu-fixture-file-contents root ".revu/reviews/worktree.json"))
             (anchor (alist-get 'anchor (revu-record-test--annotation
                                         (revu-record-test--json file) 0))))
        (should (equal (alist-get 'line (alist-get 'start anchor))
                       "alpha three"))
        (should (equal (alist-get 'count anchor) 3))
        (should (equal (alist-get 'digest anchor)
                       (revu-digest (revu-fixture-file-contents
                                     root "alpha.txt"))))
        (should-not (string-match-p "\"state\"" text))
        (should-not (string-match-p "\"resolution\"" text))
        (should-not (string-match-p "\"author\"" text))))))

(provide 'revu-record-test)
;;; revu-record-test.el ends here
