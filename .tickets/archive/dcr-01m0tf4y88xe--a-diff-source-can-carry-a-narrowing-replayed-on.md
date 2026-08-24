---
id: dcr-01m0tf4y88xe
title: A diff Source can carry a Narrowing, replayed on reload and part of the Review name
status: closed
type: feature
priority: 2
mode: afk
created: '2026-08-24T18:05:01.064043513Z'
updated: '2026-08-24T18:30:11.908924058Z'
closed: '2026-08-24T18:30:11.908924058Z'
acceptance:
- title: A diff Source records paths only when a Narrowing was given; a Source without one serialises exactly as before
  done: true
- title: revu-reload regenerates a narrowed Source with its pathspecs, so the rendered files are the narrowed set
  done: true
- title: The derived Review name of a narrowed Source appends a slug of its pathspecs and differs from the full Source's name
  done: true
- title: A sidecar carrying paths loads, renders and writes back with paths intact
  done: true
- title: The public entry commands do not gain a paths prompt; only callers passing PATHS explicitly narrow
  done: true
---

## Description

ADR-0005's amendment adds an optional 'paths' list of git pathspecs to a diff Source (worktree, staged, range). It exists so the magit Bridge (ADR-0013) can hand revu a path-limited diff that survives the first 'g': today revu-reload regenerates the diff from the Source's revisions alone with revu's own options, so any narrowing would be spent on the first render and every Annotation re-anchored against the full diff.

Also the naming rule: a narrowed Source derives 'main..feature--src-foo--docs' (revisions' name plus a slug of each pathspec), so the same narrowing resumes the same Review and the full one is left alone.

## Design

revu-source-worktree / -staged / -range take an optional PATHS and record it only when non-nil; revu-source-paths reads it. revu-diff-worktree-text, -staged-text and -range-text append '--' plus the pathspecs when given. revu--source-files passes them through, so reload replays them. revu-review-name-for-source appends the slug. No schema bump (ADR-0005 amendment says why). Anchor capture and re-location are unaffected: they read file content by path, not the diff. Pin with tests: a narrowed range Source regenerates narrowed on reload; a Source without paths is byte-identical to today's; the name slug is deterministic and differs from the full name; a sidecar with paths written by this revu round-trips.

## Notes

**2026-08-24T18:30:11.908924058Z**

A diff Source (worktree, staged, range) takes an optional PATHS and records it as 'paths' only when given, so an un-narrowed Source serialises byte-for-byte as before. The three -text functions append '-- <pathspecs>', revu--source-files reads revu-source-paths and threads them through, so revu-reload replays the Narrowing instead of widening on the first 'g'. revu-review-name-for-source appends a hyphen-joined slug in the order the pathspecs were given (main..feature--src-foo--docs), so a narrowed Review resumes itself and the full one is left alone. Sidecar validation refuses a 'paths' that is not an array of strings; no schema bump. The entry commands gained no prompt -- PATHS is a trailing optional argument for the magit Bridge. Nine tests in test/revu-narrowing-test.el, including a load from a paths-bearing Sidecar revu did not write. Commit 04899b6; full suite 209/209.
