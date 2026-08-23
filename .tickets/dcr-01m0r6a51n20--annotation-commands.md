---
id: dcr-01m0r6a51n20
title: Annotation commands
status: open
type: task
priority: 1
mode: afk
created: '2026-08-23T20:52:05.811527080Z'
updated: '2026-08-23T20:52:05.811527080Z'
parent: dcr-01m0r63dzcq8
acceptance:
- title: Line, range, hunk, file and review Targets each creatable, editable, deletable from the buffer
  done: false
- title: Every mutation lands in the Sidecar before the command returns
  done: false
- title: Annotations render as foldable child sections at their Anchor lines with Kind and state visible
  done: false
- title: Resume after Source edits shows moved/orphaned badges from derived state
  done: false
deps:
- dcr-01m0r6a4vfzs
- dcr-01m0r6a4yk0t
---

## Description

The core loop becomes real: add an Annotation at point (line), on an active region (range), on a hunk (hunk-as-range), on a file, or on the Review; choose the Kind; write the body via string-edit; edit and delete existing Annotations. Each mutation creates the Anchor, persists atomically to the Sidecar, and re-renders — Annotations appear as addressable child sections at their Anchor lines, badged with derived anchor state, foldable, deletable at point. Resuming a Review renders yesterday's Annotations re-anchored. Cites ADR-0003, ADR-0005, ADR-0008.
