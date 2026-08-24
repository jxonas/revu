---
id: dcr-01m0rmwaeggd
title: A Reviewed mark has no visual indication beyond collapsing
status: open
type: bug
priority: 2
mode: afk
created: '2026-08-24T01:06:41.230405527Z'
updated: '2026-08-24T01:18:09.000590080Z'
tags:
- render
- reviewed
acceptance:
- title: Reviewed, stale and unreviewed are visually distinct on a hunk heading with every view toggle off
  done: false
- title: The indication survives expanding a collapsed reviewed section
  done: false
- title: A partly reviewed file heading shows how many of its hunks match
  done: false
- title: A plain-file Review shows the state on its file heading
  done: false
- title: 'ADR-0009 amended: collapse is no longer the sole indication, and the three derived states are recorded'
  done: false
- title: CONTEXT.md carries the three states under Reviewed mark
  done: false
links:
- dcr-01m0rkxmpxza
---

## Description

Reported against revu v0 QA. There is no way to look at the buffer and see what has been marked reviewed.

Collapse is the only indication there is, and ADR-0009 says so outright: "marking collapses the section via `magit-insert-section`'s `HIDE` (ADR-0008) and auto-advances point to the next unreviewed section". revu-render.el carries eight faces and none of them is for reviewed state; the render pass knows nothing about marks except the `hidden-p` predicate handed to it.

Part of what the reviewer saw is dcr-01m0rkxmpxza — reviewed sections have never actually collapsed on a render, because the visibility revu resolves is never applied. But fixing that does not close this. Collapse is a poor indicator on its own:

- It is ambiguous. A folded hunk means "reviewed" or "I folded this by hand", and nothing tells the two apart.
- It is self-erasing. Expand a hunk to re-read it and the only evidence it was reviewed is gone.
- It is conditional on a view toggle. With hide-reviewed off, an expanded reviewed hunk is pixel-identical to an unreviewed one.

A mark is a persisted assertion, in ADR-0009's own framing. How it renders should not be a side effect of where a fold happens to be.

## Design

Three rendered states, derived on load and never persisted — the discipline ADR-0003 set for Anchors and ADR-0004 for Path resolution, applied a third time:

- `reviewed` — a mark's digest matches the region's current content
- `stale` — a mark exists for the region but no longer matches it
- `unreviewed` — no mark was ever taken

Carried by a glyph on the hunk or file heading plus a `revu-reviewed` face:

- `reviewed`: a check glyph, heading dimmed. The recessive look is the point — the feature exists to get read work out of the way.
- `stale`: a distinct glyph, struck through or hollow, and not dimmed. This is the case where silence actively misleads: a region an agent changed under the reviewer looks identical to code never read, so rework cannot be told from new work. It is more urgent than either.
- `unreviewed`: nothing, as now.

A file heading shows progress rather than a binary. ADR-0009 persists hunk marks only for diff Sources and renders a file reviewed when every hunk matches, so a file with three of five hunks marked is neither reviewed nor untouched. Show `3/5`. Working down a large Source is the whole use case and "how much of this file is left" is the question being asked; it also makes the file/hunk asymmetry visible instead of surprising.

A plain-file Source persists one mark over the whole content, so the indication lands on the file heading and there is no partial state.

Considered and rejected: a gutter mark beside the line numbers, which survives expanding a section but places the indication at line granularity when ADR-0009 holds marks at hunk granularity — it would claim something the model does not hold. Also rejected: colour alone, which reads as "this is special somehow" rather than naming which state it is.

ADR-0009 needs amending. Its "In the buffer" paragraph makes collapse the indication; it becomes one of two things marking does, alongside the state the heading renders. Its remark that "staleness needs no flag" stays true and should be left standing — it is about persistence, and `stale` is derived.
