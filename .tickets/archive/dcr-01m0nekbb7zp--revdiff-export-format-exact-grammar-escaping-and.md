---
id: dcr-01m0nekbb7zp
title: 'revdiff export format: exact grammar, escaping and plugin expectations'
status: closed
type: task
priority: 2
mode: afk
created: '2026-08-22T19:19:12.487226794Z'
updated: '2026-08-22T19:26:45.026860515Z'
closed: '2026-08-22T19:26:45.026860515Z'
parent: dcr-01m0nekb375q
tags:
- wayfinder:research
---

## Description

## Question

Pin, from revdiff's source (`app/annotation/store.go`, `app/annotation/parse.go`) and its Claude Code / Codex / OpenCode plugin skills, everything our Export must reproduce to be byte-compatible: header regex and the four record shapes, sort order, record separation, the `## ` body-line escaping rule, the `hunk` keyword range rule, path relativity, the `??` / leading-word question convention the plugins apply, and what the plugins do with the file after reading it. Note any behaviour where the plugins are stricter than the format.

Capture the findings as `docs/research/revdiff-export-format.md` on a `research/revdiff-export-format` branch.

## Notes

**2026-08-22T19:26:44.934934369Z**

Resolution — findings in `docs/research/revdiff-export-format.md` on branch `research/revdiff-export-format` (commit 7379107, read against revdiff master 0526193, 2026-08-20).

What an Emacs exporter must reproduce:
- Record key `(path, line, type)`; type is `+`, `-`, or a literal space; file-level = line 0, type "".
- Line numbers are file lines, not diff offsets: `-` rows use the old-file number, `+` and context rows the new-file number.
- Headers: `## path (file-level)`, `## path:N (T)`, `## path:N-M (T)`. Parser regex `^## (.+?)(?::(\d+)(?:-(\d+))?)? \((file-level|\+|-| )\)$`.
- Layout: header, newline, body, newline; records joined by exactly one blank line; no leading/trailing blank lines; empty review emits zero bytes and `-o` is not written.
- Sort: paths bytewise, then line ascending (file-level first); `+`/`-` on the same line have unspecified tie order.
- Escaping: body lines whose first non-space content is `## ` get one extra leading space; parser strips exactly one. Nothing else is escaped.
- Trim trailing newlines from bodies; parser accepts CRLF and tolerates unescaped `## ` lines after the first header.
- `hunk` keyword (`(?i)\bhunk\b`) expands EndLine forward only within the same change type, `+`/`-` rows only, only when M > N. Import accepts `N-M` on any type but validates on `(line, type)` alone.
- Paths are repo-root-relative; outside a repo, keyed by the path as typed / resolved absolute.
- `--annotations` import drops orphans with stderr warnings, requires line *and* type to match the live diff, caps at 1 MiB, errors on parse failure.
- Plugins: Claude/Codex launcher reads `--output=$TMPDIR/revdiff-output-XXXXXX`, cats it, deletes it; the `??` / `explain|remind|describe|what is|what are|how does|how do|clarify` question rule is applied by Claude/Codex/pi, not OpenCode, and not by the format. Plugin docs mention only `(+)`, `(-)`, `(file-level)`; the Go parser is the real contract.

Implication for revu: Kind `question` → prefix/suffix `??` on export; review-level notes have no revdiff equivalent and must be dropped or folded into a file-level record on export (decide in the Export & sidecar commands ticket).

**2026-08-22T19:26:45.026860515Z**

revdiff export grammar pinned: (path,line,type) key, file-line numbering (old for -, new otherwise), header regex, one-blank-line separation, '## ' body escaping, hunk-range rule, import orphan handling, plugin question convention. Note: docs/research/revdiff-export-format.md on branch research/revdiff-export-format.
