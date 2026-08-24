---
id: dcr-01m0t3rkpff2
title: A fold the reviewer set dies on every render when magit-section's visibility options are off
status: closed
type: bug
priority: 2
mode: afk
created: '2026-08-24T14:46:02.703703925Z'
updated: '2026-08-24T16:15:11.761926523Z'
closed: '2026-08-24T16:15:11.761926523Z'
acceptance:
- title: A fold set by hand survives a reload with magit-section-cache-visibility globally nil
  done: true
- title: It also survives when that option is a list of section types that does not include revu's
  done: true
- title: It also survives with magit-section-preserve-visibility globally nil
  done: true
- title: Opening a review leaves both global values unchanged outside the review buffer
  done: true
- title: ADR-0012 amended to name the two variables the fold invariant depends on, and why revu defends them
  done: true
links:
- dcr-01m0t7v8hq0p
---

## Description

A fold the reviewer sets by hand outlives the render that built the section (ADR-0012). That guarantee currently rests on two magit-section variables revu never sets and the reviewer can turn off:

- 'magit-section-cache-visibility' gates whether a fold is ever written to the cache. It is a defcustom, so a magit user may well have set it -- and it accepts a list of section types as well as a boolean, so a value naming magit's own types excludes revu's without the reviewer ever intending to.
- 'magit-section-preserve-visibility' gates whether the cache is read back at all. The cache can be perfectly populated and still never consulted.

With either off, every hand-set fold dies on every render. There is no error and nothing on screen to diagnose: the buffer simply comes back expanded, which is the exact failure ADR-0012 exists to prevent. revu has no fold memory of its own -- it only deletes from magit's cache; the writes are magit's.

## Design

'revu-mode' binds both variables buffer-locally, so a review buffer keeps the invariant whatever the reviewer configured for magit, and their global values are untouched.

This is a deliberate exception to revu's posture of inheriting the reviewer's magit-section configuration rather than overriding it. It is narrow and it is defensible on one ground: these two control a mechanism revu builds on, not an appearance the reviewer is entitled to choose. Defending only one of the two would be the worst outcome -- the posture cost paid without the protection bought, since write and read are halves of one guarantee.

## Notes

**2026-08-24T16:15:11.761926523Z**

revu-mode binds magit-section-cache-visibility and magit-section-preserve-visibility buffer-locally to t, so the fold invariant of ADR-0012 holds whatever the reviewer configured for magit, and their global values are untouched. Four tests in test/revu-render-test.el cover the cases: the cache option nil, the cache option a list of section types that excludes revu's, the preserve option nil (asserted through a filter toggle round-trip, because a same-tree reload reads a fold back off the old section tree and would pass without the fix), and the globals unchanged outside the review buffer. ADR-0012 gained a 'What the fold invariant rests on' section naming both variables, why the exception is narrow, and how it sits against ADR-0008's rejected magit-section-highlight-current option. Commit e76844c.
