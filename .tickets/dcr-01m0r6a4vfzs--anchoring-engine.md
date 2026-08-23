---
id: dcr-01m0r6a4vfzs
title: Anchoring engine
status: open
type: task
priority: 1
mode: afk
created: '2026-08-23T20:52:05.614362581Z'
updated: '2026-08-23T20:52:05.614362581Z'
parent: dcr-01m0r63dzcq8
acceptance:
- title: Every ladder rung and the tie-orphans rule covered by direct tests
  done: false
- title: 'Rebase/edit fixture: annotations re-found as moved; deleted lines orphan'
  done: false
- title: Removed-line Targets re-locate in the base blob via recorded Revisions
  done: false
- title: Renamed file resolves with annotations intact; plain-file rename orphans
  done: false
- title: No anchor state or path resolution ever appears in the Sidecar
  done: false
deps:
- dcr-01m0r6a4rf7e
---

## Description

Anchors re-locate against file content, never the diff: creation captures line text, three lines of context each side, and the file digest; re-location runs the ADR-0003 ladder (digest match trusts the number, then exact line text nearest the recorded number, then whitespace-stripped, then context window; in-window ties orphan rather than guess); range endpoints anchor independently; anchor state fresh/moved/orphaned is derived on load and never persisted. Removed lines re-locate inside git show <base>:<path> using the Review's recorded Revisions. Renames follow via one git diff -M --name-status call per load for git Sources; plain files just orphan; path resolution present/renamed/deleted derived per path (ADR-0004); Target path stays immutable. This is the spec's secondary pure seam — tested directly.
