---
id: dcr-01m0zjc6bscw
title: A worktree Source includes untracked files
status: closed
type: feature
priority: 3
mode: afk
created: '2026-08-26T17:37:36.630153928Z'
updated: '2026-09-09T21:28:07.286467718Z'
closed: '2026-09-09T21:28:07.286467718Z'
tags:
- needs-triage
acceptance:
- title: An ignored file does not appear
  done: true
- title: A file created in the worktree and neither staged nor committed appears as an all-added file in every worktree Source, against HEAD or another Revision, narrowed or not, and again on reload and on resuming the Review
  done: true
- title: A worktree that differs from its base only by an untracked file opens a Review rather than being refused as empty
  done: true
- title: A Reviewed mark taken over an untracked file still holds after the file is staged, and its Annotations re-anchor as any added file's do
  done: true
- title: ADR-0005 records that untracked files belong to every worktree Source, that ignored files do not, and why Reviewed marks, Path resolution and Anchors need no new rule for them
  done: true
links:
- dcr-01m0rbfvtpkk
external_refs:
- git:c8d679a
---

## Description

A worktree Source is `git diff <base>`, and `git diff` never shows an untracked file. A file the agent creates and never stages is invisible to the Review until it is staged or committed, while "everything the worktree carries that the base does not" promises that a new file counts. Forgetting `git add` is the common case.

Every worktree Source, against HEAD or against any other Revision, includes each untracked file as an all-added file, with `.gitignore` respected so an ignored file never appears. This is not a new Source kind and not a Narrowing: it widens what the worktree Source means, so a Narrowing limits untracked files the same way it limits tracked ones, and reload, resume, `revu-diff-since` and the magit Bridge all see them because they read the worktree Source through the one place it is cut. A worktree that differs from its base only by an untracked file opens a Review instead of being refused as empty. An untracked binary or empty file appears as a file with no hunks, as a tracked one does.

The untracked file's diff is cut with the same options as the rest of the Source, so its hunk carries the same content lines it will carry once the file is staged and a Reviewed mark taken over it holds across the `git add`. Nothing else needs a new rule. A Reviewed mark digests hunk content only, never a blob. Path resolution reports an untracked file present while it exists on disk and deleted once it is gone; git cannot follow a rename of a file it never tracked, and that reads deleted like any rename git misses. Anchors on an all-added file never need a base blob, so the ADR-0003 rule for removed lines does not apply.

ADR-0005's worktree amendment gets a further amendment recording that untracked files belong to every worktree Source, that ignored files do not, and why Reviewed marks, Path resolution and Anchors need no new word for them.

## Notes

**2026-09-09T21:28:07.286467718Z**

Every worktree Source now appends each untracked file as an all-added file, cut with git diff --no-index against the null device with the same options as the rest of the Source. The widening is at revu-diff-worktree-text, the one place the worktree Source is cut, so reload, resume, revu-diff-since and the magit Bridge all see it and a Narrowing limits untracked files as it limits tracked ones. ADR-0005 carries the amendment; 15 tests in test/revu-untracked-test.el.

Two decisions the ticket did not dictate, both recorded in the ADR. First, /.revu/ is excluded alongside the ignored files: the Review must not list the Sidecar it is being written into, and git-ignoring .revu/ is only recommended, so it cannot be left to .gitignore. Second, a path the tracked diff already names is left to the diff -- a file deleted from the index and written again on disk is both, and rendering it twice would leave its Reviewed marks and folds unable to say which of the two they meant; the reviewer sees git's own answer, the deletion. A nested repository is skipped rather than descended into.

One caveat found in review and written into the ADR: a clean filter (core.autocrlf, a .gitattributes filter=) rewrites the bytes on the way into the index, so a mark taken before the git add reads stale after it -- honestly, since the content read is not the content staged.
