---
id: dcr-01m0r6a5dmvn
title: Reload and round-trip
status: closed
type: task
priority: 2
mode: afk
created: '2026-08-23T20:52:06.194491766Z'
updated: '2026-08-23T23:36:17.945870605Z'
closed: '2026-08-23T23:36:17.945870605Z'
parent: dcr-01m0r63dzcq8
acceptance:
- title: Reload shows agent Replies inline and appended Annotations in place
  done: true
- title: Reload of a broken Sidecar errors with position, keeps last-good buffer and disk
  done: true
- title: Mutation after external edit is blocked with guidance; force-write overwrites deliberately
  done: true
deps:
- dcr-01m0r6a51n20
---

## Description

The return leg per ADR-0007: a revert-style reload command re-reads the Sidecar and the Source in one pass, re-anchors and re-renders; an agent's reply strings render inline under their Annotation bodies with a distinct face — presence is the answered signal; agent-appended Annotations appear as ordinary sections. Refusal on invalid input keeps the last-good buffer and reports the failure position; the write guard from the persistence ticket is surfaced here as the user-visible flow (blocked mutation message pointing at reload), with the force-write command as the explicit escape hatch.

## Notes

**2026-08-23T23:36:17.945870605Z**

revu-reload re-reads the Sidecar and the Source in one pass, re-anchors and re-renders, so an agent's Replies appear inline under the bodies they answer -- a Reply has a face of its own because its presence is the answered signal -- and Annotations the agent appended render as ordinary sections. Nothing is merged and nothing is watched: the reviewer asks. A Sidecar this revu cannot read refuses loudly and names where the trouble is, leaving the buffer showing the Review it had and the file exactly as the agent wrote it. The write guard from the persistence ticket is surfaced as the user-visible flow: a blocked mutation names revu-reload, and revu-force-write is the one deliberate way past it.
