---
id: dcr-01m0r6a5gry9
title: Keymap, evil bindings and transient dispatch
status: open
type: task
priority: 2
mode: afk
created: '2026-08-23T20:52:06.290160522Z'
updated: '2026-08-23T20:52:06.290160522Z'
parent: dcr-01m0r63dzcq8
acceptance:
- title: Canonical map drives every command; magit-section natives intact
  done: false
- title: Evil block binds only when evil is loaded; vanilla Emacs unaffected; conventions match evil-collection
  done: false
- title: Transient lists the full palette; force-write and render filters live only there
  done: false
- title: RET visits fresh and moved Targets; removed/orphaned message and stay put
  done: false
deps:
- dcr-01m0r6a54nvk
- dcr-01m0r6a57ms8
- dcr-01m0r6a5akck
- dcr-01m0r6a5dmvn
---

## Description

Bind the finished command set per ADR-0010: canonical revu-mode-map atop magit-section natives (a add, e edit, k delete, r reviewed toggle, E export, g reload, RET visit Target, ? dispatch); the guarded first-party evil-define-key* block in normal/motion state following evil-collection conventions (x delete, gr reload, gj/gk and C-j/C-k sections, gh up, brackets siblings, za/zo/zc/zr folds) with no evil dependency; revu-dispatch transient as the complete palette and the sole home of force-write and the annotated-only/hide-reviewed toggles. RET visits the Target at the resolved current path and re-located line; removed-line and orphaned Targets message and stay put.
