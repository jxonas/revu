---
id: dcr-01m0nekb375q
title: 'revu: Emacs diff & file review with exportable annotations'
status: open
type: epic
priority: 1
mode: hitl
created: '2026-08-22T19:19:12.231180857Z'
updated: '2026-08-23T02:46:07.820807790Z'
tags:
- wayfinder:map
---

## Description

## Destination

A spec ready to build from: `CONTEXT.md` glossary, ADRs for the load-bearing choices (review-buffer base library, annotation record & anchor model, export format, persistence), and a v0 implementation ticket list. The way is clear when nothing remains to decide before someone builds `revu` v0.

## Notes

- Domain: Emacs Lisp package (`revu`, prefix `revu-`), Emacs 30.2+, GPL-3-or-later.
- Reference product: https://github.com/umputun/revdiff — research notes in `docs/research/` once the research ticket lands.
- Skills every session should consult: `grilling`, `domain-modeling` (keep `CONTEXT.md` vocabulary: Review, Annotation, Kind, Target, Anchor, Source, Export).
- Standing preferences: leverage built-ins first (`diff-mode`, overlays, `string-edit`, `json-serialize`); a dependency on `magit-section` is acceptable if the prototype justifies it; never depend on full magit internals. Wayfinder is planning-only here: produce decisions, not code (prototypes are throwaway).

**2026-08-23T01:35:11.535289709Z**

Decisions so far += [Re-anchoring across renames and deleted paths](dcr-01m0nspa8aee) — ADR-0004: git Sources follow renames (one 'git diff -M --name-status base..worktree' call at load); plain files just orphan; new derived per-path 'path resolution' (present/renamed/deleted), never persisted; anchor states stay line-scoped; Target path immutable, so Export resolves stale/duplicate paths (handoff noted on Export & sidecar commands).

**2026-08-23T01:43:37.618392626Z**

Fog graduated: 'Reviewed file-tracking and annotated-only filters (revdiff Space, f, F)' left Not-yet-specified and is now the ticket [Reviewed-tracking: mark file/hunk reviewed and hide reviewed sections](dcr-01m0p4k0awfp), blocked on the review-buffer prototype; v0 spec breakdown now also depends on it.

**2026-08-23T02:43:43.260169705Z**

Decisions so far += [Export & sidecar commands](dcr-01m0nekbgpk7) — ADR-0005: schema v1 sidecar, deterministic resume-by-default naming, atomic write per mutation, .gitignore guidance docs-only; ADR-0006: revdiff Export writes .revu/<review>.md, kill-ring path is the agent handoff, collisions concatenate, review-level notes dropped loudly, export renders resolved current paths and moved lines. Posture: revdiff compat is table stakes; future native export formats are additive exporters.

Fog graduated: 'Round-trip import' left Not-yet-specified and is now the ticket [Round-trip import: agent edits to the sidecar shown in Emacs](dcr-01m0p812gcw2); v0 spec breakdown now also depends on it. Fog added: 'Additional native Export formats beyond revdiff markdown'.

## Decisions so far

Charting-session decisions (no ticket, decided in the charting grill):
- Destination is a spec, not a build.
- v0 scope: git diffs (working tree / staged / ref range) and plain files; line, range, hunk-as-range, file-level and review-level Targets; explicit Kind (question | change | note); structured Export.
- Primary consumer is an agent *outside* Emacs reading a file on disk; in-Emacs adapters (gptel, agent-shell) come later.
- Canonical record is ours, revdiff markdown is an exporter — ADR-0001.
- Sidecar `<project-root>/.revu/<review>.json` is the persisted state and the export artifact — ADR-0002.
- Any `diff-mode` buffer is the diff substrate; convenience commands wrap `git diff` for worktree / staged / `A..B`.
- Agent handshake is user-driven: the reviewer tells the agent which sidecar to read. No `emacsclient` blocking loop.
- Emacs 30.2+; GPL-3-or-later.

- [revdiff export format: exact grammar, escaping and plugin expectations](dcr-01m0nekbb7zp) — grammar pinned to the Go parser, not the plugin docs; file-line numbering with the old side for `-`; review-level notes have no revdiff equivalent, so Export must decide drop-vs-fold. Note at `docs/research/revdiff-export-format.md` on branch `research/revdiff-export-format`.
- [Canonical annotation record & anchor model](dcr-01m0nekb5z5c) — ADR-0003: ULID identity so two Annotations may share a Target; tagged `target` (review/file/line/range, hunk is a range); diff lines carry `origin` so revdiff's export key derives; Anchors store line text + 3 lines of context + a file digest and re-locate against **file content, never the diff**; state (`fresh`/`moved`/`orphaned`) is derived on load, never persisted; Reviews record their `base`/`head` Revisions so removed lines re-locate in `git show base:path`.

## Not yet specified

- Additional native Export formats beyond revdiff markdown (e.g. a markdown flavor keeping Kind, ranges, review-level notes) — additive exporters over the same record.
- Multiple concurrent reviews and review history (revdiff's `~/.config/revdiff/history`).
- In-Emacs agent adapters: a gptel tool, agent-shell send, claude-code.el send.
- MELPA packaging, CI, byte-compile/lint setup.
- Markdown TOC pane for document review.

## Out of scope

- Compare two arbitrary files (`--compare-old/new`); stdin as a feature (falls out of the diff-mode substrate anyway).
- Mercurial / Jujutsu support.
- Themes, word-diff, blame gutter, side-by-side — Emacs already has these or they are cosmetic.
- Forge / PR comment submission.
- Agent-driven blocking review loop via `emacsclient` and a Claude Code plugin — ruled out by the Q6 decision.