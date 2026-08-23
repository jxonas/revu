---
id: dcr-01m0qyda4jnd
title: Keymap and evil strategy
status: closed
type: task
priority: 2
mode: hitl
created: '2026-08-23T18:34:00.721997625Z'
updated: '2026-08-23T19:00:32.234541787Z'
closed: '2026-08-23T19:00:32.234541787Z'
parent: dcr-01m0nekb375q
tags:
- wayfinder:grilling
---

## Description

## Question

What are the default key bindings for revu-mode-map across the whole package (mark-reviewed toggle, annotated-only and hide-reviewed toggles, annotation add/edit/delete, navigation, export, reload, force-write), and what is the evil (vim bindings) strategy — emacs-state buffer like classic magit, evil-tolerant default keys, or first-party evil-collection-style bindings shipped by revu?

Constraints surfaced by the reviewed-tracking grill (ADR-0009 fixed the semantics, deferred the keys here):
- SPC is the de-facto evil leader (doom/spacemacs); f/F/n/j/k/g/v are contested evil motions/operators in normal state.
- revdiff parity would suggest SPC (mark reviewed), f (annotated-only), F (unreviewed-only).
- GitHub's 'Viewed' checkbox suggests v-adjacent mnemonics for mark-reviewed.
- magit-section provides TAB folding and section navigation natively; survey how evil-collection treats magit/pr-review-style section buffers before deciding.

## Notes

**2026-08-23T19:00:32.141858844Z**

Resolution — ADR-0010 (docs/adr/0010-keymap-and-first-party-evil-bindings.md):
- One canonical revu-mode-map for the special buffer, atop magit-section natives: a/e/k = add/edit/delete Annotation, r = Reviewed toggle, E = Export, g = reload, RET = visit Target, ? = dispatch.
- Evil strategy: first-party bindings, pr-review pattern — guarded evil-define-key* '(normal motion), no evil dependency, no evil-set-initial-state (normal state). Same mnemonics except motions stay motions: x delete, gr reload, C-j/C-k + gj/gk sections, gh up, [/] siblings, za-family folds — evil-collection-magit-section conventions bound by us.
- revu-dispatch transient on ? is the full palette and the only home of force-write and the annotated-only/hide-reviewed filter toggles. Transient dependency accepted.
- RET-visit-Target is v0 scope (minimal: removed/orphaned Targets message and stay put).
- Constraint fixed for Plain-file review UX: all interaction in the dedicated read-only revu buffer, never a minor mode on the real file buffer.
Rationale anchored in ecosystem survey: new magit-section-derived modes land in evil normal state everywhere (vanilla/Doom/evil-collection), so single letters are shadowed; emacs-state posture is legacy and fails dogfooding (maintainer is Doom evil-first); no evil-tolerant flat keymap exists. Emacs convention beats revdiff key parity — parity lives in the export format.

**2026-08-23T19:00:32.234541787Z**

ADR-0010: one canonical revu-mode-map (a/e/k annotate, r reviewed, E export, g reload, RET visit, ? dispatch) plus first-party guarded evil bindings in normal state (pr-review pattern, evil-collection conventions, no evil dep); transient dispatch is the palette and sole home of force-write and render filters; all interaction stays in the dedicated read-only buffer.
