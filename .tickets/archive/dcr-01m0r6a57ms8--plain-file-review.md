---
id: dcr-01m0r6a57ms8
title: Plain-file review
status: closed
type: task
priority: 2
mode: afk
created: '2026-08-23T20:52:06.003114491Z'
updated: '2026-08-24T00:07:54.184089814Z'
closed: '2026-08-24T00:07:54.184089814Z'
parent: dcr-01m0r63dzcq8
acceptance:
- title: Entry refuses non-file buffers and out-of-project files; prompts to save modified buffers
  done: true
- title: Buffer renders disk content flat with annotations as child sections and line numbers
  done: true
- title: Annotate, restart, resume works identically to diff review
  done: true
- title: Single file-content Reviewed mark toggles and un-matches on edit
  done: true
deps:
- dcr-01m0r6a54nvk
---

## Description

Reviewing a single file per ADR-0011: entry command refuses buffers not visiting a saved file and files outside a project root, prompts to save a modified buffer; renders one flat file section of on-disk content (disk is the single truth, message when the visiting buffer differs) with Annotations interleaved as child sections and the same dim line-number prefix; region at entry only positions point. One file per Review; reload re-reads Sidecar and Source in one pass. Reviewed-tracking degrades to the single file-content mark. Cites ADR-0009, ADR-0011.

## Notes

**2026-08-24T00:07:54.184089814Z**

revu-file reviews a single saved file in the same dedicated read-only buffer a diff gets, rendered flat: one file section holding every line of the file, Annotations interleaved as child sections at their Anchor lines, and the same dim line-number prefix. Entry refuses a buffer visiting no file and a file outside a project root, and offers to save a modified buffer first. Disk is the single truth -- declining the save reviews what is on disk and says so -- and review found the region's line number was still being taken from the drifted buffer, so point now stays at the top rather than landing somewhere the review buffer is not showing. Reviewed degrades to one mark over the file's content verbatim, which un-matches on an edit and resurrects on a revert. A plain-file Source follows no rename: a missing file orphans its Annotations, and it is still a plain file once it is gone -- review found a deleted file falling back to a diff heading, so what tells the two apart is now the Source rather than whether there is content left to read. A file holding one empty line renders that line.
