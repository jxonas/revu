;;; revu-anchor.el --- Anchors that re-locate an Annotation in file content  -*- lexical-binding: t; -*-

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

;; An Anchor is what lets an Annotation survive its file being edited.
;; It records the annotated line verbatim, three lines of context on each
;; side, and a digest of the file the line was read from; a range Anchor
;; records both endpoints that way plus the number of lines between them.
;;
;; Re-location searches file *content*, never the diff: a diff's line
;; offsets are regenerated on every `git diff', while a line's text and
;; its neighbours survive a rebase (ADR-0003).  The ladder runs in one
;; order:
;;
;;   1. the file digest still matches, so the recorded number is trusted;
;;   2. the same line text, nearest the recorded number;
;;   3. the same line text ignoring leading and trailing whitespace;
;;   4. the context window, when the line itself was rewritten.
;;
;; Ambiguity orphans rather than guesses: two candidates the same
;; distance from the recorded number, or a context window that matches in
;; more than one place, leave the Annotation orphaned.  Rungs two to four
;; look no further than `revu-anchor-search-radius' lines away.
;;
;; Everything here is a pure function of content passed in as a string.
;; Nothing reads a file, runs git or touches a buffer, so the ladder is
;; testable exactly as it runs.  The state it derives -- `fresh', `moved'
;; or `orphaned' -- is derived on every load and never persisted, because
;; a stored state is a lie as soon as the file is edited outside Emacs.

;;; Code:

(require 'seq)
(require 'subr-x)
(require 'revu-record)

;; The `revu' customization group is defined in `revu.el', which is
;; loaded after this file; a group is only a symbol either way.
(defcustom revu-anchor-search-radius 500
  "How far from its recorded line revu looks for a moved Annotation.
This governs only the degraded path: when the file digest still matches,
the recorded line number is trusted however large the file is."
  :type 'natnum
  :group 'revu)

(defconst revu-anchor-context-lines 3
  "How many lines of context an Anchor records on each side.
Fixed rather than configurable, and baked into the record: an agent
reading a Sidecar must be able to interpret it with no Emacs
configuration at all (ADR-0003).")

;;;; Anchors as records

(defun revu-anchor--lines (content)
  "Return the lines of CONTENT, without the empty line its last newline ends."
  (let ((lines (split-string content "\n")))
    (if (and (cdr lines) (equal (car (last lines)) ""))
        (butlast lines)
      lines)))

(defun revu-anchor--slice (lines from to)
  "Return the 1-based lines FROM to TO of LINES, as a vector.
Line numbers outside LINES contribute nothing, so a line near either edge
of the file records the context that is there rather than padding."
  (vconcat (seq-subseq lines (max 0 (1- from))
                       (min (length lines) (max 0 to)))))

(defun revu-anchor--point (lines number)
  "Return the Anchor point for the 1-based line NUMBER of LINES."
  `((line . ,(nth (1- number) lines))
    (before . ,(revu-anchor--slice lines
                                   (- number revu-anchor-context-lines)
                                   (1- number)))
    (after . ,(revu-anchor--slice lines
                                  (1+ number)
                                  (+ number revu-anchor-context-lines)))))

(defun revu-anchor-create (content line)
  "Return the Anchor for the 1-based LINE of CONTENT.
CONTENT is the whole content of the file the line was read from -- the
base blob, for a Target on a removed line -- and it is what the Anchor's
digest covers."
  (append (revu-anchor--point (revu-anchor--lines content) line)
          `((digest . ,(revu-digest content)))))

(defun revu-anchor-create-range (content start end)
  "Return the Anchor for lines START to END of CONTENT.
The endpoints are anchored independently, so a range whose middle is
rewritten still re-locates; the line count records how long the range
was when the reviewer drew it."
  (let ((lines (revu-anchor--lines content)))
    `((start . ,(revu-anchor--point lines start))
      (end . ,(revu-anchor--point lines end))
      (count . ,(1+ (- end start)))
      (digest . ,(revu-digest content)))))

(defun revu-anchor-line (anchor)
  "Return the line text ANCHOR recorded, without its newline."
  (alist-get 'line anchor))

(defun revu-anchor-before (anchor)
  "Return the lines of context ANCHOR recorded before its line."
  (alist-get 'before anchor))

(defun revu-anchor-after (anchor)
  "Return the lines of context ANCHOR recorded after its line."
  (alist-get 'after anchor))

(defun revu-anchor-digest (anchor)
  "Return the digest of the file content ANCHOR was taken in."
  (alist-get 'digest anchor))

(defun revu-anchor-start (anchor)
  "Return the Anchor point for the first line of the range ANCHOR covers."
  (alist-get 'start anchor))

(defun revu-anchor-end (anchor)
  "Return the Anchor point for the last line of the range ANCHOR covers."
  (alist-get 'end anchor))

(defun revu-anchor-count (anchor)
  "Return how many lines the range ANCHOR covered when it was made."
  (alist-get 'count anchor))

(defun revu-anchor-range-p (anchor)
  "Return non-nil when ANCHOR anchors a range rather than a single line."
  (and (assq 'start anchor) t))

;;;; The ladder

(defun revu-anchor--candidates (lines number predicate)
  "Return the 1-based lines of LINES satisfying PREDICATE, nearest NUMBER first.
Lines further from NUMBER than `revu-anchor-search-radius' are not
looked at: a match on the far side of a large file is a coincidence,
not the reviewer's line."
  (let ((found nil)
        (index 0))
    (dolist (line lines)
      (setq index (1+ index))
      (when (and (<= (abs (- index number)) revu-anchor-search-radius)
                 (funcall predicate line index))
        (push index found)))
    (sort (nreverse found)
          (lambda (a b) (< (abs (- a number)) (abs (- b number)))))))

(defun revu-anchor--nearest (candidates number)
  "Return the one of CANDIDATES nearest NUMBER, or nil when there is no one.
Two candidates the same distance away are a coin flip, so they orphan
the Annotation instead of one of them winning."
  (cond
   ((null candidates) nil)
   ((and (cdr candidates)
         (= (abs (- (nth 0 candidates) number))
            (abs (- (nth 1 candidates) number))))
    nil)
   (t (car candidates))))

(defun revu-anchor--context-match-p (lines point index)
  "Return non-nil when the context POINT recorded surrounds INDEX in LINES."
  (let ((before (revu-anchor-before point))
        (after (revu-anchor-after point)))
    (and (or (> (length before) 0) (> (length after) 0))
         (equal before (revu-anchor--slice lines (- index (length before))
                                           (1- index)))
         (equal after (revu-anchor--slice lines (1+ index)
                                          (+ index (length after)))))))

(defun revu-anchor--found (located number)
  "Return the located pair for the LOCATED line against the recorded NUMBER.
A line found where it was recorded is `fresh'; found anywhere else it is
`moved'; not found at all it is `orphaned'."
  (cond
   ((null located) (cons nil 'orphaned))
   ((eq located number) (cons located 'fresh))
   (t (cons located 'moved))))

(defun revu-anchor--locate-point (lines point number digest-matches)
  "Locate the line POINT anchors in LINES, recorded at NUMBER.
DIGEST-MATCHES says whether the file is byte-for-byte the one the Anchor
was taken in, which is the first rung of the ladder.  Return a cons of
the line number and the derived state."
  (let* ((text (revu-anchor-line point))
         (trimmed (string-trim text))
         (located
          (if (and digest-matches (<= number (length lines)))
              number
            (catch 'revu-anchor--found
              ;; A rung that names one line decides.  A rung that ties names
              ;; no line, so the ladder goes on: the context window is where
              ;; ADR-0003 puts the tie that orphans, and a rung above it has
              ;; no business deciding what it could not tell apart.
              (dolist (predicate
                       (list (lambda (line _index) (equal line text))
                             (lambda (line _index)
                               (equal (string-trim line) trimmed))))
                (let* ((candidates (revu-anchor--candidates
                                    lines number predicate))
                       (nearest (and candidates
                                     (revu-anchor--nearest candidates number))))
                  (when nearest
                    (throw 'revu-anchor--found nearest))))
              ;; The line itself was rewritten.  Its neighbours still name
              ;; the place -- but only if they name exactly one place.
              (let ((windows (revu-anchor--candidates
                              lines number
                              (lambda (_line index)
                                (revu-anchor--context-match-p
                                 lines point index)))))
                (and (null (cdr windows)) (car windows)))))))
    (revu-anchor--found located number)))

(defun revu-anchor-locate (content anchor number)
  "Locate in CONTENT the line ANCHOR was taken on, recorded at NUMBER.
Return a cons of the line number the Annotation belongs on now and the
state derived for it -- `fresh', `moved', or `orphaned' with no number.
CONTENT is the current content of the file to search, which for a
removed line is the base blob the line was removed from."
  (revu-anchor--locate-point
   (revu-anchor--lines content) anchor number
   (equal (revu-anchor-digest anchor) (revu-digest content))))

(defun revu-anchor-locate-range (content anchor start end)
  "Locate in CONTENT the range ANCHOR covers, recorded as START to END.
Return a cons of the located (START . END) pair and the derived state.
The endpoints are located independently; losing either of them, or
finding them in the wrong order, orphans the range rather than reporting
a range the reviewer never drew."
  (let* ((lines (revu-anchor--lines content))
         (matches (equal (revu-anchor-digest anchor) (revu-digest content)))
         (first (revu-anchor--locate-point
                 lines (revu-anchor-start anchor) start matches))
         (last (revu-anchor--locate-point
                lines (revu-anchor-end anchor) end matches)))
    (if (or (null (car first)) (null (car last))
            (> (car first) (car last)))
        (cons nil 'orphaned)
      (cons (cons (car first) (car last))
            (if (and (eq (cdr first) 'fresh) (eq (cdr last) 'fresh))
                'fresh
              'moved)))))

(defun revu-anchor-locate-removed (base-content current-content anchor number)
  "Locate the removed line ANCHOR was taken on, recorded at NUMBER.
BASE-CONTENT is the base blob the line was removed from, and the ladder
runs over it: the blob is immutable, so an Annotation on a removed line
of any git Source keeps re-locating however the worktree moves on.

A base the repository can no longer read leaves BASE-CONTENT nil -- a
commit rewritten and pruned, or one a shallow clone never had.  The line
is nowhere to search for, so the Anchor is `fresh' as long as
CURRENT-CONTENT is the file the Anchor was taken over and `orphaned' as
soon as it is not (ADR-0003\\='s amendment).  Searching CURRENT-CONTENT
for the text instead would report a line the reviewer never annotated."
  (if base-content
      (revu-anchor-locate base-content anchor number)
    (revu-anchor--found
     (and current-content
          (equal (revu-anchor-digest anchor) (revu-digest current-content))
          number)
     number)))

(provide 'revu-anchor)
;;; revu-anchor.el ends here
