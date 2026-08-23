---
id: dcr-01m0r6a4msjd
title: Package skeleton and test harness
status: open
type: task
priority: 1
mode: afk
created: '2026-08-23T20:52:05.400949536Z'
updated: '2026-08-23T20:52:05.400949536Z'
parent: dcr-01m0r63dzcq8
acceptance:
- title: Package byte-compiles cleanly with magit-section and transient declared
  done: false
- title: ERT batch run builds the fixture git repo and passes
  done: false
- title: .revu/ path helper resolves the project root and refuses paths outside one
  done: false
---

## Description

Stand up the revu package so every later ticket lands on a working base: package headers (Emacs 30.2+, GPL-3-or-later, deps magit-section and transient, prefix revu-), project-root detection with the <project-root>/.revu/ path helper (refusing files outside a project root, per ADR-0011), and an ERT harness whose fixture builder creates a throwaway git repository with committed, staged and worktree changes for command-seam tests. Batch-mode test runner runs green. Cites: ADR-0008 (deps), ADR-0011 (project-root refusal), spec Testing Decisions.
