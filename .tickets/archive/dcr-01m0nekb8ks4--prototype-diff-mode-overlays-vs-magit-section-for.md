---
id: dcr-01m0nekb8ks4
title: 'Prototype: diff-mode+overlays vs magit-section for the review buffer'
status: closed
type: task
priority: 2
mode: hitl
created: '2026-08-22T19:19:12.403717315Z'
updated: '2026-08-23T18:10:28.953910720Z'
closed: '2026-08-23T18:10:28.953910720Z'
parent: dcr-01m0nekb375q
tags:
- wayfinder:prototype
---

## Description

## Question

Which base should the review buffer use: built-in `diff-mode` with overlays and `outline-minor-mode`, or the standalone `magit-section` library (pr-review's pattern: diff-mode fontify -> `magit-section` wash -> per-line `(path line)` props -> inline comment sections)?

Build a throwaway of each on the same git diff: annotate a line, show the annotation inline, navigate between annotations, fold a file. Compare code size, dependency cost, look and feel, and how naturally each extends to plain-file review.

Resolution is an ADR naming the base; the prototype branch is linked, not merged.

## Notes

**2026-08-23T01:43:37.518270711Z**

New evaluation criterion from Reviewed-tracking ticket (dcr-01m0p4k0awfp): how well does each candidate collapse/hide a reviewed hunk or file? magit-section has native section collapsing; diff-mode+overlays would need hand-built invisible-text overlays. Weigh this in the verdict.

**2026-08-23T17:50:45.642281892Z**

Prototypes built and smoke-tested on branch prototype/review-buffer-base (commit 59ebbee): prototype/revu-proto-diffmode.el (148 lines, zero deps) and prototype/revu-proto-section.el (216 lines, magit-section 4.7.0 from NonGNU ELPA, auto-installed to prototype/.elpa-proto). Same fixture.diff, same keymap (a/n/p/k/TAB/r/R). Run: emacs -Q -l prototype/revu-proto-<name>.el. See prototype/README.md for what to compare. Awaiting human play + verdict; resolution ADR pending.

**2026-08-23T18:10:28.863451377Z**

Resolution: magit-section wins — ADR-0008 (docs/adr/0008-review-buffer-built-on-magit-section.md, commit 03d7f8f). Human played both prototypes on branch prototype/review-buffer-base (not merged): reviewed collapsing is magit-insert-section's HIDE argument vs fragile hand-built invisible overlays; annotations are addressable sections; native uniform folding; render-from-state extends to plain-file review. Costs accepted: NonGNU ELPA dep (magit-section 4.7.0, never full magit), owning a ~90-line diff parser/renderer, font-lock-face (not face) for inserted text.

**2026-08-23T18:10:28.953910720Z**

magit-section is the review-buffer base — ADR-0008. Prototypes on branch prototype/review-buffer-base; decided by native section collapsing (reviewed-tracking), addressable annotation sections, uniform folding, render-from-state extending to plain files. diff-mode+overlays rejected: smaller but structureless; every feature hand-rolled overlays.
