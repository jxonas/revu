---
id: dcr-01m0r6a5akck
title: revdiff Export and agent handoff
status: open
type: task
priority: 1
mode: afk
created: '2026-08-23T20:52:06.097502211Z'
updated: '2026-08-23T20:52:06.097502211Z'
parent: dcr-01m0r63dzcq8
acceptance:
- title: Exported markdown parses under the pinned grammar for line, range, hunk and file Targets
  done: false
- title: Collisions concatenate; review-level notes dropped with a visible count
  done: false
- title: Renamed and moved Targets export today's paths and numbers; orphans kept at recorded numbers
  done: false
- title: Kill-ring handoff carries the absolute path and the agent contract
  done: false
deps:
- dcr-01m0r6a51n20
---

## Description

The Export per ADR-0006, grammar pinned to docs/research/revdiff-export-format.md (the Go parser is the contract): writes .revu/<review>.md, overwritten each export, prefix argument prompts for a destination; renders resolved current paths (old and new path merged into one group) and re-located line numbers; colliding (File, Line, Type) records concatenate bodies; question Kind maps to the ?? convention; review-level Annotations are dropped with a loud count; orphaned Annotations export at recorded numbers. Export and the sidecar-path command both push the absolute path plus the terse agent contract (ADR-0007) to the kill ring and echo it.
