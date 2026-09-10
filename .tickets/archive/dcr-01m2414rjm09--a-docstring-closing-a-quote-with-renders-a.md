---
id: dcr-01m2414rjm09
title: A docstring closing a quote with \=' renders a straight quote
status: closed
type: bug
priority: 3
mode: hitl
created: '2026-09-09T21:28:21.332594245Z'
updated: '2026-09-10T14:16:35.114305512Z'
closed: '2026-09-10T14:16:35.114305512Z'
---

## Description

`substitute-command-keys' turns a backtick into a curly open quote and a plain apostrophe into a curly close one, so `git diff' renders as 'git diff'. Written `git diff\=', the close comes out as a straight quote against a curly open: 'git diff' with mismatched ends, which is what C-h f shows the reader.

The repo has 29 of these across revu.el, revu-record.el, revu-annotate.el, revu-diff.el, revu-reviewed.el and revu-magit.el. The `re' linter is happy with all of them, because \\=' is a legitimate escape and the linter only catches the single-backslash \=' that puts a stray = on screen. This is the same shape of fault docs/agents/standards.md already records: a rendering nobody looked at, copied because it looked like the project's style.

The rule the fix establishes: \\=' is for an apostrophe inside a word -- SOURCE\\='s -- and never for closing a `quote'. The untracked-files change already follows it in the code it added; the rest of the repo does not.

## Notes

**2026-09-10T14:16:35.114305512Z**

39 \\=' quote-closings replaced with a plain apostrophe across 9 files. The ticket counted 29 and its file list missed revu-render.el and the test suite. One plural possessive kept (revu-record.el:234). Two possessives of a quoted symbol reworded (revu.el:452, revu-record.el:449), since no spelling of one renders. standards.md now has the rule and a grep that also catches the end-of-line case. Compile, lint and all 337 tests are clean. Commit 01c076d.
