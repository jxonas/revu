---
id: dcr-01m0nekb375q
title: 'revu: Emacs diff & file review with exportable annotations'
status: open
type: epic
priority: 1
mode: hitl
created: '2026-08-22T19:19:12.231180857Z'
updated: '2026-08-22T19:26:45.117760404Z'
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

**2026-08-22T19:26:45.117760404Z**

Decision: [revdiff export format: exact grammar, escaping and plugin expectations](dcr-01m0nekbb7zp) — grammar pinned to the Go parser (not the plugin docs); file-line numbering with old side for `-`; review-level notes have no revdiff equivalent, so the Export ticket must decide drop-vs-fold. Note at `docs/research/revdiff-export-format.md` on `research/revdiff-export-format`.

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

Ticket decisions are appended as notes below.

## Not yet specified

- Round-trip import: an agent edits or answers annotations in the sidecar and Emacs shows the result.
- Multiple concurrent reviews and review history (revdiff's `~/.config/revdiff/history`).
- In-Emacs agent adapters: a gptel tool, agent-shell send, claude-code.el send.
- MELPA packaging, CI, byte-compile/lint setup.
- "Reviewed" file-tracking and annotated-only filters (revdiff `Space`, `f`, `F`).
- Renamed files and moved hunks when re-anchoring across Source changes.
- Markdown TOC pane for document review.

## Out of scope

- Compare two arbitrary files (`--compare-old/new`); stdin as a feature (falls out of the diff-mode substrate anyway).
- Mercurial / Jujutsu support.
- Themes, word-diff, blame gutter, side-by-side — Emacs already has these or they are cosmetic.
- Forge / PR comment submission.
- Agent-driven blocking review loop via `emacsclient` and a Claude Code plugin — ruled out by the Q6 decision.
