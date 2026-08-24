---
id: dcr-01m0t3r7pwkk
title: The current section's highlight overlays the whole body, so what is under point loses its faces
status: open
type: bug
priority: 2
mode: afk
created: '2026-08-24T14:45:50.428061943Z'
updated: '2026-08-24T14:45:50.428061943Z'
acceptance:
- title: The three section classes inherit a shared revu-section parent, with no change to rendered output
  done: false
- title: With point in a hunk, the face at a body line still reads as that line's Origin face, not the highlight
  done: false
- title: The same holds for a file section, including a plain-file Source, whose lines have no hunk section of their own
  done: false
- title: 'The same holds for an Annotation: its body and its Reply stay distinguishable while point rests on it'
  done: false
- title: The heading of the current section is still highlighted, so the affordance survives
  done: false
- title: Tests assert on the face visible at a position, not on magit's overlay list, so they state the guarantee in terms of the buffer
  done: false
- title: ADR-0008 amended to record specialising magit-section-highlight, over the paint protocol and over the off-switch
  done: false
---

## Description

Moving point onto a hunk, a file or an Annotation should leave what is under it readable. Today it does the opposite: magit-section paints its current-section highlight across the entire section body, so the added/removed colouring of the lines being read is flattened into one background, and on an Annotation the Reply's face -- which is the answered signal (ADR-0007) -- stops being distinguishable from the body it answers.

After this ticket the highlight covers a section's heading only, and body text keeps the face the render gave it.

Note that plain-file review has no hunk section: its lines sit flat under the file section (ADR-0011). Covering the file section is therefore what fixes plain-file review, not an extra.

## Design

The three section classes gain a shared parent, 'revu-section', and 'magit-section-highlight' is specialised on it once rather than three times. The method highlights the heading range and stops.

This is extension through a public cl-defmethod, the same way revu already specialises 'magit-section-ident-value' (ADR-0012), not a reach into magit internals -- the boundary ADR-0008 drew.

The heading range is highlighted with no face argument, so it inherits whatever the reviewer has themed 'magit-section-highlight' to. revu has no opinion about what 'you are here' should look like, and adding a tenth face to assert one would say nothing its other nine do not.

Considered and rejected:

- The paint protocol -- bind the 'painted' slot and implement 'magit-section-paint'. This is how magit's own diff buffers keep their colours, and the only other escape magit offers: every branch of 'magit-section-highlight' overlays the body unless 'painted' is bound. It costs a repaint method, a pair of highlight-variant faces, and a repaint on every move of point between sections. It can be migrated to later without changing anything outside the renderer, so it is not foreclosed.
- Setting 'magit-section-highlight-current' to nil. Zero code, but it buys readability back by discarding the current-section affordance altogether, and it reaches into the reviewer's own magit-section configuration to do it.
