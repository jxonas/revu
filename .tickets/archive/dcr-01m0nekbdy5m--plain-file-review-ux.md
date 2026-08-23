---
id: dcr-01m0nekbdy5m
title: Plain-file review UX
status: closed
type: task
priority: 2
mode: hitl
created: '2026-08-22T19:19:12.573968823Z'
updated: '2026-08-23T19:13:44.651939877Z'
closed: '2026-08-23T19:13:44.651939877Z'
parent: dcr-01m0nekb375q
tags:
- wayfinder:grilling
deps:
- dcr-01m0nekb8ks4
---

## Description

## Question

How does reviewing a plain file differ from reviewing a diff in the chosen review buffer? Decide: does the reviewer annotate the real file buffer (overlays, margin marks, read-only toggled?) or a dedicated review buffer showing the file as all-context; are non-file buffers allowed; how annotations are displayed (inline section vs margin vs sideline); how range selection works from an active region; what revdiff's markdown TOC idea becomes, if anything, in v0.

## Notes

**2026-08-23T19:00:39.630443658Z**

Constraint from Keymap and evil strategy (ADR-0010): all revu interaction happens in the dedicated read-only revu buffer — plain-file review must render-from-state there too, never install a minor mode on the user's editable file buffer. Single-key bindings are therefore always safe; the canonical map and evil overlay from ADR-0010 apply unchanged.

**2026-08-23T19:13:44.651939877Z**

ADR-0011: plain-file review renders one flat file section (all lines, annotations as child sections at their Anchor lines) in the dedicated revu buffer — the diff renderer minus hunk splitting. One file per Review; entry refuses non-file buffers and files outside a project root, prompts to save modified buffers; disk content is the single truth and g reloads sidecar+source in one pass (ADR-0007). Region at entry only positions point; a region straddling annotation sections targets the file lines it touches. Line numbers render as a dim text prefix for plain files and diffs alike. Markdown TOC stays out of v0 (outline sections are its future home).
