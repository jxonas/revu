---
id: dcr-01m0rkx3k23r
title: A hunk section's identity is its header text, so folds and point anchoring die across an edit
status: open
type: bug
priority: 2
mode: afk
created: '2026-08-24T00:49:38.400785547Z'
updated: '2026-08-24T01:19:21.637912622Z'
tags:
- render
acceptance:
- title: A collapsed hunk stays collapsed across revu-reload when its file was edited above it
  done: false
- title: Reviewed marks keep their content-digest identity and still un-match on edit (ADR-0009 unchanged)
  done: false
- title: An ADR records why a hunk's fold identity and its Reviewed-mark identity differ
  done: false
- title: A hunk section carries a stable magit-section-ident-value of (path . index)
  done: false
links:
- dcr-01m0rkwmzs2m
- dcr-01m0rkxmpxza
---

## Description

A hunk section is rendered with the value `(path . hunk-header)` (revu-render.el:324), e.g. `("f.txt" . "@@ -1,8 +1,8 @@")`. The header text is derived from content, so it changes whenever the file changes.

magit-section keys its visibility cache on `magit-section-ident`, which is built from the section value. So after an edit the hunk is a different section as far as the cache is concerned: the fold the reviewer set is not found, and the hunk renders expanded. `revu-render--point-state` saves the same value, so point restoration also falls through to the raw buffer line number.

Reproduced in batch against magit-section 4.7.0. Collapse the hunks of two files, edit one of them, `revu-reload`: the edited file's hunk comes back expanded, the untouched file's hunk stays collapsed.

NOT the same bug as dcr (fold loss with no edit at all). This one requires an edit between renders. Do not close that ticket on the strength of this fix.

## Design

A hunk carries two identities, and they want opposite properties:

- Content-keyed, for a Reviewed mark. ADR-0009 identifies marks by content digest precisely so that an edit un-matches the assertion — "I have read this" must stop being true when "this" changes.
- Position-keyed, for view state. A fold should survive the very edit that reload exists to show the reviewer.

Today the section value serves both and gets the second one wrong.

Settled with the reviewer: keep the section value as it is and give `revu-hunk-section` a stable `magit-section-ident-value` method — the seam magit-section provides for exactly this. The ident is the hunk's position in its file, `(path . index)`, which holds as long as hunks are not added or removed above it. This leaves the section value alone, so nothing else in revu that looks a hunk up by value has to change, and it keeps the two identities honestly distinct: content-keyed for "have I read this", position-keyed for "is this folded".

Rejected: making the value itself `(path . index)`, which touches every caller that looks a hunk up by value, revu-reviewed included; and keying on the hunk's old-start line, which still moves when the change moves.

This decision needs an ADR. It is hard to reverse, it is surprising without the reasoning, and it commits to the opposite rule from ADR-0009 for what looks like the same object — a future reader will trip on it. The ADR should say plainly that a hunk has two identities, name what each is for, and cross-reference ADR-0009 so the pair is readable together.

## Notes

**2026-08-24T01:00:32.377820528Z**

Severity drops once dcr-01m0rkxmpxza lands, but this stands on its own. That ticket is about visibility never being applied to the buffer at all; this one is about the hunk's identity being unstable, so that even with the overlays applied correctly, a hunk whose file was edited above it comes back as a different section and loses its fold. Independent causes, independent fixes.

**2026-08-24T01:18:15.235620224Z**

Left hitl: the identity scheme is recommended but not chosen. The Design section lists three options (a stable magit-section-ident-value, changing the section value itself, keying on old-start) and the trade-off against ADR-0009 needs a human decision plus an ADR before an agent should implement it.
