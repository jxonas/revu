---
id: dcr-01m0rmwaeggd
title: A Reviewed mark has no visual indication beyond collapsing
status: closed
type: bug
priority: 2
mode: afk
created: '2026-08-24T01:06:41.230405527Z'
updated: '2026-08-24T12:42:35.113351301Z'
closed: '2026-08-24T12:42:35.113351301Z'
tags:
- render
- reviewed
acceptance:
- title: Reviewed, stale and unreviewed are visually distinct on a hunk heading with every view toggle off
  done: true
- title: The indication survives expanding a collapsed reviewed section
  done: true
- title: A partly reviewed file heading shows how many of its hunks match
  done: true
- title: A plain-file Review shows the state on its file heading
  done: true
- title: 'ADR-0009 amended: collapse is no longer the sole indication, and the three derived states are recorded'
  done: true
- title: CONTEXT.md carries the three states under Reviewed mark
  done: true
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

## Notes

**2026-08-24T12:42:35.113351301Z**

A heading now carries the Reviewed state as a glyph: a check, dimmed, for reviewed, and an undimmed 'not equal to' for stale. Being heading text it survives opening a collapsed section and owes nothing to the view toggles, so collapse is one of two things marking does rather than the only sign it happened. A diff file part-way read shows how many of its hunks match (1/2); a plain file wears the glyph alone.

The three states are derived on every render and never persisted, the discipline ADR-0003 and ADR-0004 already set. Deriving 'stale' per hunk forced the one design decision here, and it is a schema addition: a digest matching nothing says something under this path was read and changed, not which region, so attributing it by path alone would badge a hunk nobody read as rework -- the same class of lie ADR-0009 rejected file-level marks for. A mark now also records the base-file lines its region covered. That is locality and not identity: it takes no part in matching, the base side holds still while the worktree moves, and a mark with no span (a plain file's, or one an older revu wrote) attributes to nothing. The field is additive and the old validator only ever checked the digest, so old Sidecars still load. ADR-0009 records all of it, including the rejected alternatives.

AC6 was already half met by e351355: the three states live in a sibling 'Reviewed state' glossary entry rather than literally under 'Reviewed mark', which is the better split and was kept. The 'Reviewed mark' entry gained the span.

Deriving the states also had to stay cheap. The first cut asked the marks about a path once per hunk and hashed the whole file to answer, which is the render cost dcr-01m0rne3grr6 had just finished killing; the marks on a path are now found before any digest is taken, and the render memoises the answer by path. 170 tests, lint and compile green.
