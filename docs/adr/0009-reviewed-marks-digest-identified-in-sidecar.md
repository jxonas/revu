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
"reviewed": [{"path": "…", "digest": "…", "created": "…"}]
```

The digest — taken over the marked region's content — *is* the mark's
identity. A rendered hunk is reviewed exactly when some mark's digest matches
its current content, so "staleness" needs no flag: an edited hunk has a new
digest, matches nothing, and renders unreviewed. Hunk boundaries and `@@`
numbers regenerate on every `git diff` and are never part of the identity.

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

In the buffer: mark-reviewed is a toggle acting on the section at point
(hunk section marks the hunk, file section the whole file); marking
collapses the section via `magit-insert-section`'s `HIDE` (ADR-0008) and
auto-advances point to the next unreviewed section. Two buffer-local view
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
