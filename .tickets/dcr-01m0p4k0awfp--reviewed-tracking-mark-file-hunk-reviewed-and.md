---
id: dcr-01m0p4k0awfp
title: 'Reviewed-tracking: mark file/hunk reviewed and hide reviewed sections'
status: open
type: task
priority: 2
mode: hitl
created: '2026-08-23T01:43:29.884735181Z'
updated: '2026-08-23T01:43:37.323530150Z'
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
