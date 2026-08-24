---
id: dcr-01m0r6a5gry9
title: Keymap, evil bindings and transient dispatch
status: closed
type: task
priority: 2
mode: afk
created: '2026-08-23T20:52:06.290160522Z'
updated: '2026-08-24T00:07:54.291284618Z'
closed: '2026-08-24T00:07:54.291284618Z'
parent: dcr-01m0r63dzcq8
acceptance:
- title: Canonical map drives every command; magit-section natives intact
  done: true
- title: Evil block binds only when evil is loaded; vanilla Emacs unaffected; conventions match evil-collection
  done: true
- title: Transient lists the full palette; force-write and render filters live only there
  done: true
- title: RET visits fresh and moved Targets; removed/orphaned message and stay put
  done: true
deps:
- dcr-01m0r6a54nvk
- dcr-01m0r6a57ms8
- dcr-01m0r6a5akck
- dcr-01m0r6a5dmvn
---

## Description

Bind the finished command set per ADR-0010: canonical revu-mode-map atop magit-section natives (a add, e edit, k delete, r reviewed toggle, E export, g reload, RET visit Target, ? dispatch); the guarded first-party evil-define-key* block in normal/motion state following evil-collection conventions (x delete, gr reload, gj/gk and C-j/C-k sections, gh up, brackets siblings, za/zo/zc/zr folds) with no evil dependency; revu-dispatch transient as the complete palette and the sole home of force-write and the annotated-only/hide-reviewed toggles. RET visits the Target at the resolved current path and re-located line; removed-line and orphaned Targets message and stay put.

## Notes

**2026-08-24T00:07:54.291284618Z**

revu-keymap.el gathers the finished command set. The canonical revu-mode-map sits on top of magit-section's natives through :parent, so TAB, n/p, M-n/M-p, ^, the level digits, q and SPC keep working, and adds a add, e edit, k delete, r reviewed toggle, E export, g reload, RET visit and ? dispatch. The evil bindings are first-party and guarded on evil-define-key* being bound, so a vanilla Emacs never sees them and there is no evil dependency; they follow evil-collection conventions, moving delete to x and reload to gr where the canonical letters are motions. revu-dispatch is the complete palette and the only way to revu-force-write and the two render filters, which are meant to cost a detour; review found the entry commands unreachable from it, so starting another Review is in the palette too (user story 36 asks it to list every command). RET visits the Target at its resolved path and re-located line, and a removed-line or orphaned Target messages and stays put rather than guessing.
