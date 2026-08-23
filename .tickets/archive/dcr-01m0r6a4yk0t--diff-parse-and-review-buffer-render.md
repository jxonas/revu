---
id: dcr-01m0r6a4yk0t
title: Diff parse and review buffer render
status: closed
type: task
priority: 1
mode: afk
created: '2026-08-23T20:52:05.713887980Z'
updated: '2026-08-23T22:23:01.180165002Z'
closed: '2026-08-23T22:23:01.180165002Z'
parent: dcr-01m0r63dzcq8
acceptance:
- title: Entry commands open the review buffer over the fixture repo's worktree, staged and range diffs
  done: true
- title: TAB folding works on file and hunk sections
  done: true
- title: Line-number prefix follows the Origin numbering rule
  done: true
- title: Re-rendering from unchanged state is idempotent
  done: true
deps:
- dcr-01m0r6a4rf7e
---

## Description

revu-mode derives from magit-section-mode in a dedicated read-only buffer, rendered from state (ADR-0008): our own unified-diff parser feeds a section tree of files and hunks; entry commands cover worktree, staged and ref-range git diffs plus an existing unified-diff buffer; text is faced with font-lock-face; every line carries the dim line-number prefix (removals numbered in the old file, the rest in the new — ADR-0011, Origin rule). Re-render from state is the only way the buffer changes.

## Notes

**2026-08-23T22:23:01.180165002Z**

revu-diff.el owns a unified-diff parser and the git calls that feed it, pinned to a fixed diff configuration so a reviewer's gitconfig cannot change what the parser reads. revu-render.el builds the magit-section tree from state -- files over hunks over lines, faced with font-lock-face, every source line carrying a revu-target text property and a dim line-number prefix that numbers removals in the old file and everything else in the new. Four entry commands: worktree (git diff HEAD, so staged and unstaged changes alike are what the reviewer sees before committing), staged, ref range, and a unified diff already in a buffer -- the last reading its Revisions from the diff's own index headers and refusing, per the build's binding decision, a diff naming objects this repository lacks rather than inventing a fifth Source kind. Re-rendering unchanged state is byte-identical and keeps point. Filed dcr-01m0r9smxsrv for the ADR amendment a first-class pasted-diff Source needs.
