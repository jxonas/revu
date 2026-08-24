---
id: dcr-01m0tp3y1th9
title: Line numbers in the Review buffer are off by default, behind a defcustom
status: closed
type: feature
priority: 3
mode: afk
created: '2026-08-24T20:06:48.122594877Z'
updated: '2026-08-24T20:50:49.542882562Z'
closed: '2026-08-24T20:50:49.542882562Z'
acceptance:
- title: A boolean defcustom revu-line-numbers exists, default nil
  done: true
- title: With it nil, no line-number prefix is inserted for diff or plain-file lines
  done: true
- title: With it non-nil, the prefix renders as today
  done: true
- title: Annotating, visiting, Export and Reviewed marks work identically either way
  done: true
- title: 'ADR-0011 carries a short amendment: the record holds the numbers, showing them is optional and off by default'
  done: true
- title: The render Commentary matches the amendment
  done: true
links:
- dcr-01m0tp3xvnyq
- dcr-01m0tp3xyh6a
- dcr-01m0t3rxangn
---

## Description

The reviewer does not want to see line numbers on hunks by default. They are revu's own inserted text prefix, not `display-line-numbers`, so nothing in magit-section governs them, and there is no knob today: the width is a private constant and the only defcustom in the package is the anchor search radius.

## Design

Add a boolean `defcustom revu-line-numbers`, default nil. When nil the prefix is not inserted at all. The line's Target (path, number, Origin) is carried by a text property on the line, not by the prefix, so Annotations, Export and Reviewed marks are unaffected. No toggle key for now; a per-buffer toggle is a separate ticket if it is ever wanted.

ADR-0011 records the prefix as a decision ("because reviewers talk to agents in line numbers"), so it gets a one-paragraph amendment in place rather than silent contradiction: the numbers live in the Sidecar; showing them in the buffer is optional and off by default. No new ADR.

This does not conflict with dcr-01m0t3rxangn's "no new defcustom": that ticket is about magit-section configuration, and line numbers are revu's own rendering.

Decided in a grilling session on 2026-08-24, together with the evil j/k bindings and the `r` advance rule.

## Notes

**2026-08-24T20:50:49.542882562Z**

revu-line-numbers, a boolean defcustom defaulting to nil, governs the line-number prefix in the Review buffer; with it off nothing is inserted and revu-render--number-width does not even scan for a width. The Target on the line carries the number, so Annotating, visiting, Export and Reviewed marks read the same line either way -- covered by tests that drive Export, RET and r with the prefix on and off. ADR-0011 carries an amendment saying which half of its prefix bullet is fixed (the numbers are in the record; drawing them is a view), and revu-render.el's Commentary matches it.
