---
id: dcr-01m0r6a4msjd
title: Package skeleton and test harness
status: closed
type: task
priority: 1
mode: afk
created: '2026-08-23T20:52:05.400949536Z'
updated: '2026-08-23T21:39:28.527918732Z'
closed: '2026-08-23T21:39:28.527918732Z'
parent: dcr-01m0r63dzcq8
acceptance:
- title: Package byte-compiles cleanly with magit-section and transient declared
  done: true
- title: ERT batch run builds the fixture git repo and passes
  done: true
- title: .revu/ path helper resolves the project root and refuses paths outside one
  done: true
---

## Description

Stand up the revu package so every later ticket lands on a working base: package headers (Emacs 30.2+, GPL-3-or-later, deps magit-section and transient, prefix revu-), project-root detection with the <project-root>/.revu/ path helper (refusing files outside a project root, per ADR-0011), and an ERT harness whose fixture builder creates a throwaway git repository with committed, staged and worktree changes for command-seam tests. Batch-mode test runner runs green. Cites: ADR-0008 (deps), ADR-0011 (project-root refusal), spec Testing Decisions.

## Notes

**2026-08-23T21:39:28.527918732Z**

revu.el carries the package headers (Emacs 30.2, magit-section 4.3.0, transient 0.13.0 — the lower transient bound Emacs's built-in 0.7.2 would otherwise trip), the defgroup, and the project-root and Sidecar path helpers that refuse a file outside a project root with a user-error rather than inventing a location for it (ADR-0011). An Eldev file pins gnu-elpa and nongnu-elpa so magit-section resolves. test/revu-fixture.el builds a hermetic throwaway repository — committed baseline, staged change, rename and deletion, unstaged worktree change, a second branch for a range, and a plain file — passing the git identity on every mutating command so it needs no HOME. eldev test, eldev lint and eldev compile --warnings-as-errors all exit 0.
