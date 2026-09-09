---
id: dcr-01m2414rjm09
title: A docstring closing a quote with \=' renders a straight quote
status: open
type: bug
priority: 3
mode: hitl
created: '2026-09-09T21:28:21.332594245Z'
updated: '2026-09-09T21:28:21.332594245Z'
---

## Description

`substitute-command-keys' turns a backtick into a curly open quote and a plain apostrophe into a curly close one, so `git diff' renders as 'git diff'. Written `git diff\=', the close comes out as a straight quote against a curly open: 'git diff' with mismatched ends, which is what C-h f shows the reader.

The repo has 29 of these across revu.el, revu-record.el, revu-annotate.el, revu-diff.el, revu-reviewed.el and revu-magit.el. The `re' linter is happy with all of them, because \\=' is a legitimate escape and the linter only catches the single-backslash \=' that puts a stray = on screen. This is the same shape of fault docs/agents/standards.md already records: a rendering nobody looked at, copied because it looked like the project's style.

The rule the fix establishes: \\=' is for an apostrophe inside a word -- SOURCE\\='s -- and never for closing a `quote'. The untracked-files change already follows it in the code it added; the rest of the repo does not.
