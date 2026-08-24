---
id: dcr-01m0tp3xvnyq
title: Evil j/k and arrows in a Review buffer move by visual line, as evil-collection does in magit
status: closed
type: bug
priority: 2
mode: afk
created: '2026-08-24T20:06:47.924866533Z'
updated: '2026-08-24T20:25:14.562129243Z'
closed: '2026-08-24T20:25:14.562129243Z'
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

## Notes

**2026-08-24T20:25:14.562129243Z**

Bound j, k, <down> and <up> to evil-next-visual-line / evil-previous-visual-line in the evil block of revu-keymap.el, where evil-collection puts them for magit's buffers. Evil's logical-line k stops at the visible boundary before a fold overlay -- the end of a collapsed heading -- while the visual motion keeps the column point was in, the way j and plain previous-line do.

The docstring of revu-keymap-bind-evil says why; no ADR change, as ADR-0010 already scopes the evil block to evil-collection's placement. Section motion (C-j/C-k, gj/gk), the folds and the canonical map are untouched, and the block still runs only under (when (fboundp 'evil-define-key*) ...), so an Emacs without evil is exactly as it was.

Two tests in test/revu-keymap-test.el: the four keys run the visual motions, and nothing binds C-n/C-p in revu-mode-map or the evil map. Caveat worth knowing: evil is not a test dependency (the vanilla test asserts evil-define-key* is unbound), so every evil test here checks placement through a stand-in keymap, not behaviour -- the column-0 outcome itself is not driven by a test. Also note the acceptance criterion said 'column 0'; a visual motion preserves the goal column, so k from column 8 lands on column 8 of the heading, not 0. That is the correct fix and what magit does; the criterion was stricter than any line motion.

231/231 tests pass, byte-compiles, revu-keymap.el lints clean. Commit 1326798.
