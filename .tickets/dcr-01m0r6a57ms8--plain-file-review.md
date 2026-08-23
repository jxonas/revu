---
id: dcr-01m0r6a57ms8
title: Plain-file review
status: open
type: task
priority: 2
mode: afk
created: '2026-08-23T20:52:06.003114491Z'
updated: '2026-08-23T20:52:06.003114491Z'
parent: dcr-01m0r63dzcq8
acceptance:
- title: Entry refuses non-file buffers and out-of-project files; prompts to save modified buffers
  done: false
- title: Buffer renders disk content flat with annotations as child sections and line numbers
  done: false
- title: Annotate, restart, resume works identically to diff review
  done: false
- title: Single file-content Reviewed mark toggles and un-matches on edit
  done: false
deps:
- dcr-01m0r6a54nvk
---

## Description

Reviewing a single file per ADR-0011: entry command refuses buffers not visiting a saved file and files outside a project root, prompts to save a modified buffer; renders one flat file section of on-disk content (disk is the single truth, message when the visiting buffer differs) with Annotations interleaved as child sections and the same dim line-number prefix; region at entry only positions point. One file per Review; reload re-reads Sidecar and Source in one pass. Reviewed-tracking degrades to the single file-content mark. Cites ADR-0009, ADR-0011.
