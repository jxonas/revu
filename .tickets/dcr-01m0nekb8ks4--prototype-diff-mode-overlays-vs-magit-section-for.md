---
id: dcr-01m0nekb8ks4
title: 'Prototype: diff-mode+overlays vs magit-section for the review buffer'
status: open
type: task
priority: 2
mode: hitl
created: '2026-08-22T19:19:12.403717315Z'
updated: '2026-08-22T19:19:12.403717315Z'
parent: dcr-01m0nekb375q
tags:
- wayfinder:prototype
---

## Description

## Question

Which base should the review buffer use: built-in `diff-mode` with overlays and `outline-minor-mode`, or the standalone `magit-section` library (pr-review's pattern: diff-mode fontify -> `magit-section` wash -> per-line `(path line)` props -> inline comment sections)?

Build a throwaway of each on the same git diff: annotate a line, show the annotation inline, navigate between annotations, fold a file. Compare code size, dependency cost, look and feel, and how naturally each extends to plain-file review.

Resolution is an ADR naming the base; the prototype branch is linked, not merged.
