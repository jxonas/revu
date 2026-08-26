---
id: dcr-01m0zjc68crm
title: Opening a Review resumes the Sidecar's Source but paints the caller's diff
status: open
type: bug
priority: 2
mode: afk
created: '2026-08-26T17:37:36.514782911Z'
updated: '2026-08-26T17:37:36.514782911Z'
acceptance:
- title: Opening a Review that resumes an existing Sidecar renders the diff of the Source the Sidecar records, so the first paint and every later reload show the same content
  done: false
- title: A Review opened against a Revision whose typed name now resolves to a different commit than the record holds says so in the resume echo, naming both commits
  done: false
- title: 'A regression test covers the branch-moved case: open the worktree against a branch, advance the branch, reopen against it, and the rendered files match the recorded base'
  done: false
- title: ADR-0005's worktree amendment gains a paragraph recording that on resume the name is the handle and the record is the truth
  done: false
links:
- dcr-01m0tkej1jg9
---

## Description

When an entry command opens a Review whose Sidecar already exists, the Sidecar is resumed — its recorded Source, base commit included, is the truth from then on: `revu-reload` replays it, and a removed line re-locates in its blob. But the first render uses the files the entry command diffed before it knew a Sidecar was there, taken against whatever the reviewer's Revision resolves to *now*.

The two agree only while the Revision has not moved. Take the worktree against `main` (Review `worktree-vs-main`, recording commit C1), let `main` advance to C2, and open the worktree against `main` again: the buffer shows `git diff C2` under a header and a record that say C1, and the next `g` silently swaps it for `git diff C1`. Annotations are placed on the first paint against content the Review does not record. Reachable today through the magit Bridge (`d r main` twice across a commit); an interactive `since` command (see the ticket this one gates) makes it an everyday path.

Fix: when a Sidecar is resumed, render from the Source it records, not from the caller's. The resume echo should also say when the two have parted — "Resumed worktree-vs-main against a1b2c3 (main is now d4e5f6)" — since the header shows the recorded commit but not that the branch has left it. The rule this encodes, decided in the grill: on resume the *name* is the handle and the *record* is the truth, even when the name was written as a branch that has since moved.
