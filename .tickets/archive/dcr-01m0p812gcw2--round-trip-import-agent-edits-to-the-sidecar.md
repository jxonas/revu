---
id: dcr-01m0p812gcw2
title: 'Round-trip import: agent edits to the sidecar shown in Emacs'
status: closed
type: task
priority: 2
mode: hitl
created: '2026-08-23T02:43:36.587943145Z'
updated: '2026-08-23T17:44:38.454459228Z'
closed: '2026-08-23T17:44:38.454459228Z'
parent: dcr-01m0nekb375q
tags:
- wayfinder:grilling
---

## Description

## Question

With schema v1 fixed (ADR-0005), the sidecar an agent edits is well-defined. Decide: is round-trip import in v0 at all — and if so, what is the minimal surface? How does revu notice external edits (revert-style reload command vs file-notify watch), how do agent-written changes render (answered questions, new annotations, edited bodies), and what does the agent write back — a convention inside the existing record (e.g. a reply/resolved field, schema bump?) or free-form body edits only? A 'no, post-v0' answer is acceptable and unblocks the spec breakdown.

## Notes

**2026-08-23T17:44:33.675953833Z**

Resolved — ADR-0007 (docs/adr/0007-round-trip-import-reload-reply-refuse.md). Round-trip import IS in v0, minimal surface: a manual revert-style reload command (no file-notify, no merge). Schema v1 gains one optional 'reply' string per Annotation — agent-written, rendered inline with a distinct face; presence of a Reply is the answered signal (no resolved flag/threading). Reader is tolerant of unknown fields but refuses the whole file on malformed JSON, higher schema, or invalid records — reload errors loudly, buffer keeps last-good state, file untouched; write guard (mtime/hash at load) blocks mutations after external edits until reload; explicit force-write command is the escape hatch. Kill-ring handoff carries a terse agent contract block, not just the path. New glossary term: Reply.

**2026-08-23T17:44:38.454459228Z**

ADR-0007: round-trip import in v0 as a manual reload command; schema v1 adds optional 'reply' on Annotations (presence = answered); tolerant of unknown fields, whole-file refusal on invalid; mtime write guard + force-write escape; kill-ring handoff carries the agent contract.
