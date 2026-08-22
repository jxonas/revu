---
id: dcr-01m0nekbgpk7
title: Export & sidecar commands
status: open
type: task
priority: 2
mode: hitl
created: '2026-08-22T19:19:12.662397425Z'
updated: '2026-08-22T22:33:12.237916879Z'
parent: dcr-01m0nekb375q
tags:
- wayfinder:grilling
deps:
- dcr-01m0nekb5z5c
- dcr-01m0nekbb7zp
---

## Description

## Question

Define the user-facing surface around the sidecar: default Review naming from the Source (`worktree`, `staged`, `main..feature`, file path); when the sidecar is written (every edit vs explicit save); the revdiff-markdown Export command and where it writes; what the reviewer hands the agent (a path? a single command that prints it?); `.gitignore` guidance.

## Notes

**2026-08-22T22:33:12.237916879Z**

From [Canonical annotation record & anchor model](dcr-01m0nekb5z5c) / ADR-0003, two things land on this ticket:
- Two Annotations may share a Target (identity is the ULID, not the Target). Both flatten to the same revdiff `## path:N (T)` header — decide how the exporter resolves that collision (concatenate bodies, emit both and accept revdiff last-write-wins on import, or refuse).
- ADR-0003 fixes only the Review fields anchoring needs (Source kind, `base`, `head` Revisions). Sidecar naming, schema version and record ordering are still this ticket's to settle.
