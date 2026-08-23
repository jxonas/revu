---
id: dcr-01m0qyda4jnd
title: Keymap and evil strategy
status: open
type: task
priority: 2
mode: hitl
created: '2026-08-23T18:34:00.721997625Z'
updated: '2026-08-23T18:34:00.721997625Z'
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
