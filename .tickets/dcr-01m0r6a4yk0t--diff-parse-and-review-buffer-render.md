---
id: dcr-01m0r6a4yk0t
title: Diff parse and review buffer render
status: open
type: task
priority: 1
mode: afk
created: '2026-08-23T20:52:05.713887980Z'
updated: '2026-08-23T20:52:05.713887980Z'
parent: dcr-01m0r63dzcq8
acceptance:
- title: Entry commands open the review buffer over the fixture repo's worktree, staged and range diffs
  done: false
- title: TAB folding works on file and hunk sections
  done: false
- title: Line-number prefix follows the Origin numbering rule
  done: false
- title: Re-rendering from unchanged state is idempotent
  done: false
deps:
- dcr-01m0r6a4rf7e
---

## Description

revu-mode derives from magit-section-mode in a dedicated read-only buffer, rendered from state (ADR-0008): our own unified-diff parser feeds a section tree of files and hunks; entry commands cover worktree, staged and ref-range git diffs plus an existing unified-diff buffer; text is faced with font-lock-face; every line carries the dim line-number prefix (removals numbered in the old file, the rest in the new — ADR-0011, Origin rule). Re-render from state is the only way the buffer changes.
