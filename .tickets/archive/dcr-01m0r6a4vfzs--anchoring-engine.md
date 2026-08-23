---
id: dcr-01m0r6a4vfzs
title: Anchoring engine
status: closed
type: task
priority: 1
mode: afk
created: '2026-08-23T20:52:05.614362581Z'
updated: '2026-08-23T22:23:01.271457082Z'
closed: '2026-08-23T22:23:01.271457082Z'
parent: dcr-01m0r63dzcq8
acceptance:
- title: Every ladder rung and the tie-orphans rule covered by direct tests
  done: true
- title: 'Rebase/edit fixture: annotations re-found as moved; deleted lines orphan'
  done: true
- title: Removed-line Targets re-locate in the base blob via recorded Revisions
  done: true
- title: Renamed file resolves with annotations intact; plain-file rename orphans
  done: true
- title: No anchor state or path resolution ever appears in the Sidecar
  done: true
deps:
- dcr-01m0r6a4rf7e
---

## Description

Anchors re-locate against file content, never the diff: creation captures line text, three lines of context each side, and the file digest; re-location runs the ADR-0003 ladder (digest match trusts the number, then exact line text nearest the recorded number, then whitespace-stripped, then context window; in-window ties orphan rather than guess); range endpoints anchor independently; anchor state fresh/moved/orphaned is derived on load and never persisted. Removed lines re-locate inside git show <base>:<path> using the Review's recorded Revisions. Renames follow via one git diff -M --name-status call per load for git Sources; plain files just orphan; path resolution present/renamed/deleted derived per path (ADR-0004); Target path stays immutable. This is the spec's secondary pure seam — tested directly.

## Notes

**2026-08-23T22:23:01.271457082Z**

revu-anchor.el is the pure seam: a function of file content and an Anchor to a line number and a derived state, with git access kept outside it. The ADR-0003 ladder runs digest, then exact line text nearest the recorded number, then whitespace-stripped, then the context window; a rung that ties names no line and the ladder goes on, so only a tie inside the window orphans. Range endpoints locate independently and an inverted or lost endpoint orphans the range. Anchor capture records the line verbatim, three lines of context each side and the file digest; removed lines re-locate in the base blob via the Review's recorded Revisions. Path resolution runs one git diff -M --name-status against the worktree per load for git Sources, so a rename made after a range's head is still followed; plain-file Sources never follow renames. No anchor state and no path resolution is ever persisted, and a test holds the Sidecar to it. Filed dcr-01m0rbfvtpkk to amend ADR-0003's now-stale base-blob consequence.
