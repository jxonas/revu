---
id: dcr-01m0rkx3k23r
title: A hunk section's identity is its header text, so folds and point anchoring die across an edit
status: closed
type: bug
priority: 2
mode: afk
created: '2026-08-24T00:49:38.400785547Z'
updated: '2026-08-24T13:08:47.102746151Z'
closed: '2026-08-24T13:08:47.102746151Z'
tags:
- render
acceptance:
- title: A collapsed hunk stays collapsed across revu-reload when its file was edited above it
  done: true
- title: Reviewed marks keep their content-digest identity and still un-match on edit (ADR-0009 unchanged)
  done: true
- title: An ADR records why a hunk's fold identity and its Reviewed-mark identity differ
  done: true
- title: A hunk section carries a stable magit-section-ident-value of (path . index)
  done: true
- title: The index counts the file's parsed hunks, so a view filter does not reshuffle idents
  done: true
links:
- dcr-01m0rkwmzs2m
- dcr-01m0rkxmpxza
---

## What to build

A hunk section carries a stable `magit-section-ident-value` of
`(PATH . INDEX)` -- the hunk's ordinal position among the hunks its file
was parsed with -- so a fold the reviewer set survives the very edit that
reload exists to show them.

A hunk is rendered with the value `(PATH . HEADER)`. The header text is
derived from content, so it changes whenever the file does. magit-section
keys its visibility cache on the ident it builds from that value, so
after an edit the hunk is a different section as far as the cache is
concerned: the fold is not found and the hunk comes back expanded.
Collapse the hunks of two files, edit one of them, `revu-reload`: the
edited file's hunk is open, the untouched file's is still closed.
Reproduced in batch against magit-section 4.7.0.

A hunk carries two identities, and they want opposite properties.
Content-keyed, for a Reviewed mark: ADR-0009 identifies marks by content
digest precisely so an edit un-matches the assertion -- "I have read
this" must stop being true when "this" changes. Position-keyed, for view
state: a fold should outlive the edit. Today the value serves both and
gets the second one wrong.

Leave the value alone and give `revu-hunk-section` an ident-value method
-- the seam magit-section provides for exactly this. Nothing that looks a
hunk up by value has to change, revu-reviewed included, and the two
identities stay honestly distinct.

The index counts the hunks the file was parsed with, not the hunks this
render kept. The view filters drop hunks before they are rendered, so an
index over what was rendered would reshuffle every ident below a dropped
hunk and hand its fold to a different hunk on the next filter toggle.

Write an ADR for this. It is hard to reverse, it is surprising without
the reasoning, and it commits to the opposite rule from ADR-0009 for what
looks like the same object. It should say plainly that a hunk has two
identities, name what each is for, and cross-reference ADR-0009 so the
pair reads together.

Rejected: making the value itself `(PATH . INDEX)`, which touches every
caller that looks a hunk up by value; and keying on the hunk's old-start
line, which still moves when the change moves.

## Blocked by

None - can start immediately.

## Notes

**2026-08-24T13:08:47.102746151Z**

A hunk section now carries an index of its position among the hunks its file was parsed with, and implements magit-section-ident-value as (PATH . INDEX). The value stays (PATH . HEADER), so nothing that looks a hunk up by value changed and Reviewed marks keep their content-digest identity (ADR-0009). ADR-0012 records the two identities and why they pull opposite ways. Tests: a hunk folded by the reviewer survives an edit above it across revu-reload (red before the fix), and a view filter dropping a hunk leaves the fold of the hunk below it alone.
