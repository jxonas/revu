---
id: dcr-01m0t3rxangn
title: Say in the Commentary what revu does with the reviewer's magit-section configuration
status: open
type: task
priority: 3
mode: afk
created: '2026-08-24T14:46:12.561000279Z'
updated: '2026-08-24T18:05:36.445024057Z'
acceptance:
- title: revu.el's Commentary states that revu inherits rather than overrides magit-section configuration
  done: false
- title: It names both variables revu binds buffer-locally, and says they defend the fold invariant rather than an appearance
  done: false
- title: It shows the revu-mode-hook form a reviewer would write to change anything else
  done: false
- title: No new defcustom and no README are added
  done: false
deps:
- dcr-01m0t3r7pwkk
- dcr-01m0t3rkpff2
links:
- dcr-01m0tf5gqcc1
---

## Description

A reviewer who has configured magit-section has no way to know what revu honours and what it overrides. revu's stance is worth one paragraph: it inherits the reviewer's magit-section configuration rather than overriding it, expresses what it needs of its own through its faces and its section classes, and makes exactly two exceptions -- both to protect the fold invariant, neither to assert a look.

The Commentary header of 'revu.el' is the home for this. It is where Emacs package users look first, it is what ELPA renders, and it travels with the code. Creating a README for one paragraph would be letting this question force a documentation surface the project does not otherwise need yet.

## Design

Blocked by both bugs because it describes their outcomes: the two exceptions it names are the variables the fold-invariant ticket binds, and the 'headings are highlighted, bodies are not' rule is what the highlight ticket establishes. Writing it before they land would document an intention rather than the code.

Ships no defcustom. A reviewer who wants something different writes a 'revu-mode-hook', and the Commentary shows the form.

## Notes

**2026-08-24T18:05:36.445024057Z**

The magit posture paragraph now has a second half (ADR-0013, dcr-01m0tf5gqcc1): revu-section configuration is inherited, and magit proper is reached only through the opt-in, experimental revu-magit-mode, which lives in its own file and is never loaded by the core. When the Commentary is written, say both in the same paragraph so a reader sees one stance, not two. If this ticket lands before the mode does, name the mode as forthcoming; ADR-0013 is the reference either way.
