---
id: dcr-01m0tp3xyh6a
title: Marking reviewed moves point to the next rendered sibling, never past a collapsed file
status: closed
type: bug
priority: 2
mode: afk
created: '2026-08-24T20:06:48.017193054Z'
updated: '2026-08-24T20:39:35.505149308Z'
closed: '2026-08-24T20:39:35.505149308Z'
acceptance:
- title: With every file collapsed, marking file N puts point on the heading of file N+1, reviewed or not
  done: true
- title: Marking a hunk puts point on the next hunk's heading; marking the last hunk of a file puts it on the next file's heading
  done: true
- title: When the next sibling's heading is inside a collapsed parent, point lands on that parent's heading and no fold is changed
  done: true
- title: Marking a run advances from the last marked section by the same rule
  done: true
- title: With no next sibling, point stays on the marked section's heading; with hide-reviewed on, on the nearest rendered section after where it was, else before
  done: true
- title: Un-marking never moves point
  done: true
- title: The advance tests are rewritten to the new rule and one covers the collapsed-next-file case
  done: true
- title: The Commentary and docstrings describe the rule; CONTEXT.md is untouched
  done: true
links:
- dcr-01m0tp3xvnyq
- dcr-01m0tp3y1th9
---

## Description

With ten files collapsed, pressing `r` on file 1 lands on file 3, `r` on file 3 lands on file 5, and so on: every mark skips a file.

Cause: after marking, the advance seeks the next *unreviewed hunk* in Source order and jumps to it with no invisibility guard. When that hunk sits inside a collapsed file, point is placed inside the fold overlay and Emacs bumps it out at the end of the command, past the whole collapsed file. Two further surprises follow from the same rule: already-reviewed files are skipped silently, and point always lands on a hunk heading, never on a file heading.

## Design

One rule for files and hunks. After *marking*, point goes to the heading of the next sibling in Source order that is rendered, reviewed or not. Marking a hunk goes to the next hunk; the last hunk of a file goes to the next file's heading. If that heading lies inside a collapsed parent, land on the parent's heading instead; folds are never changed by the advance. A run advances from its last marked section. No next sibling: stay on the marked section's heading (with hide-reviewed on, the marked section has left the buffer, so the nearest rendered section after where it was, else the one before). Un-marking never moves point.

Source order rather than buffer order because with hide-reviewed on the marked section is gone from the buffer; the existing code already walks Source order, so this is the same walk minus the unreviewed filter plus the fold guard.

Decided in a grilling session on 2026-08-24, together with the evil j/k bindings and the line-number defcustom.

## Notes

**2026-08-24T20:39:35.505149308Z**

Marking reviewed now advances by one rule for files and hunks: point goes to the heading of the next sibling in Source order that is rendered, reviewed or not -- hunk to hunk within a file, and off the last hunk of a file to the file below it. The old rule sought the next unreviewed hunk with no invisibility guard, so with the files collapsed point was placed inside a fold and Emacs bumped it past the whole file: every mark skipped a file. The fold guard is revu-render-heading-position, sharing the walk revu-render--restore-point already had, and it asks the overlay on screen rather than the hidden slot a render resolved. A run advances from the last section it marked; with no sibling left point stays as near to what was marked as the render allows (its own heading, else the nearest rendered section after it, else before). Unmarking moves point nowhere. Review found the duplicate fold walk and a fallback scan that could land inside the file just marked; both fixed. 239 tests green.
