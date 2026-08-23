---
id: dcr-01m0nekbgpk7
title: Export & sidecar commands
status: closed
type: task
priority: 2
mode: hitl
created: '2026-08-22T19:19:12.662397425Z'
updated: '2026-08-23T02:43:27.057064280Z'
closed: '2026-08-23T02:43:27.057064280Z'
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

**2026-08-23T01:35:00.757618623Z**

Handoff from Re-anchoring across renames and deleted paths (ADR-0004): Target paths are immutable (path at annotation time), so a sidecar may show stale or duplicate paths after a rename. Path resolution facts (present/renamed/deleted) are derived and available at export time — rendering resolved current paths, and grouping one file that appears under two paths, is the exporter's job.

**2026-08-23T02:43:26.965747208Z**

Resolved (grilling, ADR-0005 + ADR-0006):
- Naming: deterministic from Source (worktree / staged / main..feature with '/'→'-' / file-<slug>); same Source resumes the existing sidecar; prompt offers the default. Concurrent reviews per source stay out of v0.
- Write policy: atomic write (temp+rename) on every mutation; no debounce, no explicit save (mechanics of ADR-0002).
- Schema v1: {schema, name, source{kind, base, head, path}, created, updated, annotations[]}; flat integer schema, readers refuse higher; annotations in ULID order; ISO-8601 UTC.
- Export: revu-export writes .revu/<review>.md beside the sidecar, overwritten each time; prefix arg prompts for destination. Export command and revu-sidecar-path push the absolute path to the kill ring and echo it — that's the agent handoff.
- Collisions on (File,Line,Type): concatenate bodies with a blank line, '??' marks question bodies.
- Review-level Annotations: dropped from revdiff Export with a warning count (parser rejects preambles; pseudo-paths lie).
- Export renders the resolved present: current paths (merging renamed old+new groups), re-found numbers for moved anchors, orphaned included at recorded numbers.
- .gitignore: documentation-only guidance to ignore .revu/; revu never edits it.
- Posture confirmed: revdiff compat is table stakes (ADR-0001); future native export formats are additive exporters over the same record.

**2026-08-23T02:43:27.057064280Z**

Sidecar naming/write-policy/schema fixed as ADR-0005; revdiff Export destination, handoff, collision, review-level-drop and resolved-present rules fixed as ADR-0006.
