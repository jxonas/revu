---
id: dcr-01m0tp3xvnyq
title: Evil j/k and arrows in a Review buffer move by visual line, as evil-collection does in magit
status: open
type: bug
priority: 2
mode: afk
created: '2026-08-24T20:06:47.924866533Z'
updated: '2026-08-24T20:06:48.214161587Z'
acceptance:
- title: In evil normal and motion state, j, k, <down> and <up> in a Review buffer are the visual-line motions
  done: false
- title: Moving up onto a collapsed section's heading with k leaves point at column 0 of the heading
  done: false
- title: Section motion (C-j/C-k, gj/gk) and non-evil C-n/C-p are unchanged
  done: false
- title: The docstring of the evil binding function says why the four keys are rebound; no ADR change
  done: false
- title: An Emacs without evil is left exactly as it was
  done: false
links:
- dcr-01m0tp3xyh6a
- dcr-01m0tp3y1th9
---

## Description

Moving up with `k` onto a collapsed file or hunk section leaves point at the *end* of the heading, while `j` lands on column 0. Section motion (`C-k`, `gk`) does not have the problem.

Cause: evil's `j`/`k`/`<up>`/`<down>` are logical line motions. Going up onto a collapsed section they stop at the visible boundary before the fold overlay, which is the end of the heading line. revu inherits these from evil untouched: its evil block binds only section motion and folds. Non-evil `C-n`/`C-p` move by visual line and land at column 0.

## Design

Bind `j`, `k`, `<down>`, `<up>` in the evil block to the visual-line motions, matching evil-collection's magit placement. This stays within ADR-0010 (first-party evil bindings mirror evil-collection's placement for magit-section buffers); only the docstring of the binding function needs a sentence. Nothing for non-evil users.

Decided in a grilling session on 2026-08-24, together with the `r` advance rule and the line-number defcustom.
