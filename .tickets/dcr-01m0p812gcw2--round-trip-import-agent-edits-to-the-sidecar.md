---
id: dcr-01m0p812gcw2
title: 'Round-trip import: agent edits to the sidecar shown in Emacs'
status: open
type: task
priority: 2
mode: hitl
created: '2026-08-23T02:43:36.587943145Z'
updated: '2026-08-23T02:43:36.587943145Z'
parent: dcr-01m0nekb375q
tags:
- wayfinder:grilling
---

## Description

## Question

With schema v1 fixed (ADR-0005), the sidecar an agent edits is well-defined. Decide: is round-trip import in v0 at all — and if so, what is the minimal surface? How does revu notice external edits (revert-style reload command vs file-notify watch), how do agent-written changes render (answered questions, new annotations, edited bodies), and what does the agent write back — a convention inside the existing record (e.g. a reply/resolved field, schema bump?) or free-form body edits only? A 'no, post-v0' answer is acceptable and unblocks the spec breakdown.
