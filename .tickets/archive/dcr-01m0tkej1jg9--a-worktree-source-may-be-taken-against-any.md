---
id: dcr-01m0tkej1jg9
title: A worktree Source may be taken against any Revision, not only HEAD
status: closed
type: feature
priority: 2
mode: afk
created: '2026-08-24T19:20:10.541118667Z'
updated: '2026-08-26T17:37:51.689166627Z'
closed: '2026-08-24T23:02:09.230142017Z'
acceptance:
- title: revu-diff-worktree takes an optional base Revision, defaulting to HEAD; it opens the diff of the worktree against that Revision and the Source records the commit it resolves to
  done: true
- title: The derived Review name stays worktree for a HEAD base and carries the Revision as the reviewer named it otherwise, so the HEAD Review does not fork on every commit and a non-HEAD one never resumes it
  done: true
- title: A Narrowing still slugs its pathspecs onto either name, and the two separators do not collide
  done: true
- title: The magit Bridge opens a lone revision from d r, and a prefix-argument d w, as that Source instead of refusing
  done: true
- title: A revision naming nothing still refuses, and so does a non-HEAD base for the index
  done: true
- title: Reload replays the recorded base, and a line the diff removed re-locates in that base's blob
  done: true
- title: ADR-0005's naming rule and ADR-0013's refusal paragraph record the decision
  done: true
links:
- dcr-01m0rbfvtpkk
- dcr-01m0tf5gqcc1
- dcr-01m0zjc68crm
- dcr-01m0zjcn2gbj
---

## Description

A reviewer who asks magit for `d r' and names a lone revision -- a tag, a branch -- is asking for everything that changed since it, committed and uncommitted alike: magit shows `git diff <rev>' for that input. revu refuses, because its worktree Source is defined as the worktree against HEAD.

The Source model already carries what is needed. `revu-source-worktree' takes a base Revision, `revu-diff-worktree-text' runs `git diff <revision>', and reload, base-blob reads for removed lines and rename resolution all key off `revu-source-base'. Two things are missing: an entry point that passes a base other than HEAD, and a Review name that tells the two apart.

The name is what makes this more than a one-liner. The name derived for a worktree Source is the bare string `worktree', ignoring the base, and deliberately so: the Review of the worktree stays one Review as HEAD moves rather than forking on every commit. Widen the base without touching the name and a Review against a tag resumes the Sidecar of the Review against HEAD, reading the wrong Source under the wrong Annotations -- a worse failure than today's refusal.

## Design

`revu-diff-worktree' gains an optional base Revision, defaulting to HEAD. The precedent for the name is `revu-diff-range', which derives the name from the Revisions as they were typed and records the commits they resolve to: `worktree' for a HEAD base, `worktree-vs-qa-2026-08-17' for anything else. The separator is `-vs-' rather than `--', which ADR-0005 has already spent on the Narrowing.

In the Bridge, a lone revision from `d r' and a prefix-argument `d w' map onto that Source instead of refusing. A revision naming nothing still refuses, and so does a non-HEAD base for the index: there is no index-against-a-commit Source, and adding one is a domain change that does not ride in here.

ADR-0005 owns the naming rule and ADR-0013 the Bridge's refusals, so both are amended. ADR-0003's stale sentence about a worktree Source having no base blob belongs to dcr-01m0rbfvtpkk and is left alone.

## Notes

**2026-08-24T23:02:09.230142017Z**

revu-diff-worktree takes an optional base Revision (arglist is now (base name paths), matching revu-diff-range). The diff is git diff <base>; the Source records the commit it resolved to, so reload replays it and a removed line re-locates in that base's blob. The derived name is worktree for a base naming the commit HEAD names -- compared as commits, so the checked-out branch opens the one Review -- and worktree-vs-<revision> otherwise, with the Narrowing still slugging on behind -- and no Revision can spell it. The magit Bridge opens a lone revision from d r and the revision d w reads from a prefix argument as that Source; a revision naming nothing refuses, and so does a non-HEAD base for the index. A worktree Review is recognised as its scratch bucket by the name it derives against HEAD (revu-review-scratch-name-p), since its record now holds a commit its name never matched. ADR-0005 and ADR-0013 amended. 278 tests pass; commit d3608b7. Not done: a base is not reachable interactively -- the prefix argument is already spent on the name -- so revu's own d w still opens against HEAD.
