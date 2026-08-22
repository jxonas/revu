# Emacs building blocks for revu

Surveyed 2026-08-22 during map charting. Stars and last-push dates from GitHub; MELPA presence from `archive.json`.

## Headline

No Emacs package annotates lines/ranges/hunks of both a diff and a plain file, persists locally, and exports
structured data. Each candidate below covers at most two of those four axes. The closest whole-product match is
revdiff itself (Go TUI), which is the design reference, not a base.

## Built-ins (Emacs 30.2 baseline)

- `diff-mode` — parses unified/context diffs; `diff-hunk-next/prev`, `diff-file-next/prev`, `diff-hunk-text`,
  `diff-find-source-location` (hunk line → file and line), `diff-refine-hunk` (word-level overlays). Refine
  overlays can override text-property fontification (pr-review issue #13): keep annotation overlays at a higher
  priority.
- `vc-diff` / `vc-root-diff` — diff-mode buffers for any VC backend without magit.
- Overlays and text properties — the primitive every annotation package uses; lost on buffer kill, so
  persistence is layered on top.
- `string-edit` / `read-string-from-buffer` (29.1+) — multi-line comment composer, `C-c C-c` accept, `C-c C-k` abort.
- `bookmark.el` — front/rear context strings for re-anchoring; `bookmark-make-record-function` pattern.
- `outline-minor-mode` — folding by regexp; lighter alternative to magit-section.
- `tabulated-list-mode` — for an "all annotations" list buffer.
- `json-serialize` / `json-parse-string` — native JSON.
- `ediff` — side-by-side, hard to extend, no comment model. Reference only.

## Plain-file annotation packages

| Package | Status | Attach | Persist | Export | Notes |
|---|---|---|---|---|---|
| annotate.el (bastibe) | MELPA, 432★, 2026-05, Emacs 27.1 | region/word overlays, threaded replies | sexp DB or `.notes` sidecar; record `(START END TEXT ANCHORED-TEXT COLOR POLICY ID REPLY-TO)` + file MD5 | unified diff of original vs annotated; "integrate" as code comments | Most mature anchoring model: re-search anchored text within ±2 lines. Single large file, not a library. |
| simply-annotate | MELPA, 38★, 2026-07, Emacs 28.1 + transient | range overlays; thread objects with status/priority/tags/comments | sexp DB keyed by file or buffer name, project DBs | Org (threads → TODO) | Richest thread metadata; no re-anchoring, stale face instead. |
| org-remark (nobiot) | GNU ELPA, 536★, 2026-05, Emacs 28 | range and line highlights, custom "pens" | `marginalia.org` with beg/end/id/original-text props | notes are Org | Best adapter architecture (`org-remark-eww-mode` etc. pattern). Heavy Org dependency. |
| org-noter | MELPA, 2026-07 | page-level for PDF/EPUB | Org | — | Document-centric; reference only. |

## Forge-backed review packages (comments on diff lines, persisted only server-side)

- pr-review (blahgeek) — MELPA, 110★, 2026-05. Renders the PR diff by fontifying with `diff-mode`, washing with
  `magit-wash-sequence` / `magit-diff-wash-diff` into magit sections; every line carries
  `pr-review-diff-line-left/right` text properties `(path line)`; pending threads are a section class inserted
  inline. **Best reference implementation** of the magit-section approach.
- code-review (wandersoncferreira) — MELPA snapshot 2022, last push 2024; fork ag91/code-review active 2026-05.
  magit-section + transient; local "not sent yet" comment objects. No local mode, no export.
- github-review (charignon) — unmaintained (2021). Comments as `#` lines typed into the diff text.
- diffscuss (tomheon, 2021, MIT) — the only inline-in-diff comment **file format**: `%*` header / `%-` body lines
  after the line they annotate, hunk-level after `@@`, changeset-level at top. Worth reading for anchoring rules.
- inline-review (phye) — not on MELPA, 2026-07. Overlays the diff onto real file buffers and comments there;
  state in `.git/inline-review-*`; no export. Reference for the "annotate in the real file" option.
- forge — cannot author draft inline review comments (magit/forge#75 open since 2019, PR #266 unmerged).
  Possible export target later, not a base.

## Diff viewers and section UIs

- `magit-section` — standalone MELPA/NonGNU package (v4.7, 2026-07, GPL-3+), designed for non-Git use; collapsible
  hierarchy, `magit-insert-section` with value/start/end/content, section-local keymaps, visibility cache.
  `magit-diff-wash-diff` (full magit) turns raw diff text into file/hunk sections.
- difftastic.el — structural side-by-side; no stable line anchoring. Reference.
- diffview — unified → two side-by-side buffers; 2023. Reference.
- diff-hl (1110★, 2026-08) / git-gutter — fringe/margin change marks in file buffers; reference for marking
  annotated lines.
- sideline (191★, 2026-07) — backend API for text at the window edge for lines near point.

## Agent integrations (consumers of the export)

- gptel (3495★, 2026-08) — `gptel-add` context, `gptel-make-tool` for agent-callable elisp tools.
- agent-shell + acp.el (xenodium, 2026-08) — `agent-shell-send-region/file`; natural sink for an export.
- agent-review (nineluj, 2025-11) — inverse direction: agent findings `FILE:LINE|SEVERITY|DESC` into a
  tabulated list. Reference for importing agent output.
- claude-code-ide.el (MCP, ediff accept/reject), claude-code.el (terminal wrapper, send region), aidermacs —
  sinks only.

## Assessment

Plausible bases: (1) built-in `diff-mode` + overlays + `string-edit` + `json-serialize`, zero deps; (2)
`magit-section` for the review buffer following pr-review's pattern; (3) annotate.el's anchoring schema and
algorithm, reused as an idea rather than a dependency; (4) org-remark's adapter architecture as a shape.

The new pieces revu must supply: a unified anchor model covering "hunk line N, old/new side" and "file line N";
the exporter; and adapters for `diff-mode` buffers on one side and file buffers on the other.
