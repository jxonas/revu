---
status: experimental
---

# The magit bridge is a transient switch and advice on magit's diff-setup funnels

A reviewer who has magit wants to pick what to review with magit's own
commands -- a commit selection in a log, `d r`'s range prompt, `d p`'s
pathspecs, staged, worktree, a commit -- and read it in revu. The obvious
bridge is a "review in revu" action appended to the `magit-diff` transient.
We build the other thing: a "review in revu" *switch* in that transient,
and advice on `magit-diff-setup-buffer` and `magit-revision-setup-buffer`
that, when the switch is on, strips it from the arguments and opens a Review
over what magit was about to show instead of a `magit-diff` buffer.

Why the switch rather than an action: an action has to reproduce magit's
DWIM and its prompts to get the same diff magit would have shown, and it
cannot be saved as a default. The two setup functions are the single funnel
every `magit-diff` action passes through, their signatures carry the whole
recipe -- `(range typearg args files type)` and `(rev files)` -- and neither
is double-dash private. Advising them is a deliberate reach past the line
ADR-0008 draws at `magit-section`, and it is the only one: the bridge lives
in its own `revu-magit.el`, behind a global minor mode `revu-magit-mode`
that is off by default, installs the advice and the switch on enable, and
removes both on disable. The core of revu never loads magit.

What the advice maps, and what it refuses:

- A `committed` range passes through as it was built. A commit selection in
  a log therefore reviews `oldest..newest`, oldest excluded, because that is
  what magit's DWIM builds and a `d d` that reviewed a different range than
  it diffs would be the surprise. Magit does not document the exclusion; the
  switch's docstring does. `A...B` becomes `merge-base(A,B)..B`, since a
  Source records commits. A commit from `d c` is `commit^..commit`.
- `staged` is the staged Source. `unstaged` widens to the worktree Source
  with a message: revu has no index-to-worktree Source, and the reviewer's
  intent from the unstaged section is what the worktree Source already
  defines itself as. Adding an unstaged Source is a domain change and does
  not ride in on a bridge.
- Pathspecs (`magit-buffer-diff-files`) become the Source's `paths`
  (ADR-0005 amendment). Every other diff argument is dropped, and the
  reviewer is told when any were set: context count, whitespace and rename
  flags change how a change is cut, which is what Reviewed-mark digests and
  Path resolution key on, so revu pins them.
- `--no-index` (`undefined` type) and stashes refuse with a `user-error`.
  There are no Revisions in the first and no stash Source for the second.

Revision names arrive from magit as full object ids; the derived Review
name abbreviates them the way magit's log shows them. The name is still
prompted for, so that a reviewer who accepts it twice resumes the same
Review.

The switch may be saved as a default with transient's `C-x s`. That makes
every `d` action open revu until it is toggled off, which is the "I review
in revu" posture, chosen by the reviewer. Refusing it would mean
special-casing transient's persistence.

The bridge requires magit 4.4 or later: the buffer-local names it reads
(`magit-buffer-diff-range`, `magit-buffer-diff-typearg`,
`magit-buffer-revision-oid`) were renamed in 4.4 with no obsolete aliases,
and `boundp` shims for 4.3 are the kind of code that rots unnoticed.

**Experimental.** The mapping is pure and is unit-tested with magit absent;
magit is a development dependency for byte-compilation only, not a test
dependency. The advice, the switch and `source.paths` may change or be
removed. Graduating is editing this file's status and, if the bridge
survives, revisiting whether a fixture-driven test of the advice earns its
dependency tree.

## Considered options

- An action suffix `("v" "Review in revu")` reading `(transient-args
  'magit-diff)` for pathspecs and `magit-diff--dwim` for endpoints: no
  advice, no reach past ADR-0008's line, but it calls a double-dash function,
  re-implements what `d r` and `d p` prompt for, and cannot be a saved
  default. Kept as the fallback if the advice proves brittle across magit
  releases.
- Honouring magit's diff arguments in full, with the Source recording them:
  turns revu into a renderer for arbitrary `git diff` invocations, and every
  argument that breaks the parser, the Anchors or Path resolution (`--stat`,
  `-R`, `--ext-diff`, rename thresholds) needs a denylist. Rejected with the
  pathspec-only Source instead.
- Including the oldest selected commit (`oldest^..newest`): what "review
  these commits" means, but it diverges from `d d` on the same selection and
  needs a root-commit special case. Rejected under the switch model, where
  the reviewer is running magit's commands and magit's semantics apply.
