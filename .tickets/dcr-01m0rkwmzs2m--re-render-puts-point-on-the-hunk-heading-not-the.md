---
id: dcr-01m0rkwmzs2m
title: Re-render puts point on the hunk heading, not the line the reviewer was on
status: open
type: bug
priority: 2
mode: afk
created: '2026-08-24T00:49:23.448882726Z'
updated: '2026-08-24T01:19:12.321904581Z'
tags:
- render
- ux
acceptance:
- title: Point returns to the same source line, not the hunk heading, after annotate/edit/delete
  done: false
- title: Point returns to the same source line after revu-reload when lines were added above it
  done: false
- title: Point falls back sanely when the line it was on is gone from the Source
  done: false
- title: The column is restored along with the line
  done: false
- title: window-start is restored, so the view does not jump when point survives
  done: false
links:
- dcr-01m0rkx3k23r
- dcr-01m0rkxmpxza
---

## Description

Every re-render moves point to the start of the enclosing section. On a hunk, that is the hunk heading, so the reviewer loses their line on every annotate, edit, delete, Reviewed-mark toggle, filter toggle, force-write and reload.

Reported against revu v0 QA (Doom Emacs, Emacs 30.2.50, Magit b6c5125, Transient 0.13.5, Git 2.54.0). Reproduces on both `revu-diff-range` and annotation insertion/deletion.

Cause is not incidental. `revu-render--restore-point` (revu-render.el:353) is written to do this:

    (let ((section (revu-render-section-with-value (car state))))
      (if section
          (goto-char (oref section start))
        (goto-char (point-min))
        (forward-line (1- (cdr state)))))

`revu-render--point-state` records the section value and the buffer line number; the section wins, and a section's start is its heading. The line number is only the fallback for when the section is gone.

The docstring justifies preferring the section so a render that adds a line above does not slide the buffer out from under the reviewer. That reasoning is right; the granularity is wrong. It should put the reviewer back on the same *line*, not merely in the same section.

## Design

Restore point by the strongest identity available, in order:

1. The `revu-target` text property under point — path, line number and Origin. It is already on every source line (revu-render.el commentary, ADR-0011), and it is stable across a re-taken diff, so it survives the case that actually bites: a hunk that grew above the reviewer.
2. The section value, as today, when point was on a heading or on a line carrying no target.
3. The raw buffer line number, as today, when the section is gone too.

Settled with the reviewer: restore the column alongside the line, and restore `window-start` as well as point. A 3 MB buffer that jumps is as disorienting as point moving, so the reviewer should be looking at the same line at the same height after a render as before it. Where the line survives but its height cannot be preserved exactly, put point back on the line and let the window settle around it rather than forcing a scroll.

Note dcr-01m0rkx3k23r (hunk section identity) degrades step 2 as long as it stands: after an edit the saved hunk value no longer matches any section, so restoration falls through to the raw line number.

## Notes

**2026-08-24T01:18:15.141705786Z**

Left hitl: two sub-decisions in the Design section are still open — whether to restore the column as well as the line, and whether window-start should be restored so the view does not jump even when point survives. Flip to afk once those are settled.
