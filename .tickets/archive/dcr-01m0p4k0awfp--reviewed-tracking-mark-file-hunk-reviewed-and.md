---
id: dcr-01m0p4k0awfp
title: 'Reviewed-tracking: mark file/hunk reviewed and hide reviewed sections'
status: closed
type: task
priority: 2
mode: hitl
created: '2026-08-23T01:43:29.884735181Z'
updated: '2026-08-23T18:34:00.627742718Z'
closed: '2026-08-23T18:34:00.627742718Z'
parent: dcr-01m0nekb375q
tags:
- wayfinder:grilling
deps:
- dcr-01m0nekb8ks4
---

## Description

## Question

How does the reviewer mark progress through a large Source, and how does the buffer hide what is done?

Sub-questions to settle:
- Granularity: file-level only (revdiff Space), or hunk-level too?
- Hiding: collapse reviewed sections, or filter views (annotated-only, unreviewed-only — revdiff f/F)? Both?
- Persistence: does reviewed state go in the sidecar, or live only in the Emacs session? If persisted, does it rot like anchor state (ADR-0003 derived-state rule)?
- Does an edit to a reviewed region (anchor no longer fresh) clear its reviewed mark?

Blocked on the review-buffer prototype: magit-section collapses sections natively; diff-mode+overlays would build hiding by hand.

## Notes

**2026-08-23T18:33:43.936223230Z**

Resolution (ADR-0009): reviewed marks are persisted user assertions in the sidecar — additive 'reviewed' array of {path, digest, created}, no schema bump. Digest over region content IS the identity: a hunk renders reviewed iff a mark matches its current content, so an edit un-reviews it with no stale flag. Diff Sources persist hunk marks only (file state derived: file reviewed = all hunks matched; marking a file marks every hunk); plain files persist one file-content mark. Unmatched marks are kept, never pruned (revert resurrects). Reviewer-private: Export drops it, agent contract silent. UI: DWIM toggle on section at point, collapse via magit-section HIDE + auto-advance to next unreviewed; annotated-only and hide-reviewed as buffer-local render predicates; reviewed and annotated orthogonal. Keys deferred to the new package-wide 'Keymap and evil strategy' ticket.

**2026-08-23T18:34:00.627742718Z**

ADR-0009: digest-identified reviewed marks persisted in the sidecar (hunk marks for diffs, file state derived; plain files one file mark); edits un-review by digest mismatch; unmatched marks kept; reviewer-private; collapse+auto-advance UI with annotated-only/hide-reviewed toggles; keys deferred to keymap ticket.
