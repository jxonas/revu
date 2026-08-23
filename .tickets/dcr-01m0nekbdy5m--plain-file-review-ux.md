---
id: dcr-01m0nekbdy5m
title: Plain-file review UX
status: open
type: task
priority: 2
mode: hitl
created: '2026-08-22T19:19:12.573968823Z'
updated: '2026-08-23T19:00:39.630443658Z'
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
