;;; revu-render.el --- Render a Review as a section tree  -*- lexical-binding: t; -*-

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

;; The review buffer is a render of state and nothing else (ADR-0008):
;; every change to a Review is a change to the state followed by a fresh
;; render, so the buffer can never drift from what the Sidecar holds.
;; Rendering the same state twice produces the same buffer.
;;
;; The tree is built with the standalone `magit-section' library, never
;; magit itself: a file is a section, a hunk is a section under it, and
;; folding, navigation and collapsing come with them.  A section that
;; should come back collapsed is rendered with `magit-insert-section's
;; HIDE argument, which is how a Reviewed mark will collapse what it
;; marks.
;;
;; Visibility is part of what a render applies, not something the buffer
;; carries over on its own: building the tree only resolves each
;; section's `hidden' slot, and the render puts those slots on screen
;; before it hands the buffer back.  A fold the reviewer set survives
;; because magit-section's visibility cache resolves it again, not
;; because the old overlay was left alone -- there is no old buffer.
;;
;; That cache is keyed on a section's identity, and a hunk's identity for
;; this purpose is where it sits among its file's hunks, never its header
;; text: the header is derived from content, so keying a fold on it loses
;; the fold on exactly the edit reload exists to show (ADR-0012).
;;
;; The buffer opens with a header naming the Review, the Source under it,
;; the Narrowing that limits it, and how much of it has been annotated and
;; read.  It is a section of its own and the first child of the root, not
;; the root's own heading: the root holds the whole buffer, and folding it
;; would take the Source away along with the header that names it.  Like
;; every other line here the header is drawn and not derived -- the caller
;; hands over a `revu-header' -- and its figures are over the whole Source,
;; because the view filters are a lens on a Source and never a change of
;; one.
;;
;; A heading carries the Reviewed state of what it opens, as a glyph the
;; render is handed rather than derives: `revu-reviewed.el' decides, this
;; file draws.  The glyph is heading text and not a fold, so it survives
;; opening a collapsed section and owes nothing to the view toggles.
;;
;; A render is where the reviewer's place is kept.  Point comes back on
;; the line it was on, named by the `revu-target' that line carries rather
;; than by the row it sat on: the row is the first thing a render changes,
;; whether by an Annotation inserted above or by a diff re-taken over a
;; file that grew.  The section and then the row answer in turn when the
;; line itself is gone, and the column and the height come back with it.
;;
;; Every source line carries a `revu-target' text property -- its path, its
;; number and its Origin -- so a command can tell what the reviewer is
;; pointing at.  The number is also drawn, as a dim prefix, when
;; `revu-line-numbers' is on: reviewers talk to agents in line numbers, so
;; the record holds them always, and the buffer shows them on request
;; (ADR-0011).  It is off by default, and turning it either way changes
;; nothing but the sight of the numbers -- Annotations, visiting, Export
;; and Reviewed marks read the Target, never the prefix.  Text is faced
;; with `font-lock-face': `global-font-lock-mode' strips `face'.

;;; Code:

(require 'cl-lib)
(require 'diff-mode)
(require 'magit-section)
(require 'seq)
(require 'revu-diff)
(require 'revu-record)

(defface revu-header-label
  '((t :inherit magit-section-heading))
  "Face of the labels down the left of the header at the top of a Review.
The values beside them are left in the default face: the label is what
the eye runs down to find a line, and the value is what it stops to
read."
  :group 'revu)

(defface revu-line-number
  '((t :inherit shadow))
  "Face of the line-number prefix, when `revu-line-numbers' has it drawn."
  :group 'revu)

(defface revu-file-heading
  '((t :inherit diff-file-header))
  "Face of the heading that opens a file's section."
  :group 'revu)

(defface revu-hunk-heading
  '((t :inherit diff-hunk-header))
  "Face of the heading that opens a hunk's section."
  :group 'revu)

(defface revu-annotation-heading
  '((t :inherit font-lock-keyword-face))
  "Face of the heading that opens an Annotation's section."
  :group 'revu)

(defface revu-annotation-body
  '((t :inherit font-lock-doc-face))
  "Face of the body the reviewer wrote on an Annotation."
  :group 'revu)

(defface revu-reply
  '((t :inherit font-lock-string-face))
  "Face of the Reply an agent wrote under an Annotation.
A Reply has a face of its own because its presence is the answered
signal (ADR-0007): the reviewer tells an answered Annotation from an
unanswered one by reading the buffer."
  :group 'revu)

(defface revu-reviewed
  '((t :inherit shadow))
  "Face of a heading whose region has been marked Reviewed, and of its glyph.
Recessive on purpose: a Reviewed mark exists to get read work out of the
reviewer's way, so what it marks should recede rather than call out."
  :group 'revu)

(defface revu-stale
  '((t :inherit warning))
  "Face of the glyph on a heading whose region was read and has changed since.
Not recessive, and deliberately so.  This is the one Reviewed state that
misleads by staying quiet: a region an agent rewrote under the reviewer
looks exactly like code nobody has read, so rework cannot be told from
new work."
  :group 'revu)

(defface revu-moved
  '((t :inherit warning))
  "Face of the badge on an Annotation whose Anchor was re-found elsewhere."
  :group 'revu)

(defface revu-orphaned
  '((t :inherit error))
  "Face of the badge on an Annotation whose Anchor was not found at all."
  :group 'revu)

(defclass revu-section (magit-section) ()
  "The parent of every section revu renders.
It exists so that what revu asks of magit-section is asked once rather
than once per class.")

(cl-defmethod magit-section-highlight ((section revu-section))
  "Highlight the heading of SECTION and stop there.
magit-section covers a section body and all when point is in it, which
flattens the faces the render put on what the reviewer is reading: the
Origin of a diff line, and the Reply that tells an answered Annotation
from an unanswered one (ADR-0007).  Revu keeps the affordance and drops
the cover.

Specialising this generic is the extension point magit-section offers,
which is the boundary ADR-0008 drew.  No face is passed, so the heading
takes whatever the reviewer has themed `magit-section-highlight' to:
revu has no opinion about what \"you are here\" should look like."
  (magit-section-highlight-range (oref section start)
                                 (or (oref section content)
                                     (oref section end))))

(defclass revu-file-section (revu-section) ()
  "The section holding one file of the Source under review.")

(defclass revu-hunk-section (revu-section)
  ((index :initarg :index :initform nil))
  "The section holding one hunk of a file under review.
INDEX is the hunk's ordinal position among the hunks its file was parsed
with, and is the hunk's identity to magit-section rather than its value
\(ADR-0012).")

(cl-defmethod magit-section-ident-value ((section revu-hunk-section))
  "Return the identity magit-section correlates SECTION by across renders.
A hunk carries two identities and they want opposite properties: its
value names the content, which is what un-matches a Reviewed mark once
the content changes (ADR-0009), and this names the position, which is
what keeps a fold across the very edit reload exists to show (ADR-0012).
The visibility cache is keyed on this one."
  (cons (car (oref section value)) (oref section index)))

(defclass revu-annotation-section (revu-section) ()
  "The section holding one Annotation.
Its value is the Annotation's ULID, which is the Annotation's identity:
two Annotations on one Target are two sections, and point can rest on
either of them.")

(cl-defstruct (revu-render-placement
               (:constructor revu-render-placement-create)
               (:copier nil))
  "Where one Annotation renders now, and the state derived for it.
ANNOTATION is the record, PATH the file it belongs to today, LINE the
line its Anchor was re-located to and ORIGIN that line's Origin, and
STATE is `fresh', `moved' or `orphaned'.  END is the last line of a
range, re-located on its own; only a range Target has one.  An
Annotation on the Review has no PATH, and one that was not found again
has no LINE: it renders under the heading of its file, or at the top of
the buffer when its file is not in the Source at all."
  annotation path line end origin state)

;; The `revu' customization group is defined in `revu.el', which is
;; loaded after this file; a group is only a symbol either way.
(defcustom revu-line-numbers nil
  "Whether the Review buffer draws each source line's number in front of it.
Off by default: the prefix is revu's own inserted text, four columns at
least on every line, and most reading does not want it.  It is a view and not a
record -- a line is named by the `revu-target' property it carries, so
Annotations, visiting, Export and Reviewed marks read the same line
either way (ADR-0011)."
  :type 'boolean
  :group 'revu)

(defconst revu-render--line-number-width 4
  "Least width of the line-number prefix, in characters.")

(defun revu-render--status-label (status)
  "Return the word that opens the heading of a file with STATUS."
  (pcase status
    ("added" "new file ")
    ("deleted" "deleted  ")
    ("renamed" "renamed  ")
    (_ "modified ")))

(defun revu-render--file-heading (file)
  "Return the heading text of FILE, a `revu-diff-file'.
A plain file is named and nothing more: there is no diff, so there is
nothing for a status word to say about it (ADR-0011)."
  (if (revu-diff-file-plain file)
      (revu-diff-file-path file)
    (concat (revu-render--status-label (revu-diff-file-status file))
          "  "
          (if (equal (revu-diff-file-status file) "renamed")
              (format "%s -> %s"
                      (revu-diff-file-old-path file)
                      (revu-diff-file-path file))
              (revu-diff-file-path file)))))

(defun revu-render--number-width (file)
  "Return the width the line-number prefix takes for FILE, or nil for no prefix.
One width per file keeps a file's lines aligned with each other, whatever
the numbers on either side of it reach.  There is no width to find when
`revu-line-numbers' is off: nothing is drawn, and the scan for the widest
number would be a walk over every line of the file for nothing."
  (when revu-line-numbers
    (let ((widest 0))
      (dolist (hunk (revu-diff-file-hunks file))
        (dolist (line (revu-diff-hunk-lines hunk))
          (setq widest (max widest (length (number-to-string (nth 1 line)))))))
      (max revu-render--line-number-width widest))))

(defun revu-render--line-face (origin)
  "Return the face a line of ORIGIN is rendered in."
  (pcase origin
    ("added" 'diff-added)
    ("removed" 'diff-removed)
    (_ 'diff-context)))

(defun revu-render-line (path old-path line width)
  "Insert LINE of the file at PATH, numbered in WIDTH columns when numbers are on.
LINE is (ORIGIN NUMBER TEXT).  The number is the line's number in the
file its Origin counts in -- the old file for a removal, the new file for
anything else -- and the whole line carries a `revu-target' property naming
what the reviewer is pointing at.  The prefix is drawn only when
`revu-line-numbers' is on; the property is there either way, which is
what makes the prefix a view and not a record.

A removed line is named under OLD-PATH, the path the file had before the
diff renamed it, because that is the only path the line exists under: it
is read back from the base blob, and ADR-0004 keeps a Target's path as
recorded rather than rewriting it later."
  (pcase-let ((`(,origin ,number ,text) line))
    (insert
     (propertize
      (concat (if revu-line-numbers
                  (propertize (format (format "%%%dd " width) number)
                              'font-lock-face 'revu-line-number)
                "")
              (propertize text 'font-lock-face (revu-render--line-face origin))
              "\n")
      'revu-target (list (if (equal origin "removed") old-path path)
                         number origin)))))

(defconst revu-render-reviewed-glyph "\N{CHECK MARK}"
  "Glyph marking a heading whose region matches a Reviewed mark.")

(defconst revu-render-stale-glyph "\N{NOT EQUAL TO}"
  "Glyph marking a heading whose region was read and no longer matches its mark.
It says what is the matter rather than that something is: the content is
not what the reviewer read.")

(defun revu-render--reviewed-badge (reviewed)
  "Return the badge naming REVIEWED, or nil when there is nothing to say.
REVIEWED is (STATE . PROGRESS) as `revu-reviewed-state-p\' returns it:
`reviewed\', `stale\' or nil, and how many of a file\'s hunks match out of
how many it has.  A file part-way read carries the count, because how
much of this file is left is the question being asked of it; a file that
is read, or has not been touched, says so with its glyph alone."
  (let* ((state (car reviewed))
         (progress (cdr reviewed))
         (glyph (pcase state
                  ('reviewed revu-render-reviewed-glyph)
                  ('stale revu-render-stale-glyph)))
         (count (when (and progress
                           (> (car progress) 0)
                           (< (car progress) (cdr progress)))
                  (format "%d/%d" (car progress) (cdr progress))))
         (text (string-join (delq nil (list glyph count)) " ")))
    (unless (string-empty-p text)
      (propertize text 'font-lock-face
                  (if (eq state 'stale) 'revu-stale 'revu-reviewed)))))

(defun revu-render--heading (text face reviewed)
  "Return the heading TEXT in FACE, carrying the badge for REVIEWED.
The badge is part of the heading and not of the section\'s body, which is
what makes a Reviewed mark visible whether the section is folded or open:
collapsing is one of the two things marking does, and never the only sign
that it happened."
  (let ((badge (revu-render--reviewed-badge reviewed)))
    (concat (propertize text 'font-lock-face
                        (if (eq (car reviewed) 'reviewed) 'revu-reviewed face))
            (and badge (concat "  " badge)))))

(defconst revu-render--annotation-indent "    "
  "What an Annotation's heading is indented by under the line it is about.")

(defun revu-render--state-face (state)
  "Return the face the badge naming Anchor STATE is rendered in."
  (pcase state
    ('moved 'revu-moved)
    ('orphaned 'revu-orphaned)
    (_ 'revu-annotation-heading)))

(defun revu-render-annotation (placement)
  "Insert the Annotation of PLACEMENT as a section of its own.
The heading names the Kind the reviewer chose and the state derived for
the Anchor, and the body under it is the section's content, so `TAB'
folds it away like any other section.  An agent's Reply follows the body
it answers, in a face of its own."
  (let* ((annotation (revu-render-placement-annotation placement))
         (state (revu-render-placement-state placement))
         (reply (revu-annotation-reply annotation)))
    (magit-insert-section (revu-annotation-section
                           (revu-annotation-id annotation))
      (magit-insert-heading
        (concat revu-render--annotation-indent
                (propertize (revu-annotation-kind annotation)
                            'font-lock-face 'revu-annotation-heading)
                (when state
                  (propertize (format " [%s]" state)
                              'font-lock-face (revu-render--state-face state)))))
      (dolist (line (split-string (revu-annotation-body annotation) "\n"))
        (insert revu-render--annotation-indent "  "
                (propertize line 'font-lock-face 'revu-annotation-body)
                "\n"))
      (dolist (line (and reply (split-string reply "\n")))
        (insert revu-render--annotation-indent "  "
                (propertize line 'font-lock-face 'revu-reply)
                "\n")))))

(defun revu-render--lines (hunk file width placements)
  "Insert the lines of HUNK of FILE, in WIDTH columns, with their PLACEMENTS.
The Annotations on a line are inserted as sections under it, which is
what makes them foldable and addressable (ADR-0008)."
  (dolist (line (revu-diff-hunk-lines hunk))
    (revu-render-line (revu-diff-file-path file) (revu-diff-file-old-path file)
                      line width)
    (dolist (placement (revu-render--placements-at
                        placements (nth 1 line) (nth 0 line)))
      (revu-render-annotation placement))))

(defun revu-render--placements-on (placements path)
  "Return the PLACEMENTS that belong to the file at PATH."
  (seq-filter (lambda (placement)
                (equal (revu-render-placement-path placement) path))
              placements))

(defun revu-render--placements-at (placements number origin)
  "Return the PLACEMENTS that belong on the line NUMBER of Origin ORIGIN."
  (seq-filter (lambda (placement)
                (and (equal (revu-render-placement-line placement) number)
                     (equal (revu-render-placement-origin placement) origin)))
              placements))

(defun revu-render--file-lines (file)
  "Return every (NUMBER . ORIGIN) FILE renders, as a list."
  (let ((lines nil))
    (dolist (hunk (revu-diff-file-hunks file))
      (dolist (line (revu-diff-hunk-lines hunk))
        (push (cons (nth 1 line) (nth 0 line)) lines)))
    lines))

(defun revu-render--unplaced (placements file)
  "Return the PLACEMENTS of FILE that no line FILE renders is about.
An Annotation on a whole file has no line to sit under, and one whose
Anchor was orphaned, or re-located outside every hunk, has no line left
to sit under; both belong under the file's own heading, where the
reviewer can still see them."
  (let ((lines (revu-render--file-lines file)))
    (seq-remove (lambda (placement)
                  (member (cons (revu-render-placement-line placement)
                                (revu-render-placement-origin placement))
                          lines))
                placements)))

(defun revu-render--annotated-p (placements hunk)
  "Return non-nil when PLACEMENTS puts an Annotation on HUNK.
PLACEMENTS are the ones already known to belong to HUNK's file.  A whole-file
Annotation, and one whose Anchor was orphaned, belongs to no hunk: it
renders under the file's own heading, which is where the annotated-only
filter keeps it findable."
  (seq-find (lambda (line)
              (revu-render--placements-at placements (nth 1 line) (nth 0 line)))
            (revu-diff-hunk-lines hunk)))

;;;; The header at the top of the buffer

(defclass revu-header-section (revu-section) ()
  "The section holding the header at the top of a Review.
It is the first child of the root and not the root's own heading: the
root holds the whole buffer, so folding it would fold the Source away
along with the header that names it.")

(cl-defstruct (revu-header
               (:constructor revu-header-create)
               (:copier nil))
  "What the header at the top of a review buffer says.
NAME is the Review's name and SCRATCH is non-nil when that name is its
Source's scratch bucket.  SOURCE is the one line naming what is under
review and NARROWING the pathspecs it is limited to, or nil for a Source
that spans every path.

KINDS is how many Annotations of each Kind the Review holds, as an alist
in Kind order; ANSWERED how many of them carry a Reply and ORPHANED how
many Anchors were not found again.

REVIEWED is (READ TOTAL STALE) over the hunks of the whole Source, and
for a plain file -- which has no hunks to divide it -- the one word its
Reviewed state is: `reviewed', `stale' or `unreviewed'.

Everything here is decided before the render is called: this file draws a
header and derives none of it, exactly as it draws a Reviewed glyph
`revu-reviewed.el' decided."
  name scratch source narrowing kinds answered orphaned reviewed)

(defconst revu-render--header-label-width 10
  "Columns a header label is padded to, colon included.
It is the width of the longest label the header always draws, so the
values line up under each other; the one longer label overruns it by
design rather than pushing every other line further right.")

(defun revu-render--header-line (label value)
  "Return the header line naming LABEL and carrying VALUE."
  (concat (propertize (string-pad (concat label ":")
                                  revu-render--header-label-width)
                      'font-lock-face 'revu-header-label)
          " " value "\n"))

(defun revu-render--plural (count word)
  "Return WORD in the number COUNT is in: as it stands for one, an s for the rest.
The word is returned rather than the count with it, because the two
figures the header draws count in different shapes -- a Kind is `3
questions' and the hunks are `12/20 hunks' -- and only the word is
common to them."
  (concat word (if (= count 1) "" "s")))

(defun revu-render--header-review (header)
  "Return the value the Review line of HEADER carries."
  (concat (revu-header-name header)
          (when (revu-header-scratch header)
            (propertize " (scratch)" 'font-lock-face 'shadow))))

(defun revu-render--header-annotations (header)
  "Return the value the Annotations line of HEADER carries.
The total is always there, so the line keeps its shape while the Review
fills up; every part behind it is left off while there is none of it,
because a Review with nothing answered should not have to say so."
  (let* ((kinds (revu-header-kinds header))
         (total (apply #'+ (mapcar #'cdr kinds)))
         (breakdown (mapconcat (lambda (kind)
                                 (format "%d %s" (cdr kind)
                                         (revu-render--plural (cdr kind)
                                                              (car kind))))
                               (seq-remove (lambda (kind) (zerop (cdr kind)))
                                           kinds)
                               " \N{MIDDLE DOT} "))
         (answered (revu-header-answered header))
         (orphaned (revu-header-orphaned header)))
    (concat (number-to-string total)
            (unless (string-empty-p breakdown) (format " (%s)" breakdown))
            (when (> answered 0) (format ", %d answered" answered))
            (when (> orphaned 0)
              (concat ", " (propertize (format "%d orphaned" orphaned)
                                       'font-lock-face 'warning))))))

(defun revu-render--header-reviewed (header)
  "Return the value the Reviewed line of HEADER carries.
The figure is over the whole Source and not over what is on screen: the
view filters are a lens on a Source and never a change of Source, so how
much is left to read cannot move when the reviewer hides what they have
read.  A plain file says the one word it is in instead, for want of
hunks to count."
  (let ((reviewed (revu-header-reviewed header)))
    (if (consp reviewed)
        (pcase-let ((`(,read ,total ,stale) reviewed))
          (concat (format "%d/%d %s" read total
                          (revu-render--plural total "hunk"))
                  (when (> stale 0)
                    (concat ", " (propertize (format "%d stale" stale)
                                             'font-lock-face 'warning)))))
      (pcase reviewed
        ('stale (propertize "stale" 'font-lock-face 'warning))
        (word (symbol-name word))))))

(defun revu-render-header (header placements)
  "Insert HEADER as the section that opens the buffer, with PLACEMENTS under it.
PLACEMENTS are the Annotations on the Review as a whole: what the
reviewer has to say about the change rather than about any line of it,
which is what the header is about too.

The Review line is the heading, so folding the header leaves the name of
what is being reviewed on screen and takes the rest away.  The fold
outlives the render because the section's value never changes with the
Review's state, which is what magit-section keys its visibility cache
on."
  (magit-insert-section (revu-header-section 'revu-header)
    (magit-insert-heading
      (string-trim-right
       (revu-render--header-line "Review" (revu-render--header-review header))))
    (insert (revu-render--header-line "Source" (revu-header-source header)))
    (when (revu-header-narrowing header)
      (insert (revu-render--header-line
               "Narrowing" (string-join (revu-header-narrowing header) " "))))
    (insert (revu-render--header-line
             "Annotations" (revu-render--header-annotations header)))
    (insert (revu-render--header-line
             "Reviewed" (revu-render--header-reviewed header)))
    (dolist (placement placements)
      (revu-render-annotation placement)))
  (insert "\n"))

(defun revu-render-hunk-value (path hunk)
  "Return the value a hunk section for HUNK of PATH is rendered with.
A hunk is named to a render by its path and the `@@\' header it was
rendered with; that pair is its identity across a render, which is how a
command finds again what it acted on once the buffer has been built anew.
Built here, in one place, so nothing can name a hunk two ways."
  (cons path (revu-diff-hunk-header hunk)))

(declare-function evil-visual-state-p "ext:evil-states" ())
(declare-function evil-exit-visual-state "ext:evil-states" (&optional buffer message))

(defun revu-render--drop-selection ()
  "Drop any selection over the buffer this render is about to destroy.
A render erases the buffer and builds it anew, so the text a selection
was over is gone and the selection says nothing about what replaces it.
Dropping it here rather than in each command that renders states that
once: a command reads the selection before it renders, and nothing needs
it afterwards.

evil is why this cannot be left alone.  `erase-buffer\' does not detach a
marker -- the same fact `revu-render-diff\' keeps a render\'s cost flat
with -- so the markers evil holds a visual selection in all collapse to
the top of the buffer, and `evil-visual-post-command\', which runs after
the command is over, puts point back at one of them.  A reviewer who
marked a run reviewed would land on the header rather than on the section
after the run.  Leaving visual state here, while those markers still say
what they mean, is what lets the command keep the last word on where the
reviewer goes next.

It runs before the render reads where the reviewer is, so what comes back
is their own point and not the end evil expanded the region to.  evil is
called only when it is there: revu depends on evil in no way (ADR-0010)."
  (deactivate-mark)
  (when (and (fboundp 'evil-visual-state-p)
             (fboundp 'evil-exit-visual-state)
             (evil-visual-state-p))
    (evil-exit-visual-state)))

(defun revu-render-diff (files &optional hidden-p placements keep-p state-p
                               header)
  "Render FILES, a list of `revu-diff-file', into the current buffer.
HIDDEN-P is called with the value of each file and hunk section and
decides whether that section is rendered collapsed; a Reviewed mark
collapses what it marks through it.  PLACEMENTS are the
`revu-render-placement's of the Review's Annotations, which render as
sections under the lines they are about.  KEEP-P is called with the value
of each file and hunk section and with whether any Annotation is on it,
and decides whether that section is rendered at all; the buffer's view
filters shape the render through it, and a nil KEEP-P renders the whole
Source.  STATE-P is called with the value of each file and hunk section
and returns the Reviewed state to badge its heading with; the render
knows marks only through it.  HEADER is the `revu-header' the buffer
opens with, decided by the caller like everything else here; nil renders
no header at all.  Point is left on the same line of the Source it was
on, at the same column and the same height, or as near to that as this
render can put it."
  (revu-render--drop-selection)
  (let* ((inhibit-read-only t)
         ;; A section's `start', `content' and `end' are plain positions
         ;; here, not the markers magit-section makes by default.  That is
         ;; sound because nothing ever edits a review buffer in place:
         ;; ADR-0008 makes every change to a Review a full re-render, and
         ;; every insertion in the package is inside this render pass, so
         ;; an integer cannot go stale under a section.  It is also what
         ;; keeps a render's cost flat -- `erase-buffer' does not detach a
         ;; marker, so markers left by earlier renders would be adjusted
         ;; again by every insertion this one makes, and a large Source
         ;; would get slower the longer it was reviewed.  Anyone adding an
         ;; in-place edit to a review buffer breaks this and must move the
         ;; positions back to markers.  Not `delay': that converts
         ;; everything back to markers at the end of the build, which is
         ;; the population this binding exists to avoid.
         (magit-section-inhibit-markers t)
         (previous (revu-render--point-now))
         (paths (mapcar #'revu-diff-file-path files))
         ;; An Annotation on the Review renders under the header, which is
         ;; what the header is about too.  One on a file the Source does
         ;; not carry belongs to no section at all and stays loose between
         ;; the header and the first file, where the reviewer can still
         ;; see it.  With no header there is nowhere to put the first kind
         ;; but loose.
         (on-the-review (and header
                             (seq-filter (lambda (placement)
                                           (null (revu-render-placement-path
                                                  placement)))
                                         placements)))
         (loose (seq-remove (lambda (placement)
                              (or (memq placement on-the-review)
                                  (member (revu-render-placement-path placement)
                                          paths)))
                            placements)))
    (erase-buffer)
    (magit-insert-section (magit-section 'revu-review)
      (when header
        (revu-render-header header on-the-review))
      (dolist (placement loose)
        (revu-render-annotation placement))
      (dolist (file files)
        (let* ((path (revu-diff-file-path file))
               (width (revu-render--number-width file))
               (mine (revu-render--placements-on placements path))
               (plain (revu-diff-file-plain file))
               ;; A hunk is numbered among the hunks its file was parsed
               ;; with, before the filters drop any: an index over what was
               ;; rendered would renumber every hunk below a dropped one and
               ;; hand its fold to a different hunk (ADR-0012).
               (hunks (seq-filter
                       (lambda (numbered)
                         (let ((hunk (cdr numbered)))
                           (or plain (null keep-p)
                               (funcall keep-p
                                        (revu-render-hunk-value path hunk)
                                        (revu-render--annotated-p mine hunk)))))
                       (seq-map-indexed (lambda (hunk index)
                                          (cons index hunk))
                                        (revu-diff-file-hunks file)))))
          (when (or (null keep-p) (funcall keep-p path (and mine t)))
            (magit-insert-section (revu-file-section
                                   path
                                   (and hidden-p (funcall hidden-p path)))
              (magit-insert-heading
                (revu-render--heading (revu-render--file-heading file)
                                      'revu-file-heading
                                      (and state-p (funcall state-p path))))
              (dolist (placement (revu-render--unplaced mine file))
                (revu-render-annotation placement))
              (pcase-dolist (`(,index . ,hunk) hunks)
                ;; A plain file is the diff render minus the hunk split: its
                ;; lines sit flat under the one file section (ADR-0011).
                (if plain
                    (revu-render--lines hunk file width mine)
                  (let ((value (revu-render-hunk-value path hunk)))
                    (magit-insert-section (revu-hunk-section
                                           value
                                           (and hidden-p
                                                (funcall hidden-p value))
                                           :index index)
                      (magit-insert-heading
                        (revu-render--heading (revu-diff-hunk-header hunk)
                                              'revu-hunk-heading
                                              (and state-p
                                                   (funcall state-p value))))
                      (revu-render--lines hunk file width mine))))))))))
    ;; Building the tree only resolves each section's visibility into its
    ;; `hidden' slot; what hides text is an invisible overlay, and only
    ;; `magit-section-hide' makes one.  Magit's own applier walks the tree
    ;; and puts the slots on screen, so the render ends by calling it --
    ;; without it every render comes back fully expanded, whatever it
    ;; resolved (ADR-0008).
    (magit-section-show magit-root-section)
    (revu-render--restore-point previous)))

(defun revu-render-forget-visibility (section)
  "Drop the visibility magit-section memoised for SECTION.
The memo is how a fold the reviewer set by hand outlives the render that
built the section: the next render reads it back and resolves the same
visibility.  It outranks the HIDE a render derives from the Review's
state, so a command whose change of state is what should decide how a
section looks has to forget the memo first."
  (setq magit-section-visibility-cache
        (assoc-delete-all (magit-section-ident section)
                          magit-section-visibility-cache)))

(defun revu-render-forget-visibility-tree (section)
  "Forget the memoised visibility of SECTION and of the sections under it.
An Annotation, and anything under one, is left alone: its fold is the
reviewer's own and no state of the Review decides it."
  (when (or (object-of-class-p section 'revu-file-section)
            (object-of-class-p section 'revu-hunk-section))
    (revu-render-forget-visibility section)
    (mapc #'revu-render-forget-visibility-tree (oref section children))))

(cl-defstruct (revu-render-point
               (:constructor revu-render-point-create)
               (:copier nil))
  "Where the reviewer was looking, so the next render can put them back.
TARGET is what the line point was on carries: its path, its number and
its Origin, which is what names that line to a render and not a Target
record.  IDENT is the identity of the section point was in, LINE the
buffer line number it was on, COLUMN the column, and HEIGHT how far down
its window the line sat.

`revu-render--restore-point' reads them; it says there which it trusts
first and why."
  target ident line column height)

(defun revu-render--point-height ()
  "Return how far down its window the line at point sits, in screen rows.
Nil when no window on this frame is showing this buffer: a batch render
has no height to keep.  A buffer shown in two windows is measured in one
of them and put back in one of them, which is the reviewer's own window
whenever they are the one rendering."
  (let ((window (get-buffer-window)))
    (when window
      (count-screen-lines (window-start window) (line-beginning-position)
                          nil window))))

(defun revu-render--point-now ()
  "Return where the reviewer is looking now, as a `revu-render-point'."
  (revu-render-point-create
   :target (get-text-property (line-beginning-position) 'revu-target)
   :ident (and magit-root-section
               (let ((section (magit-current-section)))
                 (and section (magit-section-ident section))))
   :line (line-number-at-pos)
   :column (current-column)
   :height (revu-render--point-height)))

(defun revu-render-section-with-value (value)
  "Return the section whose value is VALUE, or nil when there is none.
A section's value is its identity across a render, which is how a command
finds again what it acted on once the buffer has been built anew."
  (unless (null value)
    (let ((found nil))
      (cl-labels ((walk (section)
                    (cond (found nil)
                          ((equal (oref section value) value)
                           (setq found section))
                          (t (mapc #'walk (oref section children))))))
        (walk magit-root-section))
      found)))

(defun revu-render-target-position (predicate)
  "Return where the first line whose `revu-target' satisfies PREDICATE is.
Nil when no line does.  PREDICATE is called with what each run of the
buffer carries, which is nil for everything that is not a source line, so
it has to answer for nil as well.  The walk is over the property's runs
rather than the buffer's lines: a heading, an Annotation and its Reply
carry no Target and are not worth stepping through one line at a time."
  (let ((position (point-min))
        (found nil))
    (while (and position (not found))
      (if (funcall predicate (get-text-property position 'revu-target))
          (setq found position)
        (setq position (next-single-property-change position 'revu-target))))
    found))

(defun revu-render--target-position (target)
  "Return where the line carrying TARGET is rendered, or nil when none is.
A line a fold has hidden is no answer: point would sit in text the
reviewer cannot see, so the section that hid it is left to answer
instead."
  (when target
    (let ((found (revu-render-target-position
                  (lambda (candidate) (equal candidate target)))))
      (and found (not (invisible-p found)) found))))

(defun revu-render--heading-position (section)
  "Return where the heading standing for SECTION is, or nil for no SECTION.
A section a fold has hidden hands the question to its parent, so the
reviewer lands on the heading of whatever is holding their section closed
rather than inside it: point in invisible text is pushed out of it at the
end of the command, past everything the fold covers.  Nothing is opened
to make room -- a fold is the reviewer's own.

What is asked is the overlay on screen and not the `hidden' slot the
render resolved: the slot is magit-section's model of visibility and only
`magit-section-hide' puts it on screen (ADR-0008)."
  (while (and section (invisible-p (oref section start)))
    (setq section (oref section parent)))
  (and section (oref section start)))

(defun revu-render--section-position (ident)
  "Return where the heading of the section IDENT names is, or nil."
  (when (and ident magit-root-section)
    (revu-render--heading-position (magit-get-section ident))))

(defun revu-render-heading-position (value)
  "Return where point can be left for the section valued VALUE, or nil.
Nil when nothing rendered carries VALUE: a view filter has taken it out
of the buffer and there is no heading to go to.  A heading under a fold
answers with the heading of the fold, as `revu-render--heading-position'
says there."
  (revu-render--heading-position (revu-render-section-with-value value)))

(defun revu-render--line-position (line)
  "Return where buffer LINE begins."
  (save-excursion
    (goto-char (point-min))
    (forward-line (1- line))
    (line-beginning-position)))

(defun revu-render--restore-height (height)
  "Put the line at point back HEIGHT screen rows down its window.
`recenter' clamps at the top of the buffer rather than scrolling past
it, so a line that no longer has HEIGHT rows above it settles where it
can and the reviewer is not scrolled somewhere they never were.  The
height is kept whichever of the three answers put point where it is: a
reviewer whose line is gone is best left looking at the same part of the
buffer they were.

The window is handed the point this render just restored before it is
selected, because selecting a window puts its own idea of point back into
the buffer -- which for any window but the selected one is where the
reviewer was before the render, and would undo the restore it is here to
finish."
  (let ((window (get-buffer-window)))
    (when (and height window)
      (set-window-point window (point))
      (with-selected-window window
        (recenter height)))))

(defun revu-render--restore-point (previous)
  "Put the reviewer back where PREVIOUS, a `revu-render-point', had them.
Three places are tried, in the order of how well each names the line the
reviewer was on.  The Target the line carries names the line itself, and
so survives the render that adds an Annotation above them and the diff
re-taken over a file that grew.  The section names the hunk the line was
in, and answers once the line is gone from the Source.  The buffer row
names nothing but where the line happened to sit -- which is the first
thing a render changes -- and answers only once the section is gone too.

The column comes back with the line, and the line comes back at the
height it was at, so a reviewer who kept their line does not lose their
view of it."
  (let ((position (revu-render--target-position
                   (revu-render-point-target previous))))
    (if position
        (progn (goto-char position)
               (move-to-column (revu-render-point-column previous)))
      ;; A heading is read from its start: there is no column of the
      ;; reviewer's to keep on a line that is not the line they were on.
      (goto-char (or (revu-render--section-position
                      (revu-render-point-ident previous))
                     (revu-render--line-position
                      (revu-render-point-line previous))))))
  (revu-render--restore-height (revu-render-point-height previous)))

(provide 'revu-render)
;;; revu-render.el ends here
