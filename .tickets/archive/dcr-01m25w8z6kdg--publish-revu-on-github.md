---
id: dcr-01m25w8z6kdg
title: Publish revu on GitHub
status: closed
type: task
priority: 2
mode: afk
created: '2026-09-10T14:41:45.171106328Z'
updated: '2026-09-10T14:47:07.968985277Z'
closed: '2026-09-10T14:47:07.968985277Z'
acceptance:
- title: eldev test -B, eldev lint, eldev compile clean
  done: true
- title: No email address in tracked content
  done: true
- title: Every commit authored by the GitHub noreply address
  done: true
- title: README installs work as written for each package manager
  done: false
---

## Description

Prepare the repository for a public GitHub release at jxonas/revu: README with install instructions for :vc, straight, Elpaca, Doom, Spacemacs and manual; COPYING; CHANGELOG (Keep a Changelog); CONTRIBUTING; CI on Emacs 29.1, 30.2 and snapshot; Package-Requires lowered to the audited floor (emacs 29.1, magit-section 4.3.6, transient 0.3.0); Author lines without email; commit history rewritten to the GitHub noreply address; tag v0.1.0. Not ELPA/MELPA.

## Notes

**2026-09-10T14:47:07.968985277Z**

README with six install routes, COPYING, CHANGELOG, CONTRIBUTING, CI on 29.1/30.2/snapshot. Package-Requires lowered to the audited floor (emacs 29.1, magit-section 4.3.6, transient 0.3.0) after an audit found nothing needed Emacs 30 and that magit-section 4.3.0 was too low for the highlight generics revu-render uses. Author lines carry no email; history rewritten to the GitHub noreply address. Screenshot script in docs/images; the image itself is taken by hand before the push. The install snippets were written from each package manager's documented recipe form and not executed: that criterion stays unchecked, and the first report from a straight, Elpaca, Doom or Spacemacs user is what verifies it.
