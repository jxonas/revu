---
id: dcr-01m0r63dzcq8
title: revu v0 build
status: open
type: epic
priority: 1
mode: afk
created: '2026-08-23T20:48:25.580767068Z'
updated: '2026-08-23T20:52:40.901715382Z'
links:
- dcr-01m0nekb375q
---

## Description

## Problem Statement

Reviewing code and documents happens in Emacs, but the feedback produced there has nowhere structured to live. A reviewer reading a diff or a file writes notes into scratch buffers, commit messages, or chat windows; handing that feedback to an AI agent means retyping it with file/line references the agent must trust. Tools that do capture structured review feedback (revdiff) live outside Emacs, keep state in memory, and lose the reviewer's place. There is no way to annotate a diff or file inside Emacs and have an agent outside Emacs read those annotations — with stable identities, kinds, and locations — while the review is still underway.

## Solution

`revu`: an Emacs package that opens a dedicated read-only review buffer over a Source (a git diff — worktree, staged, or ref range — or a single plain file) and lets the reviewer attach Annotations (question / change / note) to lines, ranges, files, or the Review itself. Every mutation is persisted immediately to a Sidecar JSON file under `<project-root>/.revu/` — the Sidecar *is* the review state, and it is the canonical record an agent reads at any moment. Anchors re-locate Annotations against file content when the Source changes; Reviewed marks let the reviewer work through large Sources; a revdiff-markdown Export keeps existing agent plugins working; a reload command brings the agent's Replies and appended Annotations back into the buffer. All vocabulary is fixed in `CONTEXT.md`; all load-bearing choices are fixed in ADR-0001 through ADR-0011.

## User Stories

1. As a reviewer, I want to open a review buffer over my uncommitted worktree diff, so that I can read all my changes in one place before committing.
2. As a reviewer, I want to review the staged diff, so that I can check exactly what the next commit will contain.
3. As a reviewer, I want to review a ref range (`A..B`), so that I can review a branch the way a PR would present it.
4. As a reviewer, I want to review a unified diff I already have in a buffer, so that revu is not limited to the diffs its own commands generate.
5. As a reviewer, I want to open a review buffer over a single saved file, so that I can annotate a document or source file that has no diff.
6. As a reviewer, I want to attach an Annotation to the line at point, so that my feedback lands exactly where I mean it.
7. As a reviewer, I want to attach an Annotation to an active region, so that feedback about a block is recorded as a range, not a guessed line.
8. As a reviewer, I want to annotate a whole hunk in one act, so that hunk-scoped feedback does not require hand-selecting its lines.
9. As a reviewer, I want file-level Annotations, so that I can comment on a file as a whole ("split this module") without inventing a line.
10. As a reviewer, I want review-level Annotations, so that summary feedback ("overall: naming drifts") has a home.
11. As a reviewer, I want each Annotation to carry an explicit Kind — question, change, or note — so that the reader knows whether I expect an answer, an edit, or nothing.
12. As a reviewer, I want to edit an Annotation's body after writing it, so that I can sharpen feedback without delete-and-retype.
13. As a reviewer, I want to delete an Annotation, so that withdrawn feedback disappears from the record, not just the screen.
14. As a reviewer, I want every change persisted immediately to the Sidecar, so that a crash or restart loses nothing and an agent can read the file mid-review.
15. As a reviewer, I want re-invoking revu on the same Source to resume the existing Review, so that a review survives lunch, restarts, and reboots.
16. As a reviewer, I want Annotations to stay attached to their lines after I edit, rebase, or regenerate the diff, so that yesterday's feedback still points at the right code.
17. As a reviewer, I want to see when an Annotation has moved or been orphaned, so that I can trust — or repair — a stale location instead of being lied to.
18. As a reviewer, I want renamed files followed automatically in git Sources, so that a rename does not orphan a file's worth of feedback.
19. As a reviewer, I want to mark a hunk or file reviewed and have it collapse and advance me to the next unreviewed section, so that I can grind through a large diff without losing my place.
20. As a reviewer, I want an edited region to automatically stop counting as reviewed, so that "reviewed" never describes code I have not seen.
21. As a reviewer, I want reverting an edit to resurrect its Reviewed mark, so that I am not punished for experiments I undid.
22. As a reviewer, I want hide-reviewed and annotated-only view filters, so that I can see only what still needs my eyes, or only what I said.
23. As a reviewer, I want to export the Review as revdiff markdown, so that revdiff's existing Claude Code / Codex / OpenCode plugins consume my feedback unchanged.
24. As a reviewer, I want the export and sidecar commands to push the absolute path plus a terse agent contract to the kill ring, so that handing the review to an agent is one yank.
25. As an AI agent outside Emacs, I want the Sidecar to be a stable, documented JSON schema with ULID identities and explicit Targets, so that I can parse feedback without scraping prose.
26. As an AI agent, I want to answer a question by setting a `reply` field on its Annotation, so that my answer travels back inside the same record.
27. As an AI agent, I want to append my own Annotations with fresh ULIDs, so that I can flag things I noticed while acting on the review.
28. As a reviewer, I want a reload command that re-reads Sidecar and Source and re-renders, so that agent Replies and appended Annotations appear inline where the feedback was written.
29. As a reviewer, I want revu to refuse to overwrite a Sidecar the agent changed since my load, so that agent work is never silently clobbered.
30. As a reviewer, I want an explicit force-write escape hatch, so that I can discard agent edits I judge garbage — deliberately, never by accident.
31. As a reviewer, I want a malformed Sidecar refused loudly with my last-good state kept, so that a broken agent edit costs me nothing and hides nothing.
32. As a reviewer, I want `RET` on an Annotation or line to visit the Target at its re-located position in the current file, so that reading feedback and fixing code are one motion.
33. As a reviewer, I want line numbers rendered in the review buffer for diffs and plain files alike, so that I can talk to agents and colleagues in line numbers.
34. As an evil user, I want working normal-state bindings out of the box that follow evil-collection conventions, so that the buffer is native to my fingers with zero config on vanilla evil, Doom, or evil-collection.
35. As a vanilla Emacs user, I want magit-section's folding and navigation plus mnemonic single keys, so that the buffer behaves like the special buffers I already know.
36. As any user, I want a `?` transient dispatch listing every command, so that I can discover the palette without reading the manual.
37. As a reviewer, I want plain-file review to happen in the dedicated buffer, never touching my editable file buffer, so that revu never fights my own modes and keys.
38. As a script author, I want Anchor context and digests baked into the record, so that I can interpret a Sidecar with no Emacs and no configuration.

## Implementation Decisions

All load-bearing decisions are recorded as ADRs; the glossary in `CONTEXT.md` is the vocabulary contract. Implementation tickets cite the ADRs they build. Index:

- **ADR-0001** — the canonical record is ours; revdiff markdown is one Export, mapping Kind `question` to revdiff's `??` convention.
- **ADR-0002** — the Sidecar `<project-root>/.revu/<review>.json` *is* the review state; no flush step; re-anchoring is therefore first-class.
- **ADR-0003** — Annotation = `{id, kind, target, anchor, body, created, updated}`; ULID identity; tagged Target (`review`/`file`/`line`/`range`); diff lines carry `origin`; Anchors store line text + 3 context lines + file digest and re-locate against file content (never the diff) via digest → exact → whitespace-stripped → context-window ladder; anchor state derived on load, never persisted; Reviews record `base`/`head` Revisions so removed lines re-locate in `git show base:path`.
- **ADR-0004** — rename following for git Sources via one `git diff -M --name-status` at load; plain files just orphan; path resolution (`present`/`renamed`/`deleted`) derived per path, never persisted; Target `path` immutable.
- **ADR-0005** — schema v1 shape (`schema`, `name`, `source{kind,base,head,path}`, timestamps, `annotations` in ULID order); deterministic Review names resume the same Source; atomic write per mutation; `.revu/` git-ignoring is docs-only guidance.
- **ADR-0006** — revdiff Export writes `.revu/<review>.md`: collisions concatenate, review-level Annotations dropped with a loud count, resolved current paths and re-located line numbers rendered; exact grammar pinned in `docs/research/revdiff-export-format.md`.
- **ADR-0007** — round-trip is a manual reload command; optional `reply` string per Annotation (presence = answered, rendered inline); tolerant reader for unknown fields, whole-file refusal on invalid input with last-good state kept; mtime/hash write guard; force-write as the only escape hatch; kill-ring handoff carries the agent contract.
- **ADR-0008** — the review buffer is built on the standalone `magit-section` library (never full magit): revu owns a small diff parser and renderer, re-rendering the section tree from state; buffer text faced with `font-lock-face`.
- **ADR-0009** — Reviewed marks are digest-identified, persisted additively in the Sidecar (`reviewed` array); hunk marks only for diffs (file state derived), one file-content mark for plain files; unmatched marks kept; reviewer-private (Export and agent contract ignore them); DWIM toggle + collapse + auto-advance; annotated-only and hide-reviewed are render predicates.
- **ADR-0010** — one canonical `revu-mode-map` atop magit-section natives (`a`/`e`/`k` annotate ops, `r` reviewed toggle, `E` export, `g` reload, `RET` visit, `?` dispatch); first-party guarded `evil-define-key*` normal-state bindings following evil-collection conventions (`x` delete, `gr` reload, `gj`/`gk`/`C-j`/`C-k`, `za` folds); transient dispatch is the full palette and sole home of force-write and the render filters; all interaction in the dedicated read-only buffer.
- **ADR-0011** — plain-file review renders one flat file section with Annotations as child sections; one file per Review; entry refuses non-file and non-project buffers, prompts to save; disk is the single truth; line numbers as a dim text prefix for plain files and diffs alike.

Platform: Emacs 30.2+, GPL-3-or-later, package prefix `revu-`. Dependencies: `magit-section` (NonGNU ELPA) and `transient`; never full magit; no evil dependency. Built-ins preferred elsewhere (`json-serialize`, `string-edit` for bodies).

## Testing Decisions

- Tests assert external behavior at two seams only. **Primary seam — the command layer**: ERT invokes the interactive commands against a temporary fixture git repository and asserts on the two real outputs, the Sidecar JSON on disk and the rendered review buffer (its text and section structure). **Secondary seam — the anchoring engine**: a pure function from file content plus Anchor to position and state, tested directly because its edge cases (moved, whitespace-shifted, duplicated, deleted lines; renames; base-blob lookups) explode combinatorially.
- Export is tested through the command seam at the file boundary, against the grammar fixtures in `docs/research/revdiff-export-format.md` — the Go parser's grammar is the contract.
- No test asserts on internal data structures, overlay counts, or private function calls; re-rendering from state must be free to change shape.
- Every implementation ticket lands with its own ERT coverage; the harness and fixture repo builder are part of the skeleton ticket. High-value targets: anchoring ladder, Sidecar read/write/refuse/guard, export grammar, reviewed-digest matching.
- Prior art: none — the repo is greenfield; the prototypes on `prototype/review-buffer-base` are throwaway reference material, not code to inherit.

## Out of Scope

- Comparing two arbitrary files (`--compare-old/new`) and stdin as a feature.
- Mercurial / Jujutsu support.
- Themes, word-diff, blame gutter, side-by-side views.
- Forge / PR comment submission.
- Agent-driven blocking review loop via `emacsclient`.
- Post-v0 fog (tracked on the wayfinder map, not here): additional native Export formats, multiple concurrent Reviews and history, in-Emacs agent adapters (gptel, agent-shell, claude-code.el), MELPA/CI packaging, markdown TOC pane.

## Further Notes

- This epic's child tickets are the implementation cut; their `deps` edges are the build order and their priorities encode core-first sequencing (annotate-and-export before comfort features).
- The wayfinder map [revu: Emacs diff & file review with exportable annotations](dcr-01m0nekb375q) holds the full decision trail; `docs/adr/` holds the decisions themselves.
- The agent contract text (kill-ring handoff) is fixed in ADR-0007: answer questions by setting `reply`; append new Annotations with fresh ULIDs; never delete or reorder; keep valid JSON; preserve unknown fields.
