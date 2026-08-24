---
id: dcr-01m0rkwmzs2m
title: Re-render puts point on the hunk heading, not the line the reviewer was on
status: open
type: bug
priority: 2
mode: afk
created: '2026-08-24T00:49:23.448882726Z'
updated: '2026-08-24T12:54:02.855727545Z'
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
- title: The line is restored to the height it was at, so the view does not jump when point survives
  done: false
links:
- dcr-01m0rkx3k23r
- dcr-01m0rkxmpxza
---

## What to build

A re-render leaves the reviewer looking at the same line, at the same
place on screen, that they were on before it.

Every change to a Review is a full re-render (ADR-0008), so this is on
the path of annotate, edit, delete, a Reviewed-mark toggle, a filter
toggle, force-write and reload. Today the render puts point at the start
of the enclosing section, and a section starts at its heading, so the
reviewer loses their line on every one of those.

Reported against revu v0 QA (Doom Emacs, Emacs 30.2.50, Magit b6c5125,
Transient 0.13.5, Git 2.54.0). Reproduces on both `revu-diff-range` and
annotation insertion/deletion.

Restore point by the strongest identity the buffer offers, in order:

1. The `revu-target` under point -- path, line number and Origin. It is
   already on every source line, and it names the line rather than where
   the line happened to sit, so it survives the case that actually bites:
   a re-taken diff whose hunk grew above the reviewer.
2. The section, when point was on a heading or on a line carrying no
   target. Find it again by its magit-section ident, not by its value: a
   hunk's value is its header text and so changes with the content, while
   its ident is being made stable by dcr-01m0rkx3k23r.
3. The raw buffer line number, when the section is gone too.

Restore the column alongside the line, and put the line back at the
height it was at, so a large buffer does not jump under a reviewer who
kept their line. Where the height cannot be honoured -- the line is now
too near the top of the buffer to sit that low -- put point on the line
and let the window settle around it rather than forcing a scroll.

## Blocked by

None - can start immediately.