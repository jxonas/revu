---
id: dcr-01m0nspa8aee
title: Re-anchoring across renames and deleted paths
status: closed
type: task
priority: 2
mode: hitl
created: '2026-08-22T22:33:04.010762415Z'
updated: '2026-08-23T01:35:00.851959126Z'
closed: '2026-08-23T01:35:00.851959126Z'
parent: dcr-01m0nekb375q
tags:
- wayfinder:grilling
---

## Description

## Question

ADR-0003 anchors against file content at a `path`. When the file at `path` no longer exists — renamed, moved, or deleted — what does re-anchoring do?

Sub-questions to settle:
- Follow git rename detection (`git diff -M --name-status`, `git log --follow`) to a new path, or orphan?
- If a rename is followed, is the Target `path` rewritten in the sidecar, or is the old path kept with the new one recorded beside it?
- A genuinely deleted file: `orphaned`, or a distinct state?
- Plain-file Sources have no git rename detection available. Same answer, or different?

Resolution is an amendment to ADR-0003 (or a follow-up ADR).

## Notes

**2026-08-23T01:35:00.851959126Z**

ADR-0004: git Sources follow renames via one 'git diff -M --name-status base..worktree' call at load (default 50% similarity); plain-file Sources never follow — missing file orphans. New derived concept 'path resolution' (present/renamed/deleted), per path, never persisted. Anchor states stay line-scoped: pure rename with intact line is fresh; deletion adds no fourth state (annotations orphan, resolution says why). Target path is immutable — removed-line re-location needs the base-side path — so post-rename annotations record the new path and Export resolves the grouping. Glossary term added to CONTEXT.md.
