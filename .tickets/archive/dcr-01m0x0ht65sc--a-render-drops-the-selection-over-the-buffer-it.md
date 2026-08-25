---
id: dcr-01m0x0ht65sc
title: A render drops the selection over the buffer it destroys
status: closed
type: bug
priority: 1
mode: afk
created: '2026-08-25T17:47:37.541365416Z'
updated: '2026-08-25T18:19:29.638459230Z'
closed: '2026-08-25T18:19:29.638459230Z'
acceptance:
- title: Marking a run from a visual-line selection advances to the section after the run
  done: true
- title: A range Annotation from a visual-line selection leaves point where the render put it
  done: true
- title: evil is a test dependency and both cases have regression tests
  done: true
- title: ADR-0010 records the rule
  done: true
---

## Description

Marking a run of sections reviewed from an evil visual-line selection leaves point on the header section at the top of the buffer instead of on the section after the run.

`revu-render` calls `erase-buffer`, which does not detach markers: every marker in the buffer collapses to position 1. evil holds the visual selection in markers (`evil-visual-beginning`, `evil-visual-end`, `evil-visual-mark`, `evil-visual-point`). After the command returns, `evil-visual-post-command` contracts the region and puts point back at its saved marker, now position 1. revu's own advance runs and lands correctly; evil overwrites it a moment later.

A lone `r` is untouched: no visual state, no markers to collapse. `revu-annotate-dwim` over a visual selection renders the same way and is expected to have the same fault.

## Design

The rule: a render destroys the text a selection was over, so the selection does not survive it. `revu-render` drops it before `erase-buffer` -- `deactivate-mark` for vanilla Emacs, and, guarded by `fboundp` so revu still depends on evil in no way, `evil-exit-visual-state` for evil. It goes before `revu-render--point-now` so the position the render remembers is the reviewer's own, not the end evil expanded the region to.

evil becomes a test dependency in `Eldev`: the fault is the interaction, so no pure test reaches it. The regression tests cover both entry points -- a batch mark and a range Annotation, each from a real visual-line selection.

ADR-0010 is amended with the hazard; no new ADR and no CONTEXT.md term.

## Notes

**2026-08-25T17:53:09.058902502Z**

Fixed in `revu-render--drop-selection`, called first thing in `revu-render-diff` (revu-render.el:563, :609): `deactivate-mark`, and `evil-exit-visual-state` behind an `fboundp` guard.

Reproduced in the suite before fixing: with the call commented out, all four new tests in test/revu-evil-test.el fail with point at 1 -- the header, exactly as reported. evil is a test dependency in Eldev, required by that file and nothing else.

`revu-keymap-leaves-a-vanilla-emacs-alone` dropped its `(should-not (fboundp 'evil-define-key*))` premise, which evil-as-a-test-dependency invalidates; the map is still the vanilla one because it is built when the package loads, before any test file requires evil.

`eldev test -B` (305), `eldev lint` and `eldev compile` are clean.

**2026-08-25T18:19:29.638459230Z**

A render now drops the selection over the buffer it is about to erase.

`erase-buffer` does not detach a marker, so the four markers evil keeps a visual selection in collapsed to position one, and `evil-visual-post-command` -- running after the command was over -- put point back on one of them. Marking a run reviewed from a `V` selection landed the reviewer on the header instead of on the section after the run, overwriting the advance the command had already made. `revu-annotate` over a selection had the same fault.

`revu-render--drop-selection` states the rule once, first thing in `revu-render-diff` and before it reads where the reviewer is: `deactivate-mark`, plus `evil-exit-visual-state` behind an `fboundp` guard, so revu still depends on evil in no way. evil is a test dependency now; test/revu-evil-test.el drives the real pre- and post-command hooks and every one of its four tests fails with point at 1 when the guard is taken out. ADR-0010 carries the reasoning.
