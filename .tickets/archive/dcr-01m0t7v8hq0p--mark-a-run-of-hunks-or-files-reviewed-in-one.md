---
id: dcr-01m0t7v8hq0p
title: Mark a run of hunks or files reviewed in one gesture
status: closed
type: feature
priority: 2
mode: afk
created: '2026-08-24T15:57:23.895567324Z'
updated: '2026-08-24T17:06:19.322777963Z'
closed: '2026-08-24T17:06:19.322777963Z'
acceptance:
- title: A region spanning sibling hunk headings marks every hunk in it reviewed
  done: true
- title: A region spanning sibling file headings marks every file in it reviewed
  done: true
- title: A region inside one hunk's body still annotates a range, unchanged
  done: true
- title: A selection containing already-reviewed sections marks the rest and unmarks nothing
  done: true
- title: A prefix argument unmarks the selection, or the section at point when there is none
  done: true
- title: Sections with nothing to mark are skipped and the skip is reported
  done: true
- title: A selection with nothing markable in it raises a user-error
  done: true
- title: The whole gesture writes the Sidecar once and renders once
  done: true
- title: Point lands on the first unread hunk after the marked run, with hide-reviewed on and off
  done: true
- title: A hand-folded hunk outside the selection keeps its fold across the render
  done: true
- title: ADR-0008 carries the region disambiguation rule
  done: true
links:
- dcr-01m0t3rkpff2
---

## Description

Every revu command acts on one section, the section point is in. A reviewer who
skims eight hunks of a lockfile has to press `r` eight times.

There is also a mismatch in the buffer today. `magit-section-mode` installs
`magit-section--highlight-region` as `redisplay-highlight-region-function` and
runs `magit-section-update-highlight` on every command, so dragging across two
hunk headings already suppresses the normal region overlay and paints a section
selection. No revu command honours it: `a` annotates the raw line range anyway.
The buffer promises a gesture revu does not have. This ticket is what makes the
promise true; the mismatch is not separately fixable.

Marking is the whole scope. Annotating a selection is out: it would need a
Target kind spanning several files, which ADR-0003 deliberately refuses.

## Design

Settled by design review. Every point below was decided against the source, not
assumed.

**Gesture.** The region, read two ways. A region inside one section's body is a
run of Source lines and still annotates as a range. A region spanning sibling
headings is a section selection and marks. `magit-section-internal-region-p`
decides between them; `magit-region-sections` returns the run.

**Records.** One mark per hunk, as marking a file already produces (ADR-0009).
The selection is a gesture, never persisted, and is not domain language: it goes
in no Sidecar and no glossary entry.

**Membership.** No condition filter on the selection. A placed Annotation
renders inside its hunk section, so it is a child, not a sibling, and a drag
across annotated hunks never selects one. Only unplaced and loose Annotations
are siblings, and they render before everything markable, so one enters a
selection only when the drag starts on it. Mark every selected section that has
assertions, skip the rest, and report the skip. Raise a `user-error` only when
nothing in the selection was markable.

**Semantics.** A selection always marks and never flips, so already-read hunks
inside the run survive. A prefix argument unmarks, over a selection or over the
section at point.

**Write.** Accumulate every mark into one Review value, write the Sidecar once,
render once. N writes would mean N renders, and the render is the expensive part
on a large Source. This means lifting the marking out of `revu-reviewed-toggle`
into a pure function over the Review and leaving the write at the edge.

**Point.** Advance from the end of the last marked section. When
`revu-reviewed-hide-reviewed` is on the marked run is gone from the render, so
advance from the position the first selected section occupied; falling back to
`point` can leave the reviewer above the run and re-offer hunks they just read.

**Folds.** Run `revu-reviewed--forget-visibility` once per marked section, so a
hand-folded hunk outside the selection keeps its fold.

**Name.** `revu-reviewed-toggle` keeps its name and `r` keeps its binding
(ADR-0010). Only the docstring changes, to say what happens in both cases.

**Record.** Amend ADR-0008 with the disambiguation rule: it is the ADR that drew
the magit-section boundary, and the region's two meanings is a user-facing
contract a future reader will question. Nothing goes into CONTEXT.md.

## Notes

**2026-08-24T17:06:19.322777963Z**

The region now marks. A run of sibling hunk or file headings selected with the region marks every section in it in one gesture: one Review value, one Sidecar write, one render, and point left on the first hunk after the run that has not been read.

magit-region-sections draws the line between the region's two meanings. Inside a section's body the region is still a run of Source lines and still annotates as a range; across sibling headings it is a section selection and marks. The named alternative, magit-section-internal-region-p, turned out to be redundant against it -- it answers for exactly the case magit-region-sections already refuses -- so the disambiguation is one call, and ADR-0008 carries the rule.

A selection marks and never flips, so hunks already read inside a run keep their marks; a prefix argument unmarks, over a selection or over the section at point. Sections with nothing to assert are passed over and the skip is reported; a selection with nothing markable in it is a user-error. Folds are forgotten once per marked section, so a hand-folded hunk outside the run keeps its fold.

Point advances over the Source's order rather than the buffer's, which is one path for hide-reviewed on and off instead of the two the design proposed: with the filter on there is no section left in the buffer to walk on from, and a position taken before the render is wrong as soon as the file heading above the run leaves too.

ADR-0009 was amended as well as ADR-0008: it recorded mark-reviewed as a toggle, and over a run it is not one. 13 tests added; 200 pass.
