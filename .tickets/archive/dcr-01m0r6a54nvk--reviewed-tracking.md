---
id: dcr-01m0r6a54nvk
title: Reviewed-tracking
status: closed
type: task
priority: 2
mode: afk
created: '2026-08-23T20:52:05.907983496Z'
updated: '2026-08-23T23:36:17.750312772Z'
closed: '2026-08-23T23:36:17.750312772Z'
parent: dcr-01m0r63dzcq8
acceptance:
- title: Toggle marks/unmarks hunk and file at point, collapses and auto-advances
  done: true
- title: Editing a hunk renders it unreviewed; reverting resurrects the mark
  done: true
- title: File shows reviewed only when every hunk digest matches
  done: true
- title: annotated-only and hide-reviewed filters shape the render and compose
  done: true
deps:
- dcr-01m0r6a51n20
---

## Description

Digest-identified Reviewed marks per ADR-0009: a DWIM toggle on the section at point (hunk marks the hunk; file section marks per hunk; plain files come later with their own single mark), persisted additively in the Sidecar's reviewed array, no schema bump. A region is reviewed exactly when a mark's digest matches its current content — an edit un-reviews, a revert resurrects; unmatched marks are kept. Marking collapses the section and auto-advances to the next unreviewed section. Buffer-local annotated-only and hide-reviewed render predicates. Reviewed state is reviewer-private: Export and the agent contract ignore it.

## Notes

**2026-08-23T23:36:17.750312772Z**

revu-reviewed.el marks what the reviewer has read, identified by a digest of the hunk's body lines and nothing else, so an edit un-reviews a hunk with no staleness flag to keep in step and reverting the edit brings the mark back. Unmatched marks are kept rather than pruned, which is what makes resurrection possible. A diff persists hunk marks only: marking a file takes one mark per hunk and the file reads reviewed while every hunk of it matches, so no mark can go on claiming a file was read after a hunk under it changed. Marking collapses what it marks and moves point on to the next unread hunk -- including when hide-reviewed has taken the marked hunk out of the buffer, which review caught. The two filters are buffer-local render predicates that compose, and reviewed and annotated stay orthogonal. Marks are reviewer-private: the Export never reads them.
