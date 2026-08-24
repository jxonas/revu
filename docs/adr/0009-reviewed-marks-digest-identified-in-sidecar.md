---
status: accepted
---

# Reviewed marks are digest-identified and persisted in the sidecar

Reviewed-tracking lets the reviewer work through a large Source by marking
hunks and files reviewed and getting them out of the way. The mark is a
persisted assertion; whether it still holds is derived — the same discipline
ADR-0003 set for Anchors.

The sidecar gains one additive field (no schema bump; ADR-0007's tolerant
reader absorbs it):

```json
"reviewed": [{"path": "…", "digest": "…", "span": [4, 12], "created": "…"}]
```

The digest — taken over the marked region's content — *is* the mark's
identity. A rendered hunk is reviewed exactly when some mark's digest matches
its current content, so "staleness" needs no flag: an edited hunk has a new
digest, matches nothing, and renders unreviewed. Hunk boundaries and `@@`
numbers regenerate on every `git diff` and are never part of the identity.

`span` is the base-file lines the marked region covered when the mark was
taken, end exclusive. It is locality, not identity: it takes no part in
matching, and a mark whose span is gone still matches content that hashes to
its digest. It exists so that a mark which has *stopped* matching can be
attributed to the hunk that grew out of those lines — see the derived states
below. The base side is the one that holds still: a diff is taken against a
pinned Revision, so editing the worktree moves a hunk on the new side while
leaving the old lines it grew out of where they were. A pure-insertion hunk
covers no base line, so its span is the single line it was inserted at.
Plain-file marks record no span — the path is their locality — and neither do
marks written by a revu that predates the field; those attribute to nothing.

For diff Sources only hunk marks are persisted. Marking a file reviewed
creates a mark per hunk; a file renders reviewed when every hunk matches.
A separately persisted file mark could read "reviewed" while containing
changed hunks — the lie this design exists to prevent. Plain-file Sources
persist a single mark whose digest covers the file content.

Unmatched marks are kept, not pruned: reverting an edit resurrects the mark
(that content genuinely was reviewed), and pruning would silently delete user
assertions. Reviews are small; the garbage is bytes.

Reviewed state is reviewer-private: Export drops it (revdiff markdown has no
reviewed concept), and the agent contract does not mention it — agents
editing the sidecar preserve unknown fields, which the tolerant-reader
posture already requires in both directions.

Three Reviewed states are derived on load and never persisted — the discipline
ADR-0003 set for Anchors and ADR-0004 for Path resolution, applied a third
time. A region is `reviewed` when a mark's digest matches its current content;
`stale` when a mark was taken over it and no longer matches it — for a hunk,
when some unmatched mark on its path was taken over base lines the hunk still
covers; `unreviewed` when none was ever taken. "Staleness needs no flag"
stands: that is about persistence, and `stale` is derived like the rest.

In the buffer: mark-reviewed is a toggle acting on the section at point
(hunk section marks the hunk, file section the whole file); marking
collapses the section via `magit-insert-section`'s `HIDE` (ADR-0008) and
auto-advances point to the next unreviewed section.

It stops being a toggle as soon as more than one section is being acted on. A
region across sibling headings selects a run, and a run always marks and never
flips: the reviewer is saying "I have read all of this", which is not an answer
that depends on what each section in the run was before, and a flip would unmark
the hunks in it they had already read. Unmarking a run is a prefix argument
instead, and the same argument unmarks the section at point. The records are the
same either way — one mark per hunk, and the Sidecar cannot tell a run from one
press per section (ADR-0008).

Collapse is one of the two things marking does and never the only sign that it
happened. The Reviewed state is rendered as a glyph on the section's heading —
a check for `reviewed`, with the heading dimmed, and a distinct, undimmed
glyph for `stale`. Being heading text, it survives expanding a collapsed
section and is independent of the view toggles. A diff file heading carries how
many of its hunks match out of how many it has while it is part-way read;
a plain file has no hunks to divide it, so it carries the glyph alone. Two buffer-local view
toggles — annotated-only and hide-reviewed — are predicates on the render
pass. Reviewed and annotated are orthogonal: a hunk with an open `question`
can be marked reviewed; the annotated-only filter keeps it findable. Key
bindings are deliberately not fixed here — they belong to the package-wide
keymap-and-evil ticket.

## Considered options

- Session-only state: loses the reviewer's place across restarts, which guts
  the feature for the large Sources it exists for.
- Dumb persisted flags: survive edits they shouldn't, showing changed code as
  reviewed.
- Hard-clearing or pruning marks on mismatch: deletes assertions the user
  made and forfeits resurrection-on-revert.
- Persisting file-level marks for diffs: allows a file to claim reviewed
  while its hunks changed underneath.
- Collapse as the sole indication: ambiguous against a hand-made fold,
  self-erasing on expand, and absent entirely with hide-reviewed off.
- Deriving `stale` per hunk from path and digest alone: underdetermined. A
  dangling mark says something under this path was read and changed, not
  which hunk, so a hunk nobody read would be shown as rework — the same
  class of lie file-level marks were rejected for.
- Attributing a mark by the `@@` header it was taken under: the header
  regenerates exactly when the content changes, so it is useless in the one
  case `stale` exists for. (The span may later serve the hunk-identity
  problem that header text causes elsewhere; that is a separate decision.)
- A gutter mark beside the line numbers: survives expanding, but places the
  indication at line granularity when marks are held at hunk granularity.
- Colour with no glyph: reads as "this is special somehow" rather than
  naming which state it is.
