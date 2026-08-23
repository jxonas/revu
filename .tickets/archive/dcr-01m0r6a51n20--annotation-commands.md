---
id: dcr-01m0r6a51n20
title: Annotation commands
status: closed
type: task
priority: 1
mode: afk
created: '2026-08-23T20:52:05.811527080Z'
updated: '2026-08-23T22:50:02.310597322Z'
closed: '2026-08-23T22:50:02.310597322Z'
parent: dcr-01m0r63dzcq8
acceptance:
- title: Line, range, hunk, file and review Targets each creatable, editable, deletable from the buffer
  done: true
- title: Every mutation lands in the Sidecar before the command returns
  done: true
- title: Annotations render as foldable child sections at their Anchor lines with Kind and state visible
  done: true
- title: Resume after Source edits shows moved/orphaned badges from derived state
  done: true
deps:
- dcr-01m0r6a4vfzs
- dcr-01m0r6a4yk0t
---

## Description

The core loop becomes real: add an Annotation at point (line), on an active region (range), on a hunk (hunk-as-range), on a file, or on the Review; choose the Kind; write the body via string-edit; edit and delete existing Annotations. Each mutation creates the Anchor, persists atomically to the Sidecar, and re-renders — Annotations appear as addressable child sections at their Anchor lines, badged with derived anchor state, foldable, deletable at point. Resuming a Review renders yesterday's Annotations re-anchored. Cites ADR-0003, ADR-0005, ADR-0008.

## Notes

**2026-08-23T22:50:02.310597322Z**

revu-annotate.el makes the reviewer's loop real: annotate the line at point, an active region as a range, a hunk as a range spanning it, a file, or the Review itself; choose the Kind; write the body with string-edit; edit and delete an Annotation at point. Every mutation runs Anchor, record, atomic Sidecar write, re-render in that order, so the file an agent reads holds the Annotation before the command returns. Annotations render as addressable foldable child sections at their re-located lines, badged with Kind and with anchor state derived on every render and never persisted.

Two anchor-capture bugs found in review and fixed here. An Anchor is now taken in the content the Source's own head side shows -- the worktree, the index, or head:<path> for a range -- so a staged or ranged Annotation records the line the reviewer saw rather than whatever the worktree had drifted to. A removed line is recorded under the path the file had before the diff renamed it, which is the only path it exists under in the base blob. Placement still re-locates against today's worktree, which is what ADR-0006's export of the resolved present needs. A pasted-diff Review records blob ids and so anchors nothing; that is pinned deliberate by a test and noted on dcr-01m0r9smxsrv.
