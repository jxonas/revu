---
id: dcr-01m0nekb5z5c
title: Canonical annotation record & anchor model
status: closed
type: task
priority: 2
mode: hitl
created: '2026-08-22T19:19:12.319342097Z'
updated: '2026-08-22T22:34:11.732906095Z'
closed: '2026-08-22T22:34:11.732906095Z'
parent: dcr-01m0nekb375q
tags:
- wayfinder:grilling
---

## Description

## Question

What is the canonical JSON record for an Annotation, and what Anchor data lets a Target survive Source changes?

Sub-questions to settle:
- Field set: id, kind, target, anchor, body, created/updated, author? Anything agents need that revdiff lacks (quoted snippet)?
- Line numbering for diff Targets: which side (old/new) is recorded for removed vs added vs context lines — revdiff records old-file numbers for removed lines, new-file numbers otherwise.
- How a diff-line Target and a plain-file-line Target unify into one record shape.
- Re-anchoring: annotate.el stores the anchored text plus a file checksum and re-searches within ±N lines; bookmark.el stores front/rear context strings. Pick a strategy and define what "stale" means and how it is shown.
- Review-level and file-level Targets: how they are represented without a line.

Resolution is an ADR plus the vocabulary update in `CONTEXT.md`.

## Notes

**2026-08-22T22:34:11.650401542Z**

Resolved as ADR-0003 (`docs/adr/0003-annotation-record-and-anchor-model.md`) plus `CONTEXT.md` terms Origin and Revision and a sharpened Anchor entry.

Answers to the sub-questions:
- **Field set**: `{id, kind, target, anchor, body, created, updated}`. `id` is a ULID and is the identity, so two Annotations may share a Target. No `author` in v0 (additive later). The quoted snippet lives inside `anchor`, not as a sibling field.
- **Target**: a tagged object — `review`, `file`, `line`, `range` — not revdiff `Line == 0` sentinels. A hunk annotation is a `range`. The exporter flattens to sentinels on the way out.
- **Line numbering**: one file line number plus `origin` (`added | removed | context`). Origin implies the side by revdiff rule (old file for removals, new file otherwise), so the `(File, Line, Type)` export key derives mechanically.
- **Diff vs plain-file unification**: same shape, `origin` simply absent for plain files. The Source kind is recorded once on the Review, not per Annotation.
- **Re-anchoring**: Anchor stores the line verbatim (no trailing newline), 3 lines of leading and trailing context (fixed, baked into the record), and a digest of the file content. Ranges anchor both endpoints plus a line count; a crossed or inverted result orphans the Target. Re-location searches **file content, never the diff**. Order: digest match, then exact line-text match nearest the recorded number, then whitespace-stripped match, then the context window; ties inside the window orphan rather than guess. Search radius is a defcustom (default 500 lines) and only governs the degraded path.
- **Stale**: three derived states — `fresh`, `moved`, `orphaned` — recomputed on load and never persisted.
- **Removed lines**: the Review records the Revisions its Source came from (`base`, optional `head`); removed-line anchors re-locate inside `git show <base>:<path>`. An uncommitted working-tree Source has no base blob, so those are `fresh` while the worktree is unchanged and `orphaned` otherwise.

Handed on:
- Export collision for two Annotations on one Target, and the rest of the Review envelope (sidecar naming, schema version, ordering) → noted on [Export & sidecar commands](dcr-01m0nekbgpk7).
- Renames and deleted paths graduated out of the fog into [Re-anchoring across renames and deleted paths](dcr-01m0nspa8aee), which now blocks the v0 spec ticket.

**2026-08-22T22:34:11.732906095Z**

ADR-0003: ULID-identified Annotation record with a tagged Target; diff lines carry origin so the revdiff export key derives; Anchors store line text + 3 lines of context + a file digest and re-locate against file content, with fresh/moved/orphaned derived on load.
