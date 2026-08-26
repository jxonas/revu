---
id: dcr-01m0zjc6bscw
title: A worktree Source includes untracked files
status: open
type: feature
priority: 3
mode: hitl
created: '2026-08-26T17:37:36.630153928Z'
updated: '2026-08-26T17:37:36.630153928Z'
tags:
- needs-triage
acceptance:
- title: A file created in the worktree and not yet staged or committed appears in every worktree Source as an all-added file, whether the Source is against HEAD or against another Revision
  done: false
- title: An ignored file does not appear
  done: false
- title: Reviewed marks, Path resolution and Anchors on an untracked file behave as the grill decides, and the ADRs that own them record the decision
  done: false
links:
- dcr-01m0rbfvtpkk
---

## Description

A worktree Source is `git diff <base>`, and `git diff` never shows an untracked file. A file the agent creates and never `git add`s is therefore invisible to the Review until it is staged or committed — and "everything the worktree carries that the base does not" reads as a promise that a new file counts. An agent forgetting `git add` is the common case, not the odd one.

Decided so far (grill, 2026-08-26): every worktree Source — against HEAD or against any other Revision — should show untracked files as all-added diffs, `.gitignore` respected. This is not a new Source kind and not a Narrowing; it widens what the worktree Source means.

Open questions to grill before this is picked up:

- What digest a Reviewed mark takes over a path git has no blob for, and whether the Reviewed-mark model (ADR-0009) needs a word for it.
- What Path resolution says about a path that is neither in the base nor in the index, and how it reads once the file is staged, committed, or deleted again.
- How the diff text is produced: intent-to-add emulation, `git diff --no-index` per file, or a synthesised file diff, given that the Reviewed-mark digests and Path resolution key on the diff being cut exactly as revu pins it (ADR-0005's Narrowing amendment).
- Whether an untracked file that is ignored is ever wanted (proposed: no).
- Anchor state for lines in a file with no base blob is already handled for a pasted diff (see the linked ADR-0003 ticket); confirm the same branch covers this.
