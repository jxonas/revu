---
id: dcr-01m0r6a4rf7e
title: Record and Sidecar persistence
status: closed
type: task
priority: 1
mode: afk
created: '2026-08-23T20:52:05.518224635Z'
updated: '2026-08-23T21:39:28.616968114Z'
closed: '2026-08-23T21:39:28.616968114Z'
parent: dcr-01m0r63dzcq8
acceptance:
- title: 'Sidecar round-trips: create, mutate, reload yields equal state; unknown fields survive'
  done: true
- title: Malformed or higher-schema file is refused loudly; last-good state kept; disk untouched
  done: true
- title: External modification blocks writes until reload; force-write overwrites deliberately
  done: true
- title: Re-invoking on the same Source resumes the existing Sidecar, never clobbers
  done: true
deps:
- dcr-01m0r6a4msjd
---

## Description

The Sidecar becomes the review state: Annotation records ({id, kind, target, anchor, body, created, updated}, ULID identity, tagged Targets review/file/line/range, origin on diff lines) per ADR-0003; schema v1 sidecar shape, deterministic resume-by-default Review naming, ULID-ordered annotations, atomic write per mutation per ADR-0005; the reader/writer posture of ADR-0007 — tolerant of unknown fields, whole-file refusal on malformed JSON / higher schema / invalid records with last-good state kept, mtime-plus-hash write guard and a force-write primitive. Verified end to end at the file boundary: mutate a Review programmatically, read the JSON back.

## Notes

**2026-08-23T21:39:28.616968114Z**

revu-record.el holds the pure data layer — Source, Target, Annotation and Review constructors and accessors, hand-rolled ULIDs, ISO-8601 UTC stamps, SHA-256 digests, schema-v1 validation — and revu-sidecar.el the I/O: deterministic Review names, atomic temp-and-rename on every mutation, the mtime-then-digest write guard, force-write, and whole-file refusal naming the position of the trouble. Records are held in exactly the shape json-parse-string decodes (alists, vectors, :null, :false), so an unknown field an agent wrote comes back the type it went in — a boolean stays false, not []. Validation reaches the Target's shape: a line Target with no line, a range with no start and end, a pathless file Target, an unknown Origin and a non-string reply each refuse the Sidecar. 26 tests green, lint and compile clean.
