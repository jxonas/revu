---
id: dcr-01m0nekb5z5c
title: Canonical annotation record & anchor model
status: open
type: task
priority: 2
mode: hitl
created: '2026-08-22T19:19:12.319342097Z'
updated: '2026-08-22T19:19:12.319342097Z'
parent: dcr-01m0nekb375q
tags:
- wayfinder:grilling
---

## Description

## Question

What is the canonical JSON record for an Annotation, and what Anchor data lets a Target survive Source changes?

Sub-questions to settle:
- Field set: id, kind, target, anchor, body, created/updated, author? Anything agents need that revdiff lacks (quoted snippet)?
- Line numbering for diff Targets: which side (old/new) is recorded for removed vs added vs context lines — revdiff records old-file numbers for removed lines, new-file numbers otherwise.
- How a diff-line Target and a plain-file-line Target unify into one record shape.
- Re-anchoring: annotate.el stores the anchored text plus a file checksum and re-searches within ±N lines; bookmark.el stores front/rear context strings. Pick a strategy and define what "stale" means and how it is shown.
- Review-level and file-level Targets: how they are represented without a line.

Resolution is an ADR plus the vocabulary update in `CONTEXT.md`.
