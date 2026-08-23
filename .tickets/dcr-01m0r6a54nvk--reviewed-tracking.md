---
id: dcr-01m0r6a54nvk
title: Reviewed-tracking
status: open
type: task
priority: 2
mode: afk
created: '2026-08-23T20:52:05.907983496Z'
updated: '2026-08-23T20:52:05.907983496Z'
parent: dcr-01m0r63dzcq8
acceptance:
- title: Toggle marks/unmarks hunk and file at point, collapses and auto-advances
  done: false
- title: Editing a hunk renders it unreviewed; reverting resurrects the mark
  done: false
- title: File shows reviewed only when every hunk digest matches
  done: false
- title: annotated-only and hide-reviewed filters shape the render and compose
  done: false
deps:
- dcr-01m0r6a51n20
---

## Description

Digest-identified Reviewed marks per ADR-0009: a DWIM toggle on the section at point (hunk marks the hunk; file section marks per hunk; plain files come later with their own single mark), persisted additively in the Sidecar's reviewed array, no schema bump. A region is reviewed exactly when a mark's digest matches its current content — an edit un-reviews, a revert resurrects; unmatched marks are kept. Marking collapses the section and auto-advances to the next unreviewed section. Buffer-local annotated-only and hide-reviewed render predicates. Reviewed state is reviewer-private: Export and the agent contract ignore it.
