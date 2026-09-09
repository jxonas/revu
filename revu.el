;;; revu.el --- Review diffs and files with exportable annotations  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Jonas Rodrigues

;; Author: Jonas Rodrigues
;; Version: 0.1.0
;; Package-Requires: ((emacs "30.2") (magit-section "4.3.0") (transient "0.13.0"))
;; Keywords: tools, vc
;; URL: https://github.com/jonasrodrigues/revu

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

;; revu reviews a Source -- a diff or a plain file -- in a dedicated
;; read-only buffer, and persists the reviewer's Annotations as a
;; Sidecar: one JSON file per Review under
;; `<project-root>/.revu/reviews/', with the Exports written beside it
;; under `<project-root>/.revu/exports/'.  The Sidecar is the review
;; state itself, and the record AI agents and scripts read.
;;
;; This file carries the package entry points and the helpers that
;; locate the project root and the Sidecar directory.
;;
;; A Review opens on the name derived from its Source and prompts for
;; nothing; that Review is the Source's scratch bucket, resumed every
;; time the Source is reviewed again.  A prefix argument asks for a name
;; instead, and `revu-rename' gives one to a Review that turned out to be
;; worth keeping (ADR-0005's amendment).  `revu-open' lists what is on
;; disk and `revu-discard' throws one away.
;;
;; There is no migration from the flat `.revu/' of before that
;; amendment: a reviewer carrying Sidecars and Exports from then moves
;; them into `reviews/' and `exports/' by hand, once.
;;
;; revu inherits the reviewer's `magit-section' configuration rather
;; than overriding it.  Its faces and section classes define the Review's
;; appearance, including highlighting headings rather than section
;; bodies.  `revu-mode' makes exactly two buffer-local exceptions:
;; `magit-section-cache-visibility' and
;; `magit-section-preserve-visibility'.  Both protect the invariant that
;; a reviewer's folds survive a render; neither controls appearance.
;; Put any other `magit-section' override in `revu-mode-hook'.  For
;; example, this disables current-section highlighting only in Reviews:
;;
;;   (add-hook 'revu-mode-hook
;;             (lambda ()
;;               (setq-local magit-section-highlight-current nil)))
;;
;; revu reaches past `magit-section' into magit only through
;; `revu-magit-mode' in `revu-magit.el'.  That mode is experimental
;; (ADR-0013), off by default, and appends a "Review in revu" switch to
;; the `magit-diff' transient.  It advises the setup functions that
;; magit's diff commands use.  Since the switch runs magit's commands,
;; magit's semantics stand: a commit selection in a log reviews
;; `oldest..newest', leaving out the oldest selected commit's changes.
;; Nothing in this file loads magit.

;;; Code:

(require 'project)
(require 'revu-anchor)
(require 'revu-annotate)
(require 'revu-diff)
(require 'revu-export)
(require 'revu-keymap)
(require 'revu-record)
(require 'revu-render)
(require 'revu-reviewed)
(require 'revu-sidecar)

(defgroup revu nil
  "Review diffs and files with exportable annotations."
  :group 'tools
  :prefix "revu-")

(defconst revu-directory-name ".revu"
  "Name of the per-project directory revu keeps a project's Reviews in.")

(defconst revu-reviews-directory-name "reviews"
  "Name of the directory under `revu-directory-name' holding Sidecars.")

(defconst revu-exports-directory-name "exports"
  "Name of the directory under `revu-directory-name' holding Exports.")

(defun revu-project-root (path)
  "Return the root of the project containing PATH, as a directory name.
PATH may name a file or a directory and need not exist.  Signal a
`user-error' when PATH belongs to no project: revu refuses a Source
outside a project root rather than inventing a Sidecar location for it."
  (let* ((expanded (expand-file-name path))
         (directory (file-name-as-directory
                     (if (file-directory-p expanded)
                         expanded
                       (file-name-directory expanded))))
         (project (project-current nil directory)))
    (unless project
      (user-error "No project root for %s; revu reviews files inside a project"
                  path))
    (file-name-as-directory (file-truename (project-root project)))))

(defun revu-directory (subdirectory &optional path)
  "Return SUBDIRECTORY of the revu directory of the project containing PATH.
PATH defaults to `default-directory'.  Nothing is created: naming a file
is not writing one, and the command about to write makes the directory.
Signal a `user-error' when PATH belongs to no project."
  (file-name-as-directory
   (expand-file-name subdirectory
                     (expand-file-name
                      revu-directory-name
                      (revu-project-root (or path default-directory))))))

(defun revu-sidecar-file-name (name &optional path)
  "Return the Sidecar file that persists the Review called NAME.
The Sidecar lives under `revu-reviews-directory-name' in the revu
directory of the project containing PATH, which defaults to
`default-directory'.  Neither the directory nor the file is created.
Signal a `user-error' when PATH belongs to no project."
  (expand-file-name (concat name ".json")
                    (revu-directory revu-reviews-directory-name path)))

(defun revu-export-file-name (name &optional path)
  "Return the file the Export of the Review called NAME is written to.
PATH names the project to look in, and defaults to `default-directory'.
It lives under `revu-exports-directory-name', beside the `reviews\\='
directory rather than beside the Sidecar itself, so that a Review name
can never collide with another kind of file and `revu-open' has one
directory to read (ADR-0005\\='s amendment).  Nothing is created."
  (expand-file-name (concat name ".md")
                    (revu-directory revu-exports-directory-name path)))

;;;; The review buffer

(defvar-local revu--sidecar nil
  "The Sidecar this review buffer reads and writes its Review through.")

(defvar-local revu--files nil
  "The parsed Source this review buffer renders, as `revu-diff-file's.")

;; `revu-mode-map' is `revu-keymap.el's, and everything that drives a
;; Review is bound there.

(define-derived-mode revu-mode magit-section-mode "Revu"
  "Major mode of the buffer a Source is reviewed in.

The buffer is read-only and is a render of the Review's state: every
command changes the state, writes it to the Sidecar and renders again.
Nothing is edited here, and revu never puts a mode on the reviewer's own
file buffers (ADR-0010)."
  (setq buffer-read-only t)
  ;; A fold the reviewer set outlives the render that built the section
  ;; (ADR-0012), and magit's visibility cache is what makes that true:
  ;; one of these gates the write to it, the other the read back.  Bound
  ;; buffer-locally, so whatever the reviewer configured for magit stands
  ;; everywhere else.
  (setq-local magit-section-cache-visibility t)
  (setq-local magit-section-preserve-visibility t))

(defun revu-buffer-name (name)
  "Return the name of the buffer the Review called NAME is reviewed in."
  (format "*revu: %s*" name))

(defun revu-review ()
  "Return the Review the current buffer is reviewing.
Signal a `user-error' outside a review buffer."
  (unless revu--sidecar
    (user-error "Not in a revu review buffer"))
  (revu-sidecar-review revu--sidecar))

(defvar-local revu--revisions nil
  "How each Revision of this buffer's Source reads, memoised by Revision.
A Revision is immutable and so is what git says about it, so the header
asks git once per buffer rather than once per render: every change to a
Review is a full re-render (ADR-0008), which would otherwise make the
header a git call per keystroke.")

(defun revu--revision-description (revision)
  "Return REVISION as the reviewer sees it: its abbreviated id and its subject.
Fall back to REVISION as the record holds it when git knows no such
commit -- one rebased away, say -- because a Revision nobody can look up
still names what the Review was taken from, and a header is not the place
to raise it."
  (unless revu--revisions
    (setq revu--revisions (make-hash-table :test #'equal)))
  (or (gethash revision revu--revisions)
      (puthash revision
               (or (revu-diff-describe-revision default-directory revision)
                   revision)
               revu--revisions)))

(defun revu--source-description (source)
  "Return the line naming SOURCE at the top of the buffer it is reviewed in.
Each kind is named the way the command that took it was asked for it, so
the line reads back as what the reviewer did: a worktree and an index are
against a Revision, a range is between two, and a plain file is itself."
  (pcase (revu-source-kind source)
    ("worktree" (format "worktree vs %s"
                        (revu--revision-description (revu-source-base source))))
    ("staged" (format "staged vs %s"
                      (revu--revision-description (revu-source-base source))))
    ("range" (format "%s .. %s"
                     (revu--revision-description (revu-source-base source))
                     (revu--revision-description (revu-source-head source))))
    ("file" (format "file %s" (revu-source-path source)))
    ;; A patch names no Revision and no path, so it says which patch it
    ;; is: the digest prefix its Review is named for.
    ("patch" (format "patch %s" (revu-patch-digest-prefix source)))
    (kind kind)))

(defun revu--header-reviewed (review files source)
  "Return the Reviewed figure for FILES, as the header of REVIEW draws it.
A plain-file SOURCE has no hunks to be counted in, so it says the one
word it is in instead (ADR-0011)."
  (if (equal (revu-source-kind source) "file")
      (or (revu-reviewed-state review files (revu-source-path source))
          'unreviewed)
    (revu-reviewed-totals review files)))

(defun revu--header (review placements)
  "Return the `revu-header' the current review buffer opens with.
PLACEMENTS is where this render put the Annotations of REVIEW, so the
orphaned figure counts what the reviewer is looking at and no file is
read a second time."
  (let* ((source (revu-review-source review))
         (name (revu-review-name review))
         (annotations (append (revu-review-annotations review) nil)))
    (revu-header-create
     :name name
     :scratch (revu-review-scratch-name-p name source)
     :source (revu--source-description source)
     :narrowing (revu-source-paths source)
     :kinds (mapcar (lambda (kind)
                      (cons kind
                            (seq-count
                             (lambda (annotation)
                               (equal (revu-annotation-kind annotation) kind))
                             annotations)))
                    revu-annotation-kinds)
     :answered (seq-count #'revu-annotation-reply annotations)
     :orphaned (seq-count (lambda (placement)
                            (eq (revu-render-placement-state placement)
                                'orphaned))
                          placements)
     :reviewed (revu--header-reviewed review revu--files source))))

(defun revu-render ()
  "Render the current review buffer from the state it carries.
Where each Annotation belongs, and the state of its Anchor, is derived
from today's file content on every render and never persisted.  Return
the Placements the render was built from, so that a caller with
something to say about them does not read every file a second time."
  (let* ((review (revu-review))
         (placements (revu-annotate-placements review default-directory)))
    (revu-render-diff revu--files
                      (revu-reviewed-hidden-p review revu--files)
                      placements
                      (revu-reviewed-keep-p review revu--files)
                      (revu-reviewed-state-p review revu--files)
                      (revu--header review placements))
    placements))

(defun revu--file-content (file)
  "Return the content of FILE, or nil when there is no such file.
A plain file that has since been deleted reads as nothing, and the
Annotations on it orphan; revu does not go looking for where it went,
because a plain-file Source follows no rename (ADR-0004)."
  (when (file-regular-p file)
    (with-temp-buffer
      (insert-file-contents file)
      (buffer-string))))

(defun revu--plain-file (path content)
  "Return the `revu-diff-file' the plain file at PATH holding CONTENT renders as.
Every line of the file is carried in one hunk, because ADR-0011 renders a
plain file flat: the hunk is the whole file, and the render puts no
section of its own around it.  A line carries no Origin -- there is no
diff for it to belong to a part of -- so the Annotations made on it
record none either.

CONTENT is nil for a file that has since been deleted, which still marks
the file plain: nothing about it is a diff, and the render says so rather
than falling back to naming a change nobody made."
  (let* ((split (split-string (or content "") "\n"))
         ;; A file's last newline ends its last line rather than opening
         ;; another one.  What is left is every line the file has, blank
         ;; ones included: a file holding one empty line has a line, and
         ;; only a file with no content at all has none.
         (lines (if (and content (string-suffix-p "\n" content))
                    (butlast split)
                  split))
         (number 0))
    (revu-diff-file-create
     :path path
     :plain t
     :content content
     :hunks (unless (or (null content) (string-empty-p content))
              (list (revu-diff-hunk-create
                     :header nil
                     :old-start 1
                     :new-start 1
                     :lines (mapcar (lambda (text)
                                      (list nil (setq number (1+ number)) text))
                                    lines)))))))

(defun revu--source-files (source root)
  "Return the files to render for SOURCE, read anew in the repository at ROOT.
This is how a Source is read again on reload: the Review records what it
was taken from, so a diff can always be taken anew and a plain file read
anew.  A patch is read back from the record itself: the diff text is what
it records, so every file of it is parsed again exactly as it was pasted,
whatever this repository holds (ADR-0005\\='s amendment).
A Source carrying a Narrowing is read again through it, so a narrowed
Review stays narrowed and its Annotations are re-anchored against the
files the reviewer asked for (ADR-0005\\='s amendment)."
  (let ((paths (revu-source-paths source)))
    (pcase (revu-source-kind source)
      ("worktree" (revu-diff-parse
                   (revu-diff-worktree-text root (revu-source-base source)
                                            paths)))
      ("staged" (revu-diff-parse (revu-diff-staged-text root paths)))
      ("range" (revu-diff-parse
                (revu-diff-range-text root
                                      (revu-source-base source)
                                      (revu-source-head source)
                                      paths)))
      ("file" (let ((path (revu-source-path source)))
                (list (revu--plain-file
                       path
                       (revu--file-content (expand-file-name path root))))))
      ("patch" (revu-diff-parse (revu-source-text source)))
      (kind (user-error "Cannot read a %s Source again" kind)))))

;;;###autoload
(defun revu-reload ()
  "Read the Sidecar and the Source again, and render the Review anew.
This is the return leg (ADR-0007): an agent answers a `question' by
writing a Reply, and may append Annotations of its own, and this is where
the reviewer sees them.  Both sides are read in one pass, so the
Annotations are re-anchored against the Source as it is now.

Nothing is merged.  A Sidecar this revu cannot read refuses loudly and
names where the trouble is; the buffer keeps the Review it was showing
and the file is left as the agent wrote it, for the reviewer to look at."
  (interactive)
  (let* ((review (revu-review))
         (files (revu--source-files (revu-review-source review)
                                    default-directory)))
    (revu-sidecar-reload revu--sidecar)
    (setq revu--files files
          ;; A Revision git knew nothing about when the header was first
          ;; drawn may have been fetched since, and a reload is the
          ;; gesture that says so: what a memo of a failed lookup would
          ;; otherwise hold until the buffer was built again.
          revu--revisions nil)
    (revu-render)
    (message "Reloaded %s" (revu-sidecar-file revu--sidecar))))

;;;###autoload
(defun revu-force-write ()
  "Write this Review over whatever is in the Sidecar now.
The way past the write guard, for when the reviewer has read what an
agent wrote and judges it garbage.  Everything the agent put in the file
is lost, which is why this is a command of its own and not what a blocked
Annotation quietly falls back to."
  (interactive)
  (let ((review (revu-review)))
    (revu-sidecar-force-write revu--sidecar review)
    (revu-render)
    (message "Wrote %s over what was there" (revu-sidecar-file revu--sidecar))))

;;;; Naming, reopening and discarding a Review

(defun revu--check-review-name (name)
  "Signal a `user-error' unless NAME is a name a Review can be filed under.
A Review\\='s name is its file name under `reviews/\\=', so a name carrying
a directory separator would file it where `revu-open\\=' never looks and the
Review the rename meant to keep would be the one that went missing."
  (when (or (string-empty-p name)
            (member name '("." ".."))
            (not (equal name (file-name-nondirectory name))))
    (user-error "%s is no name for a Review: it names a file, not a path"
                (if (string-empty-p name) "The empty string" name))))

(defun revu-rename (name)
  "Rename this Review to NAME, moving its Sidecar and its Export with it.
The decision to keep a Review usually arrives after the annotating, so
the scratch bucket a Source opens in is renamed rather than started
again (ADR-0005's amendment).  The write guard holds here like anywhere
else: a Sidecar an agent wrote to since revu read it is not moved out
from under the reviewer, who reloads and looks first."
  (interactive
   (list (read-string "Rename the Review to: " (revu-review-name (revu-review)))))
  (let* ((review (revu-review))
         (old (revu-review-name review))
         (file (revu-sidecar-file-name name default-directory)))
    (revu--check-review-name name)
    (when (equal name old)
      (user-error "This Review is already called %s" name))
    (dolist (taken (list file (revu-export-file-name name default-directory)))
      ;; Both files are checked before either moves: a Review that keeps
      ;; its Export is not renamed on top of one somebody left behind.
      (when (file-exists-p taken)
        (user-error "There is already a Review called %s: %s" name taken)))
    (revu-sidecar-ensure-unchanged revu--sidecar)
    (rename-file (revu-sidecar-file revu--sidecar) file)
    (let ((export (revu-export-file-name old default-directory))
          (renamed (revu-export-file-name name default-directory)))
      (when (file-exists-p export)
        (make-directory (file-name-directory renamed) t)
        (rename-file export renamed)))
    (setf (revu-sidecar-file revu--sidecar) file)
    (revu-sidecar-write revu--sidecar (revu-review-rename review name))
    (rename-buffer (revu-buffer-name name))
    ;; The name is on screen as well as on the buffer: the header says
    ;; which Review this is and whether it is still its Source's scratch
    ;; bucket, and a rename is what changes both.
    (revu-render)
    (message "Renamed %s to %s" old name)))

(defun revu--reviews (root)
  "Return every Review persisted under ROOT, most recently updated first.
Each is a cons of its name and the Review read from its Sidecar.  A file
this revu cannot read is left out: it cannot be opened either, and
`revu-reload' is where a Sidecar an agent broke is meant to be met."
  (let ((directory (revu-directory revu-reviews-directory-name root)))
    (when (file-directory-p directory)
      (sort (delq nil
                  (mapcar (lambda (file)
                            (ignore-errors
                              (cons (file-name-base file)
                                    (revu-sidecar-review
                                     (revu-sidecar-load file)))))
                          (directory-files directory t "\\.json\\'")))
            (lambda (a b) (string> (revu-review-updated (cdr a))
                                   (revu-review-updated (cdr b))))))))

(defun revu--scratch-p (entry)
  "Return non-nil when the Review in ENTRY is the scratch bucket of its Source.
ENTRY is a cons of a name and a Review, and the Review is scratch while
it is still called what its Source derives.  Which names those are is
`revu-review-scratch-name-p\\='s to say: a Review whose name was derived
from Revisions as the reviewer typed them reads as named either way."
  (ignore-errors
    (revu-review-scratch-name-p (car entry) (revu-review-source (cdr entry)))))

(defun revu--read-review (root)
  "Prompt for one of the Reviews persisted under ROOT and return its name.
The most recently updated comes first, and the ones still under a
derived name are marked as the scratch buckets they are."
  (let* ((entries (revu--reviews root))
         (names (mapcar #'car entries)))
    (unless entries
      (user-error "No Review to open under %s"
                  (revu-directory revu-reviews-directory-name root)))
    (completing-read
     "Open Review: "
     (lambda (string predicate action)
       (if (eq action 'metadata)
           `(metadata
             ;; The order here is the answer to "which was I just in?",
             ;; so completion is told to leave it alone.
             (display-sort-function . identity)
             (annotation-function
              . ,(lambda (name)
                   (when (revu--scratch-p (assoc name entries))
                     " (scratch)"))))
         (complete-with-action action names string predicate)))
     nil t)))

;;;###autoload
(defun revu-open (&optional name)
  "Open the Review called NAME, reading its Source again from its record.
Interactively, every Review on disk is offered.  What it is over comes
from the Sidecar rather than from what the reviewer is looking at now,
Narrowing and all, so a Review reopens over what it was taken over."
  (interactive)
  (let* ((root (revu-project-root default-directory))
         (name (or name (revu--read-review root)))
         (review (revu-sidecar-review
                  (revu-sidecar-load (revu-sidecar-file-name name root))))
         (source (revu-review-source review))
         (default-directory root))
    (revu--open source (lambda () (revu--source-files source root)) name)))

(defun revu-discard ()
  "Throw this Review away: its Sidecar, its Export, and its buffer.
The write guard holds, so a Sidecar an agent wrote to since revu read it
refuses to be deleted until the reviewer has reloaded and seen what is
in it."
  (interactive)
  (let ((name (revu-review-name (revu-review)))
        (sidecar revu--sidecar))
    (revu-sidecar-ensure-unchanged sidecar)
    (let ((export (revu-export-file-name name default-directory)))
      (when (file-exists-p export)
        (delete-file export)))
    (delete-file (revu-sidecar-file sidecar))
    (kill-buffer)
    (message "Discarded %s" name)))

(defun revu--read-review-name (source)
  "Prompt for the name of the Review over SOURCE, offering the derived one.
The default is derived from the Source, so accepting it a second time
resumes the Review already there rather than starting another."
  (let ((default (revu-review-name-for-source source)))
    (read-string (format "Review name (default %s): " default)
                 nil nil default)))

(defun revu--name-argument ()
  "Return the NAME an entry command called interactively is to open under.
That is nothing at all, so that the Review opens on the name derived
from its Source without a prompt, unless a prefix argument asks for a
name, which is `ask\\='.  The prefix argument is read here rather than in
the command, so that a caller reaching an entry command from somewhere
else -- the magit Bridge, a test, a reviewer\\='s own Lisp -- never
inherits a prefix argument meant for the command it came from
\(ADR-0005\\='s amendment)."
  (and current-prefix-arg 'ask))

(defun revu--review-name (source name)
  "Return the name of the Review over SOURCE that NAME asks for.
NAME is nil for the name derived from the Source -- that Review is the
Source\\='s scratch bucket, resumed every time it is reviewed again --
`ask\\=' to prompt for one with the derived name offered, and otherwise
the name itself."
  (pcase name
    ('nil (revu-review-name-for-source source))
    ('ask (revu--read-review-name source))
    (_ name)))

(defun revu--parted-revision (then now written)
  "Return WRITTEN and the commit NOW it names, when THEN is another commit.
Return nil when the Revision has not moved, when either commit is
missing, or when the reviewer wrote no name for it: a parting that cannot
be said the way the reviewer wrote it is not worth saying.

THEN is the commit the record holds and NOW the one the name resolves to."
  (when (and written then now (not (equal then now)))
    (cons written now)))

(defun revu--parted-revisions (recorded source names)
  "Return the Revisions of SOURCE that RECORDED has other commits for.
Each is a cons of the Revision as the reviewer wrote it -- NAMES says
which name was written for which field of the Source -- and the commit it
names now.

A staged Source never reads as parted: `git diff --cached\\=' is against
HEAD whatever the record holds, so a staged Review\\='s recorded base says
where a removed line is read from and not what the reviewer is looking
at."
  (delq nil
        (pcase (revu-source-kind source)
          ("worktree"
           (list (revu--parted-revision (revu-source-base recorded)
                                        (revu-source-base source)
                                        (alist-get 'base names))))
          ("range"
           (list (revu--parted-revision (revu-source-base recorded)
                                        (revu-source-base source)
                                        (alist-get 'base names))
                 (revu--parted-revision (revu-source-head recorded)
                                        (revu-source-head source)
                                        (alist-get 'head names)))))))

(defun revu--abbreviated-revision (root revision)
  "Return REVISION as short as ROOT abbreviates it, or as the record carries it.
A Revision this repository no longer has still names what the Review was
taken from, so it is said as it stands rather than not at all."
  (or (revu-diff-abbreviate-revision root revision) revision))

(defun revu--parted-clause (root recorded parted)
  "Return what to say about PARTED having left the Revisions RECORDED carries.
RECORDED is the Source the resumed Review is over and is what the buffer
shows; PARTED is where the names the reviewer wrote have gone since, read
in ROOT.  Return nil when they have gone nowhere."
  (when parted
    (let ((base (revu--abbreviated-revision root (revu-source-base recorded)))
          (head (revu-source-head recorded)))
      (format " against %s (%s)"
              (if head
                  (format "%s..%s" base (revu--abbreviated-revision root head))
                base)
              (mapconcat (lambda (moved)
                           (format "%s is now %s" (car moved)
                                   (revu--abbreviated-revision root (cdr moved))))
                         parted
                         ", ")))))

(defun revu--resumed-message (review root parted placements)
  "Say what opening REVIEW resumed, or nothing when there is nothing to say.
PLACEMENTS is where the render just put its Annotations, so what is
counted is what the reviewer is looking at and no file is read a second
time.  A Review resumes silently for as long as it has nothing in it;
once it does, what was picked up is echoed rather than left to be
discovered, because the scratch bucket of a Source keeps whatever was put
in it the last time and is meant to be no surprise (ADR-0005\\='s
amendment).

PARTED is the Revisions whose names have left the commits REVIEW records,
read in ROOT.  Those are said whether or not the Review carries anything:
the buffer shows the recorded commit but not that the branch has walked
off it."
  (let* ((annotations (seq-length (revu-review-annotations review)))
         (moved (revu--parted-clause root (revu-review-source review) parted))
         (carried
          (when (> annotations 0)
            (format ": %d Annotation%s (%d orphaned)"
                    annotations (if (= annotations 1) "" "s")
                    (seq-count (lambda (placement)
                                 (eq (revu-render-placement-state placement)
                                     'orphaned))
                               placements)))))
    (when (or moved carried)
      (message "Resumed %s%s%s" (revu-review-name review)
               (or moved "") (or carried "")))))

(defun revu--open (source read-files name &optional names)
  "Open the Review called NAME over SOURCE, rendering what READ-FILES gives.
The Sidecar is resumed when one is already there and written when it is
not; the buffer is reused when the Review is already open.  What a
resumed Review carries is echoed.  Return the review buffer.

A Sidecar already there is over a Source of its own, and that Source is
the one rendered: on resume the name is the handle and the record is the
truth, even when the name was written as a branch that has moved since.
So READ-FILES is called only while the record and SOURCE agree, and the
Source the record holds is read anew when they do not -- the first paint
shows what every later `revu-reload\\=' will, and the diff the caller was
about to take against a Revision the Review does not hold is never taken
at all.

NAMES is an alist saying which Revision the reviewer wrote for which
field of SOURCE, so a name that has walked off the recorded commit is
echoed as what it is."
  (let* ((root (revu-project-root default-directory))
         (file (revu-sidecar-file-name name root))
         ;; The record is read before the caller's diff is taken, and
         ;; written only once there is something to render: a Review
         ;; refused for being over nothing leaves no Sidecar behind.
         (resumed (and (file-exists-p file) (revu-sidecar-load file)))
         (recorded (if resumed
                       (revu-review-source (revu-sidecar-review resumed))
                     source))
         (files (if (equal recorded source)
                    (funcall read-files)
                  (revu--source-files recorded root)))
         (sidecar (or resumed
                      (revu-sidecar-open file
                                         (revu-review-create name source))))
         (buffer (get-buffer-create (revu-buffer-name name)))
         (placements nil))
    (with-current-buffer buffer
      (unless (derived-mode-p 'revu-mode)
        (revu-mode))
      (setq default-directory root
            revu--sidecar sidecar
            revu--files files
            placements (revu-render)))
    (pop-to-buffer buffer)
    (revu--resumed-message (revu-sidecar-review sidecar) root
                           (revu--parted-revisions recorded source names)
                           placements)
    buffer))

(defun revu--read-since-revision ()
  "Prompt for the Revision `revu-diff-since\\=' is to review the worktree against.
Completion is over the local branches and tags, and any other Revision
can be written instead: the prompt is a `completing-read\\=' that requires
no match, because git reads far more than revu can list."
  (completing-read "Review the worktree since Revision: "
                   (revu-diff-revision-names
                    (revu-project-root default-directory))
                   nil nil))

(defun revu--narrowing-subject (paths)
  "Return what to say about the Narrowing PATHS in a refusal, or nothing.
A narrowed Source that came up empty is a different thing from an empty
Source, and the reviewer who narrowed from magit never typed the
pathspecs and cannot be expected to guess them."
  (if paths
      (format " under %s" (string-join paths ", "))
    ""))

(defun revu--diff-files (files subject)
  "Return the parsed FILES, or refuse to open a Review over none of them.
SUBJECT says what was diffed and where, and is the whole message a
reviewer gets: an empty diff renders an empty buffer, and a buffer with
nothing in it cannot say whether revu failed, whether the Narrowing
matched nothing, or whether the Source is genuinely empty.  Naming what
was diffed is what makes a Source taken in the wrong project -- the
common way to reach here -- explain itself.  Refusing also keeps a
Sidecar from being written for a Review of nothing."
  (or files (user-error "%s" subject)))

;;;###autoload
(defun revu-diff-worktree (&optional base name paths)
  "Review everything the worktree carries that Revision BASE does not.
BASE defaults to HEAD, which is the everyday reading: staged and
unstaged changes alike, because that is what the reviewer is about to
commit.  Any other Revision widens the Source to what `git diff <base>\\='
shows, which is what a reviewer asking for everything since a tag means.

NAME names the Review, and is the name derived from the Source when it
is nothing; interactively a prefix argument asks for one.  The derived
name is `worktree\\=' for a base naming the commit HEAD names, and carries
BASE as it was written otherwise, so the Review of the worktree does not
fork as HEAD moves and one taken against anything else never resumes it.
The Review itself records the commit BASE resolved to, because that is
what re-anchoring a removed line needs.  PATHS narrows the Source to
those pathspecs; it is never prompted for, so only a caller that means
to narrow -- the magit Bridge -- ever narrows."
  (interactive (list nil (revu--name-argument)))
  (let* ((root (revu-project-root default-directory))
         (head (revu-diff-head-revision root))
         (revision (if base (revu--resolve root base) head))
         ;; A base naming the commit HEAD names is HEAD: the branch that
         ;; is checked out is one way of writing it, and reviewing the
         ;; worktree against it is the Review of what is about to be
         ;; committed rather than a second Review beside it.
         (named-base (unless (equal revision head) base))
         (name (revu--review-name (revu-source-worktree named-base paths)
                                  name))
         (source (revu-source-worktree revision paths)))
    (revu--open source
                (lambda ()
                  (revu--diff-files
                   (revu-diff-parse
                    (revu-diff-worktree-text root revision paths))
                   (format "The worktree at %s carries nothing %s does not%s"
                           root (or base "HEAD")
                           (revu--narrowing-subject paths))))
                name
                `((base . ,(or base "HEAD"))))))

;;;###autoload
(defun revu-diff-since (revision &optional name)
  "Review everything the worktree carries that Revision REVISION does not.
This is the reviewer\\='s \"everything since the tag\": the commits that
landed on top of REVISION and the edits that are not committed yet, read
as one diff.  The Source is the one `revu-diff-worktree\\=' takes against a
base, with the base prompted for rather than passed, and the Review is
the same Review -- `worktree-vs-<revision>\\=', named for the Revision as
it was typed.

Interactively the prompt completes over the repository\\='s local branches
and tags and takes any other Revision as free text, so `HEAD~3\\=', an
abbreviated id or `@{u}\\=' can be written instead.  Nothing is offered as
a default: a reviewer asking for everything since a point knows which
point they mean.

NAME names the Review, and is the name derived from the Source when it
is nothing; interactively a prefix argument asks for one.  A REVISION
naming the commit HEAD names opens the everyday `worktree\\=' Review, and
one naming nothing at all is refused.

Asking again for the same REVISION resumes the Review over the commit it
recorded when it was first opened, whatever the Revision has moved to
since: that commit is what the Annotations already written are anchored
in, so `g\\=' shows what has landed on top of it -- and what is still
uncommitted -- against it."
  (interactive (list (revu--read-since-revision) (revu--name-argument)))
  ;; Resolving here is what refuses a REVISION naming nothing, in the
  ;; words every entry command refuses one with.  Nothing at all is
  ;; refused by the same call: `revu-diff-worktree' reads a base of
  ;; nothing as HEAD, and the worktree since nothing is not the Review
  ;; of what is about to be committed.
  (revu--resolve (revu-project-root default-directory) revision)
  (revu-diff-worktree revision name))

;;;###autoload
(defun revu-diff-staged (&optional name paths)
  "Review what is staged in the index, against HEAD.
NAME names the Review, and is the name derived from the Source when it
is nothing; interactively a prefix argument asks for one.  PATHS narrows
the Source to those pathspecs, and is never prompted for."
  (interactive (list (revu--name-argument)))
  (let* ((root (revu-project-root default-directory))
         (source (revu-source-staged (revu-diff-head-revision root) paths))
         (name (revu--review-name source name)))
    (revu--open source
                (lambda ()
                  (revu--diff-files
                   (revu-diff-parse (revu-diff-staged-text root paths))
                   (format "Nothing is staged in %s to review%s"
                           root (revu--narrowing-subject paths))))
                name)))

;;;###autoload
(defun revu-diff-range (&optional base head name paths)
  "Review what the Revisions BASE and HEAD differ by.
NAME names the Review, and is derived from the Revisions as they were
typed -- `main..feature', not the commits they resolve to -- when it is
nothing; interactively a prefix argument asks for one.  The Review itself
records the commits, because that is what re-anchoring a removed line
needs.  PATHS narrows the Source to those pathspecs, and is never
prompted for: the derived name then carries their slug, so a narrowed
Review resumes itself rather than the full one."
  (interactive (list nil nil (revu--name-argument)))
  (let* ((root (revu-project-root default-directory))
         (base (or base (read-string "Base revision: ")))
         (head (or head (read-string "Head revision: " "HEAD")))
         (name (revu--review-name (revu-source-range base head paths) name))
         (source (revu-source-range (revu--resolve root base)
                                    (revu--resolve root head)
                                    paths)))
    (revu--open source
                (lambda ()
                  (revu--diff-files
                   (revu-diff-parse (revu-diff-range-text root base head paths))
                   (format "%s..%s changes nothing in %s to review%s"
                           base head root (revu--narrowing-subject paths))))
                name
                `((base . ,base) (head . ,head)))))

(defun revu--resolve (root revision)
  "Return the commit REVISION names in ROOT.
Signal a `user-error' when it names none: a Review that cannot say what
it was taken between cannot re-locate a removed line later."
  (or (revu-diff-resolve-revision root revision)
      (user-error "No such revision in this repository: %s" revision)))

;;;###autoload
(defun revu-diff-buffer (&optional buffer name)
  "Review the unified diff already in BUFFER, which defaults to this one.
The diff is a Source of its own and is recorded whole, so a diff from a
mail, a review page or another machine is reviewed like any other Source
and reads back the same way afterwards.  Its `index\\=' headers are neither
required nor looked up: what they name is this repository\\='s business and
a diff taken elsewhere has none of it here.

NAME names the Review, and is derived from the diff text when it is
nothing; interactively a prefix argument asks for one.  The derived name
is `patch-\\=' and a prefix of the text\\='s digest, so pasting the same text
again resumes the same Review and a different text opens a different one.

A buffer with no file diff in it at all is refused, the same way an empty
Source is, and leaves no Sidecar behind."
  (interactive (list nil (revu--name-argument)))
  (let* ((buffer (or buffer (current-buffer)))
         (text (with-current-buffer buffer
                 (buffer-substring-no-properties (point-min) (point-max))))
         (source (revu-source-patch text)))
    (revu--open source
                (lambda ()
                  (revu--diff-files
                   (revu-diff-parse text)
                   (format "%s holds no unified diff to review"
                           (buffer-name buffer))))
                (revu--review-name source name))))

;;;; Plain files

(defun revu--saved-file (file)
  "Return FILE with the reviewer given the chance to save the buffer on it.
Signal a `user-error' when FILE is nothing revu can review: a buffer
visiting no file at all, or one whose file has never been written.  An
Anchor and a Reviewed mark are both taken over what is on disk, and disk
is what an agent reads, so a Source that is not there is refused rather
than guessed at (ADR-0011)."
  (let ((file (or file buffer-file-name)))
    (unless file
      (user-error "This buffer is visiting no file; revu reviews saved files"))
    (let ((buffer (get-file-buffer file)))
      (when (and buffer (buffer-modified-p buffer)
                 (y-or-n-p (format "Save %s before reviewing it? "
                                   (file-name-nondirectory file))))
        (with-current-buffer buffer (save-buffer)))
      (unless (file-regular-p file)
        (user-error "%s has never been written; revu reviews saved files" file))
      (when (and buffer (buffer-modified-p buffer))
        (message "Reviewing what %s holds on disk; the buffer has unsaved edits"
                 (file-name-nondirectory file))))
    file))

(defun revu--goto-line (number)
  "Put point on the rendered line numbered NUMBER of the file under review.
Point opens the buffer when the render carries no such line."
  (goto-char (or (revu-render-target-position
                  (lambda (target) (equal (nth 1 target) number)))
                 (point-min))))

;;;###autoload
(defun revu-file (&optional file name)
  "Review the plain FILE, which defaults to the one this buffer visits.
NAME names the Review, and is the name derived from the Source when it
is nothing; interactively a prefix argument asks for one.

One file is reviewed per Review, flat, with no diff about it (ADR-0011).
What is on disk is what is reviewed, whatever an open buffer on the file
has been edited to since it was last written; a modified buffer is
offered the chance to be saved first.  An active region does one thing
only: it puts point on its first line in the review buffer."
  (interactive (list nil (revu--name-argument)))
  (let* (;; A region says where to start reading, and it says it in the
         ;; visiting buffer's line numbers.  Those describe the disk file
         ;; only while the buffer has not drifted from it, so a buffer
         ;; whose save was declined places point nowhere in particular
         ;; rather than somewhere wrong.
         (line (and (use-region-p)
                    (not (buffer-modified-p))
                    (line-number-at-pos (region-beginning))))
         (file (file-truename (revu--saved-file file)))
         (root (revu-project-root file))
         (path (file-relative-name file root))
         (source (revu-source-file path))
         (name (revu--review-name source name))
         (default-directory root))
    (revu--open source (lambda () (revu--source-files source root)) name)
    (when line
      (with-current-buffer (revu-buffer-name name)
        (revu--goto-line line)))))

(provide 'revu)
;;; revu.el ends here
