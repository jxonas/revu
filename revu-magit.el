;;; revu-magit.el --- Review what magit was about to diff  -*- lexical-binding: t; -*-

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

;; The magit Bridge (ADR-0013), and the one place revu reaches past
;; `magit-section' into magit proper.  It is **experimental**: the
;; switch, the advice and everything the mapping below decides may
;; change or be taken away.
;;
;; `revu-magit-mode' appends a "Review in revu" switch to the
;; `magit-diff' transient and advises the three functions every magit
;; diff command funnels through.  With the switch on, magit's own
;; commands -- `d d', `d r', `d s', `d u', `d w', `d c' -- open a Review
;; over what magit was about to show instead of a diff buffer.  With the
;; mode off, magit is untouched: nothing here is loaded by revu's core,
;; and the mode requires magit only when it is turned on.
;;
;; What the mapping decides lives in `revu-magit-plan' and
;; `revu-magit-revision-plan', which know nothing about magit: they take
;; the recipe magit built and return the revu command to run.  The
;; advice does the wiring and nothing else.
;;
;; The bridge needs magit 4.4 or later.

;;; Code:

(require 'seq)
(require 'transient)
(require 'revu)

;; The three funnels every magit diff command passes through, with the
;; arities the advice below stands on.  Declared rather than required:
;; nothing in revu's core loads magit, and this file loads it only when
;; `revu-magit-mode' is turned on.
(declare-function magit-diff-setup-buffer "ext:magit-diff"
                  (range typearg args files &optional type locked))
(declare-function magit-revision-setup-buffer "ext:magit-diff"
                  (rev args files))
(declare-function magit-stash-setup-buffer "ext:magit-stash"
                  (stash args files))
(defvar magit-version)

(defconst revu-magit--minimum-magit-version "4.4"
  "The oldest magit the Bridge is willing to reach into.
The funnels it advises were settled in 4.4, and a `boundp' shim for
what came before is the kind of code that rots unnoticed (ADR-0013).")

(defconst revu-magit--switch-argument "--revu"
  "The argument the Bridge switch adds to the arguments magit collects.
The switch travels in magit's diff arguments, so it is stripped out
before anything reads those as arguments to git.")

(defconst revu-magit--silent-arguments '("--stat" "--no-ext-diff")
  "The magit diff arguments the Bridge drops without saying so.
These are magit's own defaults and neither changes how a change is cut:
`--stat' asks magit for a summary section revu does not render, and
revu's own diffs already pass `--no-ext-diff'.  Reporting them would
mean reporting every invocation, which says nothing.")

;;;; Reading magit's arguments

(defun revu-magit--switch-on-p (arguments)
  "Return non-nil when ARGUMENTS carry the Bridge switch."
  (and (member revu-magit--switch-argument arguments) t))

(defun revu-magit--strip-switch (arguments)
  "Return ARGUMENTS without the Bridge switch.
The switch belongs to revu and not to git, so nothing downstream sees it."
  (remove revu-magit--switch-argument arguments))

(defun revu-magit--dropped-arguments (arguments)
  "Return the diff arguments in ARGUMENTS that revu drops on the floor.
Context count, whitespace and rename flags change how a change is cut,
which is what Reviewed-mark digests and Path resolution key on, so revu
pins its own and honours none of magit's (ADR-0013)."
  (seq-remove (lambda (argument)
                (member argument revu-magit--silent-arguments))
              (revu-magit--strip-switch arguments)))

(defun revu-magit--caveats (arguments type)
  "Return what the reviewer should be told about ARGUMENTS and TYPE.
A list of sentences, empty when the Review is exactly what magit was
about to show."
  (let ((dropped (revu-magit--dropped-arguments arguments))
        (notes nil))
    (when (eq type 'unstaged)
      (push (concat "revu has no index-to-worktree Source; "
                    "reviewing the whole worktree")
            notes))
    (when dropped
      (push (format "revu pins its diff arguments; dropped %s"
                    (string-join dropped " "))
            notes))
    (nreverse notes)))

;;;; The mapping

(defun revu-magit--abbreviate (revision)
  "Return REVISION shortened when it is a full object id, else as it stands.
A branch name is already the name a reviewer would use.  An object id is
not: names reach the Bridge from magit as full ids, and a Review called
after one reads the way magit's log shows it, which is git's own
abbreviation.  The name is prompted for, so the reviewer has the last
word on it."
  (if (string-match-p "\\`[[:xdigit:]]\\{40,\\}\\'" revision)
      (or (revu-diff-abbreviate-revision (revu-magit--root) revision) revision)
    revision))

(defun revu-magit--root ()
  "Return the root of the repository the Bridge is reading a recipe in."
  (revu-project-root default-directory))

(defun revu-magit--range (base head paths)
  "Return the plan reviewing what Revisions BASE and HEAD differ by.
PATHS is the Narrowing, and may be nil."
  (cons 'revu-diff-range (list (revu-magit--abbreviate base)
                               (revu-magit--abbreviate head)
                               nil paths)))

(defun revu-magit--endpoint (revision)
  "Return REVISION, or \"HEAD\" for the end of a range magit left out.
A range with an end missing is that end read as HEAD, which is the diff
git takes and what `magit-diff-range' says it shows."
  (if (or (null revision) (string-empty-p revision)) "HEAD" revision))

(defun revu-magit--against-head (revision subject plan)
  "Return PLAN when REVISION is HEAD, or why revu will not review SUBJECT.
The worktree and staged Sources are both taken against HEAD, so the
revision magit read from a prefix argument is refused rather than
quietly reviewed as HEAD.  The two are compared as the commits they
name, not as the strings they were written as, since the branch that is
checked out is HEAD.  A REVISION of nil is magit naming none, which is
HEAD by default."
  (let* ((root (revu-magit--root))
         (commit (and revision (revu-diff-resolve-revision root revision))))
    (cond
     ((null revision) plan)
     ((null commit)
      (cons 'refuse (format "No such revision in this repository: %s"
                            revision)))
     ((not (equal commit (revu-diff-resolve-revision root "HEAD")))
      (cons 'refuse (format "The %s is reviewed against HEAD; \
revu has no Source against %s" subject revision)))
     (t plan))))

(defun revu-magit--merge-base (a b paths)
  "Return the plan a three-dot range from A to B maps to, or a refusal.
A Source records the commits it was taken between, so the three-dot
notation is resolved here: what is reviewed is where A and B last
diverged, against B.  PATHS is the Narrowing, and may be nil."
  (let ((base (revu-diff-merge-base (revu-magit--root) a b)))
    (if base
        (revu-magit--range base b paths)
      (cons 'refuse (format "%s and %s share no history to review along"
                            a b)))))

(defun revu-magit-plan (range typearg files type)
  "Return what revu does with the diff magit built out of RANGE and TYPEARG.
FILES are magit's pathspecs and TYPE is the diff type magit settled on:
together with RANGE and TYPEARG they are the whole recipe every
`magit-diff' action funnels through.

Return either a cons of the revu command to run and the arguments to
run it with, or `refuse' consed onto why revu will not.  Every decision
the Bridge makes is made here, and none of it needs magit loaded.

A committed range passes through as magit built it, so a commit
selection in a log reviews `oldest..newest' with the oldest left out --
what `d d' would have shown.  `A...B' resolves to where A and B last
diverged, and a lone revision is the worktree against it, because that
is the diff git would have taken."
  (let ((paths (append files nil)))
    (cond
     ((or (equal typearg "--no-index") (eq type 'undefined))
      (cons 'refuse
            "A --no-index diff spans no Revisions for revu to review"))
     ((equal typearg "--cached")
      (revu-magit--against-head range "index"
                                (cons 'revu-diff-staged (list nil paths))))
     ((eq type 'unstaged)
      (revu-magit--against-head (revu-magit--endpoint range) "worktree"
                                (cons 'revu-diff-worktree (list nil paths))))
     ((null range)
      (cons 'refuse "This diff names no Revisions for revu to review"))
     ((string-match "\\`\\(.*\\)\\.\\.\\.\\(.*\\)\\'" range)
      (revu-magit--merge-base (revu-magit--endpoint (match-string 1 range))
                              (revu-magit--endpoint (match-string 2 range))
                              paths))
     ((string-match "\\`\\(.*\\)\\.\\.\\(.*\\)\\'" range)
      (revu-magit--range (revu-magit--endpoint (match-string 1 range))
                         (revu-magit--endpoint (match-string 2 range))
                         paths))
     ;; Anything else names one revision, and `git diff REV\=' is the
     ;; worktree against it.  A range notation revu cannot take two
     ;; Revisions out of resolves as no revision at all, and refuses
     ;; there rather than being guessed at here.
     (t (revu-magit--against-head range "worktree"
                                  (cons 'revu-diff-worktree (list nil paths)))))))

(defun revu-magit-revision-plan (rev files)
  "Return what revu does with the revision REV magit was about to show.
FILES are magit's pathspecs.  A commit is reviewed as `commit^..commit',
and both ends are resolved, so that a Review named after `HEAD' does not
come to mean a different range tomorrow.  Return the same shapes
`revu-magit-plan' returns."
  (let* ((root (revu-magit--root))
         (commit (revu-diff-resolve-revision root rev))
         (parent (and commit (revu-diff-resolve-revision
                              root (concat commit "^")))))
    (cond
     ((null commit)
      (cons 'refuse (format "No such revision in this repository: %s" rev)))
     ((null parent)
      (cons 'refuse
            (format "%s is a root commit; revu reviews a range with a base"
                    rev)))
     (t (revu-magit--range parent commit (append files nil))))))

;;;; Running a plan

(defun revu-magit--run (plan notes)
  "Carry out PLAN, then tell the reviewer NOTES.
A refusal is a `user-error': the Review revu would have opened is not
the diff magit was about to show, and opening it anyway would be the
surprise.  The notes come after the Review is open so that the name
prompt does not wipe them off the echo area."
  (pcase-let ((`(,command . ,arguments) plan))
    (when (eq command 'refuse)
      (user-error "%s" arguments))
    (prog1 (apply command arguments)
      (when notes
        (message "%s" (string-join notes "; "))))))

(defun revu-magit--diff-setup (original range typearg args files
                                        &optional type locked)
  "Open a Review instead of the diff buffer ORIGINAL would set up.
Only when the Bridge's switch is in ARGS; otherwise magit gets its
buffer, built from RANGE, TYPEARG, ARGS, FILES, TYPE and LOCKED exactly
as it asked for it."
  (if (not (revu-magit--switch-on-p args))
      (funcall original range typearg args files type locked)
    (revu-magit--run (revu-magit-plan range typearg files type)
                     (revu-magit--caveats args type))))

(defun revu-magit--revision-setup (original rev args files)
  "Open a Review over REV instead of the buffer ORIGINAL would set up.
Only when the Bridge's switch is in ARGS; otherwise magit gets its
buffer over REV, ARGS and FILES."
  (if (not (revu-magit--switch-on-p args))
      (funcall original rev args files)
    (revu-magit--run (revu-magit-revision-plan rev files)
                     (revu-magit--caveats args 'committed))))

(defun revu-magit--stash-setup (original stash args files)
  "Refuse to review STASH, or let ORIGINAL set up its buffer over ARGS and FILES.
A stash is not a Source revu has, and the Bridge does not invent one."
  (if (not (revu-magit--switch-on-p args))
      (funcall original stash args files)
    (user-error "There is no revu Source for a stash; %s stays in magit"
                stash)))

;;;; The mode

(transient-define-argument revu-magit-switch ()
  "Open what this diff command was about to show in a revu Review.

Every action of the `magit-diff' transient reads this switch, so `d d',
`d r', `d s', `d u', `d w' and `d c' each open a Review over the diff
they would have shown.  `C-x s' saves it on, which is the \"I review in
revu\" posture; toggling it off gives magit back.

Two things worth knowing, because magit does not say them and revu
inherits them:

A commit selection in a log reviews `oldest..newest', which leaves the
oldest selected commit's own changes out.  That is the range magit's
`d d' builds from the same selection, and reviewing a different one
would be the surprise.

Every other diff argument is dropped, and revu says so when any were
set: context count, whitespace and rename flags change how a change is
cut, and revu pins its own.  A `--no-index' diff and a stash are
refused outright.

Experimental: this switch and what it maps onto may change."
  :class 'transient-switch
  :key "-v"
  :description "Review in revu"
  ;; Spelled out rather than read from `revu-magit--switch-argument':
  ;; transient stores this plist as it is written.
  :argument "--revu")

(defun revu-magit--install ()
  "Put the Bridge's switch and advice in place, loading magit first."
  (require 'magit)
  (when (ignore-errors
          (version< magit-version revu-magit--minimum-magit-version))
    (user-error "The Bridge needs magit %s or later, and this is %s"
                revu-magit--minimum-magit-version magit-version))
  ;; Appended beside the transient's own actions rather than into
  ;; `magit-diff-infix-arguments', which `magit-diff-refresh' shares:
  ;; refreshing a diff buffer is not a place the switch can do anything.
  (transient-append-suffix 'magit-diff "t" '(revu-magit-switch))
  (advice-add 'magit-diff-setup-buffer :around #'revu-magit--diff-setup)
  (advice-add 'magit-revision-setup-buffer :around
              #'revu-magit--revision-setup)
  (advice-add 'magit-stash-setup-buffer :around #'revu-magit--stash-setup))

(defun revu-magit--remove ()
  "Take the Bridge's switch and advice back out, leaving magit as it was."
  (advice-remove 'magit-diff-setup-buffer #'revu-magit--diff-setup)
  (advice-remove 'magit-revision-setup-buffer #'revu-magit--revision-setup)
  (advice-remove 'magit-stash-setup-buffer #'revu-magit--stash-setup)
  (when (fboundp 'transient-remove-suffix)
    (ignore-errors
      (transient-remove-suffix 'magit-diff 'revu-magit-switch))))

;;;###autoload
(define-minor-mode revu-magit-mode
  "Route magit's diff commands into a revu Review.

Turning the mode on loads magit, appends the `revu-magit-switch' switch
to the `magit-diff' transient and advises the three functions magit's
diff commands funnel through.  With the switch on, those commands open
a Review over the diff they were about to show.  Turning the mode off
takes the switch and the advice back out; a magit that never saw this
mode is untouched, and revu's core never loads magit.

A commit selection in a log reviews `oldest..newest', with the oldest
selected commit's own changes left out -- magit's own semantics, since
these are magit's own commands.  See `revu-magit-switch' for the rest of
what the mapping decides.

Experimental (ADR-0013): the switch, the advice and the Narrowing a
Source carries may change or be removed.  Needs magit 4.4 or later."
  :global t
  :group 'revu
  (if revu-magit-mode
      (condition-case error
          (revu-magit--install)
        (error (setq revu-magit-mode nil)
               (signal (car error) (cdr error))))
    (revu-magit--remove)))

(provide 'revu-magit)
;;; revu-magit.el ends here
