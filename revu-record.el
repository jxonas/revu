;;; revu-record.el --- Review, Annotation and Target records  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Jonas Rodrigues

;; Author: Jonas Rodrigues

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; The pure data layer of revu: Reviews, Annotations, Targets and
;; Anchors, plus the JSON encoding they are persisted in.  Nothing here
;; touches the file system; `revu-sidecar.el' owns that.
;;
;; A record is an association list keyed by symbols, in the order the
;; keys appear in the Sidecar.  Reading keeps every key it does not
;; understand and writing emits it again, so a field a later revu adds
;; -- or an agent writes -- survives a round trip through an older one.
;;
;; A Review is `{schema, name, source, created, updated, annotations}'
;; and an Annotation is `{id, kind, target, anchor, body, created,
;; updated}' with an optional `reply'.  The Annotation `id' is a ULID
;; and is the identity: two Annotations may share a Target.  A Target is
;; a tagged object -- `review', `file', `line' or `range' -- tagged the
;; way a Source is, by its `kind' key.

;;; Code:

(require 'seq)
(require 'subr-x)

(defconst revu-schema-version 1
  "The Sidecar schema version this revu writes and understands.
A Sidecar declaring a higher version is refused rather than guessed at.")

(defconst revu-annotation-kinds '("question" "change" "note")
  "The Kinds an Annotation may carry: what the reviewer means by it.")

(defconst revu-target-kinds '("review" "file" "line" "range")
  "The Target kinds an Annotation may be attached to.")

(defconst revu-origins '("added" "removed" "context")
  "Which Origin a Target line carries: which part of a diff it belongs to.")

(defconst revu-source-kinds '("worktree" "staged" "range" "file")
  "The kinds of Source a Review may be taken over.")

(define-error 'revu-invalid-sidecar
  "Invalid revu Sidecar"
  'error)

(defun revu-digest (text)
  "Return the digest of TEXT: lowercase hexadecimal SHA-256, unprefixed.
One named algorithm identifies Anchor content, Reviewed marks and the
contents of a Sidecar alike, so a program reading a Sidecar without
Emacs can recompute any of them."
  (secure-hash 'sha256 text))

;;;; Alists in Sidecar order

(defun revu--put (alist key value)
  "Return ALIST with KEY set to VALUE, keeping the order of its keys.
A key that is already present keeps its position; a new key is appended,
so a record read from a Sidecar is written back in the order it came in."
  (if (assq key alist)
      (mapcar (lambda (pair)
                (if (eq (car pair) key) (cons key value) pair))
              alist)
    (append alist (list (cons key value)))))

(defun revu--put-all (alist pairs)
  "Return ALIST with every key of PAIRS set to its value, in order."
  (let ((result alist))
    (dolist (pair pairs result)
      (setq result (revu--put result (car pair) (cdr pair))))))

;;;; ULIDs

(defconst revu--crockford-alphabet "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
  "Crockford base32 digits, in value order.")

(defvar revu--ulid-previous nil
  "The last ULID `revu-ulid' returned, or nil before the first one.")

(defvar revu--random-seeded nil
  "Non-nil once the random number generator has been seeded for ULIDs.")

(defun revu--base32 (value width)
  "Return VALUE as WIDTH Crockford base32 digits, most significant first."
  (let ((digits nil)
        (remaining value))
    (dotimes (_ width)
      (push (aref revu--crockford-alphabet (mod remaining 32)) digits)
      (setq remaining (/ remaining 32)))
    (apply #'string digits)))

(defun revu--base32-increment (text)
  "Return TEXT, a Crockford base32 string, incremented by one.
Overflow past the leftmost digit wraps, which no realistic ULID reaches."
  (let ((digits (copy-sequence text))
        (index (1- (length text)))
        (carry t))
    (while (and carry (>= index 0))
      (let ((value (1+ (seq-position revu--crockford-alphabet
                                     (aref digits index)))))
        (if (= value 32)
            (aset digits index ?0)
          (aset digits index (aref revu--crockford-alphabet value))
          (setq carry nil)))
      (setq index (1- index)))
    digits))

(defun revu-ulid ()
  "Return a fresh ULID: 26 Crockford base32 digits, uppercase.
The first ten digits are the millisecond the ULID was made, so ULIDs
sort by creation time.  Two ULIDs made in the same millisecond still
sort in the order they were made, which is what keeps the sorted order
of a Sidecar's annotations equal to the order they were appended in."
  (unless revu--random-seeded
    (random t)
    (setq revu--random-seeded t))
  (let* ((milliseconds (truncate (* 1000 (float-time))))
         (tail (mapconcat (lambda (_)
                            (string (aref revu--crockford-alphabet (random 32))))
                          (number-sequence 1 16)
                          ""))
         (ulid (concat (revu--base32 milliseconds 10) tail)))
    (when (and revu--ulid-previous (not (string< revu--ulid-previous ulid)))
      (setq ulid (revu--base32-increment revu--ulid-previous)))
    (setq revu--ulid-previous ulid)))

;;;; Timestamps

(defun revu-timestamp (&optional time)
  "Return TIME as an ISO-8601 UTC timestamp, to the second.
TIME defaults to now.  The result looks like \"2026-08-23T20:52:05Z\"."
  (replace-regexp-in-string
   "\\+0000\\'" "Z" (format-time-string "%FT%T%z" time t)))

;;;; Sources

(defun revu--narrowing (paths)
  "Return the Source fields recording PATHS as a Narrowing, or nil.
PATHS is a list or a vector of git pathspecs.  No pathspecs is no
Narrowing -- the field is left off rather than written empty -- so a
Source nobody narrowed reads exactly as it did before the Narrowing
existed."
  (when (> (length paths) 0)
    `((paths . ,(vconcat paths)))))

(defun revu-source-worktree (base &optional paths)
  "Return the Source of a diff of the worktree against Revision BASE.
PATHS, when given, is the Narrowing the diff is limited to."
  `((kind . "worktree") (base . ,base) ,@(revu--narrowing paths)))

(defun revu-source-staged (base &optional paths)
  "Return the Source of a diff of the index against Revision BASE.
PATHS, when given, is the Narrowing the diff is limited to."
  `((kind . "staged") (base . ,base) ,@(revu--narrowing paths)))

(defun revu-source-range (base head &optional paths)
  "Return the Source of a diff between Revisions BASE and HEAD.
PATHS, when given, is the Narrowing the diff is limited to."
  `((kind . "range") (base . ,base) (head . ,head) ,@(revu--narrowing paths)))

(defun revu-source-file (path)
  "Return the Source of the plain file at repository-relative PATH."
  `((kind . "file") (path . ,path)))

(defun revu-source-kind (source)
  "Return the kind of SOURCE: worktree, staged, range or file."
  (alist-get 'kind source))

(defun revu-source-base (source)
  "Return the base Revision SOURCE was generated from, or nil."
  (alist-get 'base source))

(defun revu-source-head (source)
  "Return the head Revision SOURCE was generated from, or nil."
  (alist-get 'head source))

(defun revu-source-path (source)
  "Return the path of a plain-file SOURCE, or nil."
  (alist-get 'path source))

(defun revu-source-paths (source)
  "Return SOURCE's Narrowing as a list of pathspecs, or nil for none.
A diff Source carrying none spans every path (ADR-0005's amendment)."
  (append (alist-get 'paths source) nil))

(defun revu--slug (path)
  "Return PATH with every character a file name should not carry replaced.
Directory separators and other awkward characters become hyphens."
  (replace-regexp-in-string "[^A-Za-z0-9._]+" "-" path))

(defun revu--narrowing-slug (source)
  "Return the name suffix SOURCE\='s Narrowing adds, or the empty string.
Each pathspec is slugged and hyphen-joined onto the Revisions\=' name,
`main..feature--src-foo--docs\=', in the order the pathspecs were given
(ADR-0005\='s amendment names them in that order).  So the same Narrowing
resumes the same Review, and the full one over the same Revisions is left
alone."
  (mapconcat (lambda (path)
               (concat "--" (string-trim (revu--slug path) "-+" "-+")))
             (revu-source-paths source)
             ""))

(defun revu-review-name-for-source (source)
  "Return the default Review name for SOURCE.
The name is derived, not invented, so that reviewing the same Source
again finds the Review that is already there instead of starting a new
one."
  (pcase (revu-source-kind source)
    ("worktree" (concat "worktree" (revu--narrowing-slug source)))
    ("staged" (concat "staged" (revu--narrowing-slug source)))
    ("range" (concat (revu--slug (format "%s..%s"
                                         (revu-source-base source)
                                         (revu-source-head source)))
                     (revu--narrowing-slug source)))
    ("file" (concat "file-" (revu--slug (revu-source-path source))))
    (kind (signal 'revu-invalid-sidecar (list (format "Unknown Source kind: %s"
                                                      kind))))))

;;;; Targets

(defun revu-target-review ()
  "Return a Target naming the Review as a whole."
  '((kind . "review")))

(defun revu-target-file (path)
  "Return a Target naming the whole file at repository-relative PATH."
  `((kind . "file") (path . ,path)))

(defun revu-target-line (path line &optional origin)
  "Return a Target naming LINE of the file at PATH.
ORIGIN is the Origin the line carries, and is absent for a
plain-file Target, whose Source kind already says there is no diff."
  (append `((kind . "line") (path . ,path) (line . ,line))
          (when origin `((origin . ,origin)))))

(defun revu-target-range (path start end &optional origin)
  "Return a Target naming lines START to END of the file at PATH.
ORIGIN is the Origin the lines carry.  A hunk Annotation
is a range over the hunk, not a Target kind of its own."
  (append `((kind . "range") (path . ,path) (start . ,start) (end . ,end))
          (when origin `((origin . ,origin)))))

(defun revu-target-kind (target)
  "Return the kind of TARGET: review, file, line or range."
  (alist-get 'kind target))

(defun revu-target-path (target)
  "Return the repository-relative path of TARGET, or nil for a Review Target.
The path is recorded when the Annotation is made and is never rewritten,
even after the file it names is renamed."
  (alist-get 'path target))

(defun revu-target-line-number (target)
  "Return the line TARGET names, or nil when it names no single line."
  (alist-get 'line target))

(defun revu-target-start (target)
  "Return the first line of a range TARGET, or nil."
  (alist-get 'start target))

(defun revu-target-end (target)
  "Return the last line of a range TARGET, or nil."
  (alist-get 'end target))

(defun revu-target-origin (target)
  "Return the Origin of TARGET, or nil when it has none."
  (alist-get 'origin target))

;;;; Annotations

(defun revu-annotation-create (kind target body &optional anchor time)
  "Return a new Annotation of KIND on TARGET carrying BODY.
ANCHOR re-locates TARGET after the Source changes; a Review Target has
none.  TIME is the moment the Annotation is made, defaulting to now.
The Annotation's identity is its fresh ULID, so a second Annotation on
the same Target is a different Annotation, not a replacement."
  (unless (member kind revu-annotation-kinds)
    (signal 'revu-invalid-sidecar
            (list (format "Unknown Annotation Kind: %s" kind))))
  (unless (member (revu-target-kind target) revu-target-kinds)
    (signal 'revu-invalid-sidecar
            (list (format "Unknown Target kind: %s" (revu-target-kind target)))))
  (let ((stamp (revu-timestamp time)))
    (append `((id . ,(revu-ulid))
              (kind . ,kind)
              (target . ,target))
            (when anchor `((anchor . ,anchor)))
            `((body . ,body)
              (created . ,stamp)
              (updated . ,stamp)))))

(defun revu-annotation-id (annotation)
  "Return the ULID that identifies ANNOTATION."
  (alist-get 'id annotation))

(defun revu-annotation-kind (annotation)
  "Return the Kind of ANNOTATION: question, change or note."
  (alist-get 'kind annotation))

(defun revu-annotation-target (annotation)
  "Return the Target ANNOTATION is attached to."
  (alist-get 'target annotation))

(defun revu-annotation-anchor (annotation)
  "Return the Anchor of ANNOTATION, or nil when it has none."
  (alist-get 'anchor annotation))

(defun revu-annotation-body (annotation)
  "Return the body the reviewer wrote on ANNOTATION."
  (alist-get 'body annotation))

(defun revu-annotation-reply (annotation)
  "Return the agent's Reply to ANNOTATION, or nil when it is unanswered.
The presence of a Reply is the answered signal; there is no flag."
  (alist-get 'reply annotation))

(defun revu-annotation-created (annotation)
  "Return the timestamp ANNOTATION was made at."
  (alist-get 'created annotation))

(defun revu-annotation-updated (annotation)
  "Return the timestamp ANNOTATION was last changed at."
  (alist-get 'updated annotation))

(defun revu-annotation-update (annotation pairs &optional time)
  "Return ANNOTATION with every key of PAIRS set, and `updated' stamped.
TIME is the moment of the change, defaulting to now.  Keys ANNOTATION
carries that PAIRS does not mention -- including keys revu does not
understand -- are kept."
  (revu--put (revu--put-all annotation pairs)
             'updated (revu-timestamp time)))

(defun revu-annotation-set-body (annotation body &optional time)
  "Return ANNOTATION carrying BODY, stamped as updated at TIME."
  (revu-annotation-update annotation `((body . ,body)) time))

;;;; Reviews

(defun revu-review-create (name source &optional time)
  "Return a new empty Review called NAME over SOURCE, created at TIME.
TIME defaults to now."
  (let ((stamp (revu-timestamp time)))
    `((schema . ,revu-schema-version)
      (name . ,name)
      (source . ,source)
      (created . ,stamp)
      (updated . ,stamp)
      (annotations . []))))

(defun revu-review-name (review)
  "Return the name of REVIEW, which is also its Sidecar's file name."
  (alist-get 'name review))

(defun revu-review-source (review)
  "Return the Source REVIEW is over."
  (alist-get 'source review))

(defun revu-review-annotations (review)
  "Return the Annotations of REVIEW, in ULID order."
  (alist-get 'annotations review))

(defun revu-review-annotation (review id)
  "Return the Annotation of REVIEW identified by ID, or nil."
  (seq-find (lambda (annotation) (equal (revu-annotation-id annotation) id))
            (revu-review-annotations review)))

(defun revu--review-set-annotations (review annotations &optional time)
  "Return REVIEW carrying ANNOTATIONS in ULID order, stamped updated at TIME.
ANNOTATIONS may be any sequence; the Review keeps them as a vector, which
is what a decoded JSON array is."
  (revu--put-all
   review
   `((annotations . ,(vconcat
                      (sort (append annotations nil)
                            (lambda (a b) (string< (revu-annotation-id a)
                                                   (revu-annotation-id b))))))
     (updated . ,(revu-timestamp time)))))

(defun revu-review-add-annotation (review annotation &optional time)
  "Return REVIEW with ANNOTATION added, at TIME."
  (revu--review-set-annotations
   review (append (revu-review-annotations review) (list annotation)) time))

(defun revu-review-replace-annotation (review annotation &optional time)
  "Return REVIEW with the Annotation sharing ANNOTATION's id replaced, at TIME."
  (revu--review-set-annotations
   review
   (mapcar (lambda (existing)
             (if (equal (revu-annotation-id existing)
                        (revu-annotation-id annotation))
                 annotation
               existing))
           (revu-review-annotations review))
   time))

(defun revu-review-remove-annotation (review id &optional time)
  "Return REVIEW without the Annotation identified by ID, at TIME."
  (revu--review-set-annotations
   review
   (seq-remove (lambda (annotation)
                 (equal (revu-annotation-id annotation) id))
               (revu-review-annotations review))
   time))

;;;; Reviewed marks

(defun revu-mark-create (path digest &optional span time)
  "Return a Reviewed mark on PATH asserting that DIGEST was read, at TIME.
TIME defaults to now.  The digest is the mark's identity: the region is
reviewed exactly while its content still hashes to it (ADR-0009).

SPAN is the (START . END) of the base-file lines the region covered when
the mark was taken, END exclusive.  It is locality and not identity: it
says nothing about whether the assertion still holds, and is what lets a
mark that has stopped matching be attributed to the hunk that grew out of
the lines it was taken over.  A plain file needs none -- the path is the
locality -- and a mark taken before revu recorded spans has none."
  (append `((path . ,path) (digest . ,digest))
          (when span `((span . ,(vector (car span) (cdr span)))))
          `((created . ,(revu-timestamp time)))))

(defun revu-mark-path (mark)
  "Return the path MARK was taken on.
The path says which file the reviewer read; it is not the identity, so a
mark still matches content that moved to another path."
  (alist-get 'path mark))

(defun revu-mark-digest (mark)
  "Return the digest of the content MARK asserts was read."
  (alist-get 'digest mark))

(defun revu-mark-span (mark)
  "Return the base-file lines MARK was taken over, as (START . END).
Return nil for a mark that records none: a plain-file mark, whose path is
its locality, and a mark taken before revu recorded spans."
  (let ((span (alist-get 'span mark)))
    (when (and (vectorp span) (equal (length span) 2))
      (cons (aref span 0) (aref span 1)))))

(defun revu-mark-created (mark)
  "Return the timestamp MARK was taken at."
  (alist-get 'created mark))

(defun revu-review-marks (review)
  "Return every Reviewed mark of REVIEW, in the order it was taken.
A Review that has never been marked has none, which reads as the empty
vector rather than as a missing field."
  (or (alist-get 'reviewed review) []))

(defun revu-review-add-mark (review mark &optional time)
  "Return REVIEW carrying MARK as well, at TIME.
Marks are appended in the order they were taken: a mark has no ULID, and
what it asserts does not depend on where in the array it sits."
  (revu--put-all
   review
   `((reviewed . ,(vconcat (revu-review-marks review) (vector mark)))
     (updated . ,(revu-timestamp time)))))

(defun revu-review-remove-marks (review digest &optional time)
  "Return REVIEW without any Reviewed mark asserting DIGEST, at TIME.
Only the marks that match the content the reviewer is looking at are
dropped.  A mark matching nothing on disk is left where it is: it is an
assertion the reviewer made, and reverting the edit that unmatched it
brings the region back as reviewed (ADR-0009)."
  (revu--put-all
   review
   `((reviewed . ,(vconcat (seq-remove (lambda (mark)
                                         (equal (revu-mark-digest mark) digest))
                                       (revu-review-marks review))))
     (updated . ,(revu-timestamp time)))))

;;;; JSON

(defun revu--object-p (value)
  "Return non-nil when VALUE is a decoded JSON object, not an array."
  (and (consp value) (consp (car value)) (symbolp (caar value))))

(defun revu-review-encode (review)
  "Return REVIEW as the JSON text of a Sidecar, newline-terminated.
Records are held in the shape `json-parse-string' decodes them into —
objects as alists, arrays as vectors, JSON null and false as `:null' and
`:false' — so writing one back is a plain serialization and an agent's
value survives whatever type it had."
  (concat (json-serialize review) "\n"))

(defun revu--check (condition message &rest arguments)
  "Signal a `revu-invalid-sidecar' with MESSAGE and ARGUMENTS unless CONDITION."
  (unless condition
    (signal 'revu-invalid-sidecar (list (apply #'format message arguments)))))

(defun revu--validate-annotation (annotation index)
  "Signal unless ANNOTATION, the one at INDEX, is a valid schema v1 record.
The position of the offending record is named in the error, because a
refusal the reviewer cannot act on is a refusal that costs them the
Review."
  (revu--check (revu--object-p annotation)
               "annotations[%d] is not an object" index)
  (dolist (key '(id kind target body created updated))
    (revu--check (assq key annotation)
                 "annotations[%d] has no %s" index key))
  (revu--check (stringp (revu-annotation-id annotation))
               "annotations[%d] has a non-string id" index)
  (revu--check (member (revu-annotation-kind annotation) revu-annotation-kinds)
               "annotations[%d] (%s) has an unknown Kind: %s"
               index (revu-annotation-id annotation)
               (revu-annotation-kind annotation))
  (revu--check (stringp (revu-annotation-body annotation))
               "annotations[%d] (%s) has a non-string body"
               index (revu-annotation-id annotation))
  (let ((reply (revu-annotation-reply annotation)))
    (revu--check (or (null reply) (stringp reply))
                 "annotations[%d] (%s) has a non-string reply"
                 index (revu-annotation-id annotation)))
  (let* ((id (revu-annotation-id annotation))
         (target (revu-annotation-target annotation)))
    (revu--check (revu--object-p target)
                 "annotations[%d] (%s) has no Target object" index id)
    (revu--check (member (revu-target-kind target) revu-target-kinds)
                 "annotations[%d] (%s) has an unknown Target kind: %s"
                 index id (revu-target-kind target))
    ;; A Target that names no line is a Target nothing can be re-anchored
    ;; against, so the shape its kind promises is checked here rather than
    ;; discovered when the reviewer opens the Review.
    (unless (equal (revu-target-kind target) "review")
      (revu--check (stringp (revu-target-path target))
                   "annotations[%d] (%s) has a %s Target with no path"
                   index id (revu-target-kind target)))
    (pcase (revu-target-kind target)
      ("line"
       (revu--check (integerp (revu-target-line-number target))
                    "annotations[%d] (%s) has a line Target with no line" index id))
      ("range"
       (revu--check (and (integerp (revu-target-start target))
                         (integerp (revu-target-end target)))
                    "annotations[%d] (%s) has a range Target with no start and end"
                    index id)))
    (let ((origin (revu-target-origin target)))
      (revu--check (or (null origin) (member origin revu-origins))
                   "annotations[%d] (%s) has an unknown Origin: %s"
                   index id origin))))

(defun revu--validate-mark (mark index)
  "Signal unless MARK, the Reviewed mark at INDEX, is a valid record.
`reviewed' is an additive field and needs no schema bump (ADR-0009), but
a mark revu cannot read the digest of is a mark that would break a render
rather than tell the reviewer anything, so it refuses the Sidecar like
any other malformed record."
  (revu--check (revu--object-p mark) "reviewed[%d] is not an object" index)
  (revu--check (stringp (revu-mark-digest mark))
               "reviewed[%d] has no digest to match content against" index)
  (let ((span (alist-get 'span mark)))
    (revu--check (or (null span)
                     (and (vectorp span) (equal (length span) 2)
                          (integerp (aref span 0)) (integerp (aref span 1))))
                 "reviewed[%d] has a span that is not two line numbers" index)))

(defun revu-review-validate (review)
  "Signal unless REVIEW is a valid schema v1 Review; return REVIEW.
A Sidecar is refused whole: one broken record refuses the file rather
than being dropped, because silently losing an agent's answer is the
failure this format exists to prevent."
  (revu--check (revu--object-p review) "the Sidecar is not a JSON object")
  (let ((schema (alist-get 'schema review)))
    (revu--check (integerp schema) "the Sidecar has no integer schema version")
    (revu--check (<= schema revu-schema-version)
                 "the Sidecar is schema %d; this revu understands schema %d"
                 schema revu-schema-version))
  (revu--check (stringp (revu-review-name review)) "the Sidecar has no name")
  (revu--check (revu--object-p (revu-review-source review))
               "the Sidecar has no Source object")
  (revu--check (member (revu-source-kind (revu-review-source review))
                       revu-source-kinds)
               "the Sidecar has an unknown Source kind: %s"
               (revu-source-kind (revu-review-source review)))
  (let ((paths (alist-get 'paths (revu-review-source review))))
    (revu--check (or (null paths)
                     (and (vectorp paths) (seq-every-p #'stringp paths)))
                 "the Sidecar's Source paths are not an array of pathspecs"))
  (revu--check (vectorp (revu-review-annotations review))
               "the Sidecar's annotations are not an array")
  (let ((index 0))
    (seq-doseq (annotation (revu-review-annotations review))
      (revu--validate-annotation annotation index)
      (setq index (1+ index))))
  (when (assq 'reviewed review)
    (revu--check (vectorp (alist-get 'reviewed review))
                 "the Sidecar's reviewed marks are not an array")
    (let ((index 0))
      (seq-doseq (mark (revu-review-marks review))
        (revu--validate-mark mark index)
        (setq index (1+ index)))))
  review)

(defun revu-review-decode (text)
  "Return the Review encoded in the Sidecar JSON TEXT.
Keys revu does not understand are kept on the record and written back
untouched.  Malformed JSON, a schema newer than this revu, or a record
that is not a valid Annotation refuses the whole text loudly, naming
where the trouble is."
  (let ((review (condition-case error
                    (json-parse-string text
                                       :object-type 'alist
                                       :array-type 'array)
                  (json-error
                   (signal 'revu-invalid-sidecar
                           (list (format "malformed JSON at line %s, column %s"
                                         (nth 0 (cdr error))
                                         (nth 1 (cdr error)))))))))
    (revu-review-validate review)))

(provide 'revu-record)
;;; revu-record.el ends here
