---
id: dcr-01m25w8z6kdg
title: Publish revu on GitHub
status: in_progress
type: task
priority: 2
mode: afk
created: '2026-09-10T14:41:45.171106328Z'
updated: '2026-09-10T14:41:51.038235755Z'
acceptance:
- title: eldev test -B, eldev lint, eldev compile clean
  done: false
- title: No email address in tracked content
  done: false
- title: Every commit authored by the GitHub noreply address
  done: false
- title: README installs work as written for each package manager
  done: false
---

## Description

Prepare the repository for a public GitHub release at jxonas/revu: README with install instructions for :vc, straight, Elpaca, Doom, Spacemacs and manual; COPYING; CHANGELOG (Keep a Changelog); CONTRIBUTING; CI on Emacs 29.1, 30.2 and snapshot; Package-Requires lowered to the audited floor (emacs 29.1, magit-section 4.3.6, transient 0.3.0); Author lines without email; commit history rewritten to the GitHub noreply address; tag v0.1.0. Not ELPA/MELPA.
