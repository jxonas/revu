;;; revu-export.el --- Export a Review as revdiff markdown  -*- lexical-binding: t; -*-

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

;; The Export writes a Review as the markdown revdiff's agent plugins
;; already read, so those plugins work over a revu Review unchanged
;; (ADR-0001).  The grammar is not revu's to choose: it is whatever
;; revdiff's Go parser accepts, documented in
;; `docs/research/revdiff-export-format.md', and every byte rule here
;; comes from there.
;;
;; The format is poorer than the record, and ADR-0006 fixes the three
;; places it gives way.  Two Annotations on one line are one revdiff
;; record, so their bodies are concatenated rather than one of them being
;; silently replaced on the way back in.  An Annotation on the Review as
;; a whole has no revdiff record at all and is dropped, with the count
;; said out loud rather than smuggled in under a path that does not
;; exist.  And what is written is today's: the path each file now has and
;; the line each Anchor was re-located to, because the agent reading the
;; Export acts on the files as they are.
;;
;; What the reviewer keeps for themselves stays here: Reviewed marks say
;; what the reviewer has read and mean nothing to an agent, so the Export
;; never looks at them.

;;; Code:

(require 'seq)
(require 'subr-x)
(require 'revu-annotate)
(require 'revu-record)
(require 'revu-render)
(require 'revu-sidecar)

;; The review buffer's state lives in `revu.el', which requires this
;; file; naming it here would be a loading cycle.
(defvar revu--sidecar)
(declare-function revu-review "revu")

(defconst revu-export-agent-contract
  "Answer a question by setting that Annotation's reply string.  Append \
your own Annotations with fresh ULIDs.  Delete nothing and reorder \
nothing.  Keep the JSON valid, and preserve every field you do not \
understand."
  "What an agent handed a Review has to be told before it writes to it.
A broken Sidecar comes of an agent that was never told the rules, so the
handoff carries them rather than the path alone (ADR-0007).")

(defconst revu-export--question-openers
  '("explain" "remind" "describe" "what is" "what are" "how does"
    "how do" "clarify")
  "The words revdiff's plugins read as opening a question.
The format carries no Kind, so a `question' has to be recognisable from
its body alone.")

;;;; Bodies

(defun revu-export--question-p (body)
  "Return non-nil when revdiff's plugins would read BODY as a question."
  (let ((text (string-trim-left body)))
    (or (string-match-p "\\?\\?" body)
        (seq-some (lambda (opener) (string-prefix-p opener text t))
                  revu-export--question-openers))))

(defun revu-export--body (annotation)
  "Return the body ANNOTATION contributes to a record.
A `question' Kind is the one thing the format cannot say, so it is said
in the body instead: the `??' the plugins classify on is written in when
the reviewer's own words do not already carry it.  A `change' and a
`note' go out as they were written.  Trailing blank lines are dropped,
which is what revdiff's own editor does to a comment."
  (let ((body (string-trim-right (revu-annotation-body annotation) "\n+")))
    (if (and (equal (revu-annotation-kind annotation) "question")
             (not (revu-export--question-p body)))
        (concat "?? " body)
      body)))

(defun revu-export--escape (body)
  "Return BODY with any line that would open a record pushed out of the way.
A body line whose first non-space content is `## ' would be read back as
a header, so it goes out with one more leading space; the parser takes
exactly one off again.  Only that exact prefix counts, and only spaces
are looked past -- `### x' and `word ## mid' are left alone."
  (mapconcat (lambda (line)
               (if (string-prefix-p "## " (string-trim-left line " +"))
                   (concat " " line)
                 line))
             (split-string body "\n")
             "\n"))

;;;; Records

(defun revu-export--type (origin)
  "Return the revdiff change type of a line with ORIGIN.
A line with no Origin comes from a plain file rather than a diff, and
revdiff has one token for a line that is not a change."
  (pcase origin
    ("added" "+")
    ("removed" "-")
    (_ " ")))

(defun revu-export--record (placement)
  "Return the revdiff record PLACEMENT exports as, or nil when it has none.
A record is (PATH LINE END TYPE BODY): the path the file has today, the
line the Anchor was re-located to, the last line of a range, the change
type, and the body.  An Annotation that was not found again keeps the
line it was recorded on -- the body still says what was meant, and
revdiff never checks that the line is there.  An Annotation on the
Review as a whole has no record: it is the caller's to drop and count."
  (let* ((annotation (revu-render-placement-annotation placement))
         (target (revu-annotation-target annotation))
         (path (revu-render-placement-path placement))
         (type (revu-export--type (revu-render-placement-origin placement)))
         (body (revu-export--body annotation)))
    (pcase (revu-target-kind target)
      ("review" nil)
      ("file" (list path 0 0 nil body))
      ("line" (let ((line (or (revu-render-placement-line placement)
                              (revu-target-line-number target))))
                (list path line line type body)))
      ("range" (let ((start (or (revu-render-placement-line placement)
                                (revu-target-start target)))
                     (end (or (revu-render-placement-end placement)
                              (revu-target-end target))))
                 (list path start (max start end) type body))))))

(defun revu-export--merge (records)
  "Return RECORDS with the ones revdiff cannot tell apart merged into one.
revdiff knows a record by its path, line and change type, and the last
one it reads of a key replaces the ones before it.  Two Annotations on
one line are therefore concatenated, oldest first and separated by a
blank line, and the merged record covers the widest range any of them
drew.  Emitting both would silently lose one on the way back in
\(ADR-0006)."
  (let ((merged nil))
    (dolist (record records)
      (let* ((key (list (nth 0 record) (nth 1 record) (nth 3 record)))
             (cell (assoc key merged)))
        (if (null cell)
            (push (cons key record) merged)
          (let ((standing (cdr cell)))
            (setcdr cell (list (nth 0 record)
                               (nth 1 record)
                               (max (nth 2 record) (nth 2 standing))
                               (nth 3 record)
                               (concat (nth 4 standing) "\n\n"
                                       (nth 4 record))))))))
    (mapcar #'cdr (nreverse merged))))

(defun revu-export--sort (records)
  "Return RECORDS in the order revdiff writes them.
Paths compare as bytes, and inside one path the records run by line with
the file-level one, numbered zero, first."
  (sort records
        (lambda (a b)
          (let ((first (encode-coding-string (nth 0 a) 'utf-8 t))
                (second (encode-coding-string (nth 0 b) 'utf-8 t)))
            (if (string= first second)
                (< (nth 1 a) (nth 1 b))
              (string< first second))))))

(defun revu-export--header (record)
  "Return the line that opens RECORD.
A range says its last line only when there is more than one: a run of
one degrades to the plain shape, as revdiff's own writer makes it."
  (let ((path (nth 0 record))
        (line (nth 1 record))
        (end (nth 2 record))
        (type (nth 3 record)))
    (cond ((= line 0) (format "## %s (file-level)" path))
          ((> end line) (format "## %s:%d-%d (%s)" path line end type))
          (t (format "## %s:%d (%s)" path line type)))))

;;;; The Export itself

(defun revu-export-dropped (placements)
  "Return how many of PLACEMENTS revdiff has no record for.
That is the Annotations on the Review as a whole: revdiff's parser
refuses anything before the first header, and a header naming a file
that does not exist would poison the agent reading it."
  (seq-count (lambda (placement)
               (equal (revu-target-kind
                       (revu-annotation-target
                        (revu-render-placement-annotation placement)))
                      "review"))
             placements))

(defun revu-export-text (placements)
  "Return the revdiff markdown PLACEMENTS export as.
Each record is its header, a newline, its body and a newline, and one
blank line separates one from the next; there is none before the first
or after the last, so the text ends in a single newline.  A Review with
nothing revdiff can carry is the empty string rather than a blank
line -- every plugin reads empty as `no annotations, review complete'."
  (let ((records (revu-export--sort
                  (revu-export--merge
                   (delq nil (mapcar #'revu-export--record placements))))))
    (mapconcat (lambda (record)
                 (concat (revu-export--header record) "\n"
                         (revu-export--escape (nth 4 record)) "\n"))
               records
               "\n")))

(defun revu-export--sidecar-file ()
  "Return the Sidecar file of the current review buffer.
Asking for the Review first is what refuses a buffer that is not one."
  (revu-review)
  (revu-sidecar-file revu--sidecar))

(defun revu-export--hand-off (path &optional note)
  "Put PATH and the agent contract on the kill ring, and echo them.
That pair is the whole handoff: where the file is, and what an agent
writing to it may do.  NOTE, when there is one, is echoed above them and
kept off the kill ring."
  (let ((text (concat path "\n\n" revu-export-agent-contract)))
    (kill-new text)
    ;; NOTE is echoed with the handoff rather than before it.  A separate
    ;; `message' would be wiped from the echo area by this one inside the
    ;; same command, which is no way to tell a reviewer their feedback was
    ;; dropped.  Only the path and the contract go to the kill ring.
    (message "%s" (if note (concat note "\n\n" text) text))
    text))

;;;###autoload
(defun revu-export (&optional destination)
  "Write this Review as revdiff markdown, and hand the file to an agent.
DESTINATION is the file to write; interactively a prefix argument asks
for one, and otherwise it is `.revu/<review>.md', beside the Sidecar and
overwritten every time.  Return the file written, or nil when the Review
says nothing revdiff can carry -- an empty Export is no file at all,
because every plugin reads an empty one as a review with nothing to say."
  (interactive (list (when current-prefix-arg
                       (read-file-name "Export the Review to: "))))
  (let* ((placements (revu-annotate-placements (revu-review) default-directory))
         (dropped (revu-export-dropped placements))
         (text (revu-export-text placements))
         (file (expand-file-name
                (or destination
                    (concat (file-name-sans-extension
                             (revu-export--sidecar-file))
                            ".md")))))
    (let ((note (when (> dropped 0)
                  (format "Dropped %d Annotation%s on the Review itself: \
revdiff carries nothing that is not about a file"
                          dropped (if (= dropped 1) "" "s")))))
      (if (string-empty-p text)
          (progn
            ;; An earlier Export of this Review is now a lie -- the
            ;; feedback it carries has been withdrawn -- and an agent
            ;; handed the path would act on it.  Leaving no file is the
            ;; truthful empty Export, so a stale one has to go.
            (when (file-exists-p file)
              (delete-file file))
            (message "%sThis Review says nothing revdiff can carry; \
nothing was written"
                     (if note (concat note ".  ") ""))
            nil)
        (let ((coding-system-for-write 'utf-8-unix))
          (write-region text nil file nil 'silent))
        (revu-export--hand-off file note)
        file))))

;;;###autoload
(defun revu-sidecar-path ()
  "Hand this Review's Sidecar to an agent: its path and the contract.
The Sidecar is the richer of the two things a reviewer can hand over --
it carries every Annotation, and it is where an agent writes its Reply."
  (interactive)
  (revu-export--hand-off (expand-file-name (revu-export--sidecar-file))))

(provide 'revu-export)
;;; revu-export.el ends here
