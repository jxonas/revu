---
id: dcr-01m0r9smxsrv
title: 'ADR amendment: a first-class Source for a pasted unified diff'
status: open
type: task
priority: 3
mode: hitl
created: '2026-08-23T21:52:59.321719667Z'
updated: '2026-08-23T21:52:59.321719667Z'
tags:
- needs-triage
acceptance:
- title: ADR-0005 records what a pasted-diff Source is, or records that it stays a range
  done: false
- title: revu-diff-buffer no longer refuses a diff whose index headers name objects this repository lacks, or the refusal is written down as deliberate
  done: false
---

## Description

ADR-0005 fixes source.kind to worktree|staged|range|file. The fourth entry command, revu-diff-buffer, reviews a unified diff that is already in a buffer (epic user story 4), and that Source is none of the four.

v0 does what the build notes decided: revu-diff-buffer reads the Revisions from the diff's own index headers, records source.kind "range" with them, and refuses the buffer with a user-error when they name nothing this repository has. So a diff pasted from a mail, a code-review web page or another machine cannot be reviewed at all, and one that can is recorded as a range it was not necessarily taken as.

Post-v0 work: amend ADR-0005 with a Source that says what a pasted diff is -- the diff text itself, or a digest of it, plus whatever provenance the headers carry -- and a deterministic Review name for it. Anchoring (ADR-0003) needs a story for removed lines when there is no base blob to read; the worktree Source's answer (fresh while unchanged, orphaned otherwise) may carry over.
