---
id: dcr-01m0r6a4rf7e
title: Record and Sidecar persistence
status: open
type: task
priority: 1
mode: afk
created: '2026-08-23T20:52:05.518224635Z'
updated: '2026-08-23T20:52:05.518224635Z'
parent: dcr-01m0r63dzcq8
acceptance:
- title: 'Sidecar round-trips: create, mutate, reload yields equal state; unknown fields survive'
  done: false
- title: Malformed or higher-schema file is refused loudly; last-good state kept; disk untouched
  done: false
- title: External modification blocks writes until reload; force-write overwrites deliberately
  done: false
- title: Re-invoking on the same Source resumes the existing Sidecar, never clobbers
  done: false
deps:
- dcr-01m0r6a4msjd
---

## Description

The Sidecar becomes the review state: Annotation records ({id, kind, target, anchor, body, created, updated}, ULID identity, tagged Targets review/file/line/range, origin on diff lines) per ADR-0003; schema v1 sidecar shape, deterministic resume-by-default Review naming, ULID-ordered annotations, atomic write per mutation per ADR-0005; the reader/writer posture of ADR-0007 — tolerant of unknown fields, whole-file refusal on malformed JSON / higher schema / invalid records with last-good state kept, mtime-plus-hash write guard and a force-write primitive. Verified end to end at the file boundary: mutate a Review programmatically, read the JSON back.
