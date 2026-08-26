---
id: dcr-01m0rbfvtpkk
title: 'ADR-0003 amendment: a worktree Review does have a base blob'
status: open
type: task
priority: 3
mode: hitl
created: '2026-08-23T22:22:35.862419935Z'
updated: '2026-08-26T17:37:36.630153928Z'
tags:
- needs-triage
acceptance:
- title: ADR-0003 records which Sources have a base blob and which do not, and why
  done: false
links:
- dcr-01m0tkej1jg9
- dcr-01m0zjc6bscw
---

## Description

ADR-0003's Consequences say: "An uncommitted working-tree Source has no base blob, so its removed-line Anchors are `fresh` while the worktree is unchanged and `orphaned` otherwise."

That sentence assumed `revu-diff-worktree` diffs the worktree against the index, whose content is not a commit and so has no blob to read. The v0 build took the other branch: `revu-diff-worktree` runs `git diff HEAD`, so the Review covers everything uncommitted — staged and unstaged alike, which is what epic user story 1 asks for ("read all my changes in one place before committing") — and records HEAD as its base Revision. A removed line in that diff was removed from HEAD, so it re-locates in `git show HEAD:<path>` exactly as a staged or ranged Source's does.

The consequence sentence is therefore stale for worktree Sources. The nil-base-content branch of `revu-anchor-locate-removed` still earns its place — a pasted-diff Review records blob ids rather than commits and has no base blob to read — so the behaviour it describes should move to that case rather than being deleted.
