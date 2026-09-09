---
id: dcr-01m0rbfvtpkk
title: 'ADR-0003 amendment: every diff Source records a base blob, and a removed line only loses it when the base is gone'
status: closed
type: task
priority: 3
mode: afk
created: '2026-08-23T22:22:35.862419935Z'
updated: '2026-09-09T21:07:52.282675708Z'
closed: '2026-09-09T21:07:52.282675708Z'
tags:
- needs-triage
acceptance:
- title: ADR-0003 carries an amendment recording that every diff Source records a commit as its base and re-locates removed lines in that base's blob, and that the fresh-while-unchanged, orphaned-otherwise rule applies only when the recorded base cannot be read
  done: true
- title: The removed-line locator's docstring and the test pinning its nil-base branch describe an unreadable base, not a worktree Source
  done: true
links:
- dcr-01m0tkej1jg9
- dcr-01m0zjc6bscw
- dcr-01m0r9smxsrv
external_refs:
- git:38259c1
---

## Description

ADR-0003's Consequences say an uncommitted working-tree Source has no base blob, so its removed-line Anchors are `fresh` while the worktree is unchanged and `orphaned` otherwise. That assumed the worktree Source diffed against the index. It does not: a worktree Source is `git diff <revision>` against HEAD or any other Revision, and, like the staged and range Sources, records the commit it resolved to as `base`. A removed line in any diff Source was removed from that base, so it re-locates in the base blob exactly as ADR-0003's first sentence describes, and reload after a commit or a rebase keeps finding it.

Amend ADR-0003 to record the rule as it stands. Every diff Source records a commit as its base, and a removed-line Anchor re-locates inside that base's blob. A removed line always belongs to a path the base carries, so an all-added file never needs a base blob, and neither does the plain-file Source, which has no removed lines. The one case with no blob to search is a recorded base the repository no longer holds, such as a commit rewritten and pruned or absent from a shallow clone. There the fresh-while-unchanged, orphaned-otherwise rule applies: the line is nowhere to search for, and searching the current file for its text would report a line the reviewer never annotated. The code already behaves this way; the docstring of the removed-line locator and the test that pins its nil-base branch describe it as a worktree Source and should describe the unreadable base instead.

Out of scope: what a patch Annotation does without an Anchor, which dcr-01m0r9smxsrv records in ADR-0003 with the patch Source.

## Notes

**2026-09-09T21:07:52.282675708Z**

ADR-0003 carries an amendment recording that every git diff Source — worktree, staged and range — records the commit it resolved to as base, and that a removed line re-locates inside that base's blob, so a reload after a commit or a rebase keeps finding it. An all-added file and the plain-file Source need no base blob; the patch Source stands apart as its own amendment already records. The fresh-while-unchanged, orphaned-otherwise rule is left where it belongs: a recorded base the repository can no longer read, a commit rewritten and pruned or absent from a shallow clone. revu-anchor-locate-removed's docstring and the test pinning its nil-base branch now describe that unreadable base rather than a worktree Source. No behaviour change; test, lint and compile clean.
