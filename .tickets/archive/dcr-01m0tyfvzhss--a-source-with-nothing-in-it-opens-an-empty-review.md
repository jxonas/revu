---
id: dcr-01m0tyfvzhss
title: A Source with nothing in it opens an empty Review and says nothing
status: closed
type: bug
priority: 2
mode: hitl
created: '2026-08-24T22:33:07.825480207Z'
updated: '2026-08-24T22:33:19.973455043Z'
closed: '2026-08-24T22:33:19.973455043Z'
---

## Description

`revu-diff-staged` in a repository with nothing staged opens a blank `*revu: staged*` buffer and writes a Sidecar for it. The reviewer cannot tell whether revu failed, whether the Narrowing matched nothing, or whether the Source is genuinely empty -- and the common way to reach here is running the command from a buffer whose project is not the one the work is staged in. `revu-diff-worktree` and `revu-diff-range` have the same hole.

## Notes

**2026-08-24T22:33:19.973455043Z**

revu.el now runs every git entry command's parsed diff through revu--diff-files, which refuses a Source with no files in it with a user-error naming what was diffed and where -- "Nothing is staged in /path/ to review", the worktree's and the range's equivalents -- plus the pathspecs when the Source was narrowed. No Sidecar is written for a Review of nothing. Four tests in revu-review-test.el cover the three commands and the narrowed refusal; revu-narrowing-is-only-what-a-caller-asked-for was given something to review after its commit-everything. The reported symptom (an empty buffer from revu-diff-staged) was git reporting an empty index: the Sidecar the failing run wrote records base = HEAD and the bare name "staged", so no Narrowing was in play; the staged work was in another project.
