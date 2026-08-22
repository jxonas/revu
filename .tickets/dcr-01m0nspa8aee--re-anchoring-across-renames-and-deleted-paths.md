---
id: dcr-01m0nspa8aee
title: Re-anchoring across renames and deleted paths
status: open
type: task
priority: 2
mode: hitl
created: '2026-08-22T22:33:04.010762415Z'
updated: '2026-08-22T22:33:04.010762415Z'
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
