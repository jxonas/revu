---
id: dcr-01m0r6a5dmvn
title: Reload and round-trip
status: open
type: task
priority: 2
mode: afk
created: '2026-08-23T20:52:06.194491766Z'
updated: '2026-08-23T20:52:06.194491766Z'
parent: dcr-01m0r63dzcq8
acceptance:
- title: Reload shows agent Replies inline and appended Annotations in place
  done: false
- title: Reload of a broken Sidecar errors with position, keeps last-good buffer and disk
  done: false
- title: Mutation after external edit is blocked with guidance; force-write overwrites deliberately
  done: false
deps:
- dcr-01m0r6a51n20
---

## Description

The return leg per ADR-0007: a revert-style reload command re-reads the Sidecar and the Source in one pass, re-anchors and re-renders; an agent's reply strings render inline under their Annotation bodies with a distinct face — presence is the answered signal; agent-appended Annotations appear as ordinary sections. Refusal on invalid input keeps the last-good buffer and reports the failure position; the write guard from the persistence ticket is surfaced here as the user-visible flow (blocked mutation message pointing at reload), with the force-write command as the explicit escape hatch.
