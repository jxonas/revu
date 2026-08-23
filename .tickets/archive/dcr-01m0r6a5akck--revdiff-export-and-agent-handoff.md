---
id: dcr-01m0r6a5akck
title: revdiff Export and agent handoff
status: closed
type: task
priority: 1
mode: afk
created: '2026-08-23T20:52:06.097502211Z'
updated: '2026-08-23T23:36:17.844335241Z'
closed: '2026-08-23T23:36:17.844335241Z'
parent: dcr-01m0r63dzcq8
acceptance:
- title: Exported markdown parses under the pinned grammar for line, range, hunk and file Targets
  done: true
- title: Collisions concatenate; review-level notes dropped with a visible count
  done: true
- title: Renamed and moved Targets export today's paths and numbers; orphans kept at recorded numbers
  done: true
- title: Kill-ring handoff carries the absolute path and the agent contract
  done: true
deps:
- dcr-01m0r6a51n20
---

## Description

The Export per ADR-0006, grammar pinned to docs/research/revdiff-export-format.md (the Go parser is the contract): writes .revu/<review>.md, overwritten each export, prefix argument prompts for a destination; renders resolved current paths (old and new path merged into one group) and re-located line numbers; colliding (File, Line, Type) records concatenate bodies; question Kind maps to the ?? convention; review-level Annotations are dropped with a loud count; orphaned Annotations export at recorded numbers. Export and the sidecar-path command both push the absolute path plus the terse agent contract (ADR-0007) to the kill ring and echo it.

## Notes

**2026-08-23T23:36:17.844335241Z**

revu-export.el writes the Review as the markdown revdiff's plugins already read, byte for byte against the grammar pinned in docs/research/revdiff-export-format.md -- four header shapes, one blank line between records and none at either end, bytewise path order with the file-level record first, one-space escaping of body lines that would open a record, and a range only when its end is past its start. What goes out is today's: resolved paths and re-located line numbers, taken from placements rather than re-derived. Two Annotations revdiff cannot tell apart are concatenated rather than one being silently lost on the way back. Annotations on the Review itself are dropped, and review caught that the count was being echoed and then wiped from the echo area by the handoff a moment later -- it now travels with the handoff. An empty Export writes no file and removes a stale one, so a path handed to an agent never carries withdrawn feedback. Both the Export and revu-sidecar-path put the absolute path and the agent contract on the kill ring.
