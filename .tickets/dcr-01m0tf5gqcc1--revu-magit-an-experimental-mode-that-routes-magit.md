---
id: dcr-01m0tf5gqcc1
title: 'revu-magit: an experimental mode that routes magit''s diff commands into a Review'
status: open
type: feature
priority: 2
mode: afk
created: '2026-08-24T18:05:19.977014267Z'
updated: '2026-08-24T18:05:30.338007551Z'
acceptance:
- title: revu-magit-mode enable installs the advice and the transient switch; disable removes both, and a magit without the mode is untouched
  done: false
- title: revu core byte-compiles and its tests pass with magit absent; revu-magit.el byte-compiles with magit present as a development dependency
  done: false
- title: 'The pure mapping is unit-tested for: committed range passthrough, A...B to merge-base, commit to commit^..commit, staged, unstaged widened to worktree, pathspecs to Narrowing, dropped arguments reported, --no-index and stash refused'
  done: false
- title: The derived Review name abbreviates object ids and the name prompt still appears
  done: false
- title: The mode docstring, the switch docstring and the revu.el Commentary state the mode is experimental and that a log selection excludes its oldest commit
  done: false
- title: No defcustom is added
  done: false
deps:
- dcr-01m0tf4y88xe
links:
- dcr-01m0t3rxangn
---

## Description

ADR-0013. A reviewer with magit enables 'revu-magit-mode' (global minor mode, off by default). It appends a 'Review in revu' switch to the magit-diff transient and advises magit-diff-setup-buffer and magit-revision-setup-buffer: with the switch on, the advice strips it from the arguments and opens a Review over what magit was about to show -- a log selection under 'd d', a 'd r' range, 'd p' pathspecs, 'd s', 'd u', 'd w', 'd c' -- instead of a magit-diff buffer. Disabling the mode removes the advice and the switch. Experimental: the mode docstring and the revu.el Commentary say so.

The mapping (ADR-0013): committed ranges pass through as magit built them, so a log selection is oldest..newest with the oldest excluded, and the switch's docstring says so because magit's does not; A...B resolves to merge-base..B; a commit is commit^..commit; staged is the staged Source; unstaged widens to the worktree Source with a message; pathspecs become the Source's Narrowing (dcr-01m0tf4y88xe); every other diff argument is dropped with a message when any were set; --no-index and stashes refuse with a user-error. Full object ids are abbreviated in the derived name; the name is still prompted for.

## Design

New file revu-magit.el, autoloaded mode only; (require 'magit) inside the mode's enable, never at top level of revu core. Requires magit >= 4.4 (buffer-local names magit-buffer-diff-range, -typearg, magit-buffer-revision-oid; no aliases exist for 4.3). The advice bodies delegate to one pure function, e.g. revu-magit-plan (range typearg args files type) -> either (revu-command . arguments) or (refuse . message), plus a sibling for (rev files). That function is where every decision lives and is unit-tested with magit absent, on a fixture repo where needed for merge-base and rev-parse. The advice wiring and transient-append-suffix are compile-checked only: add magit as a development dependency in Eldev (byte-compile and lint), not a test dependency. Verify first whether transient-append-suffix on 'magit-diff can add the switch to the shared magit-diff-infix-arguments group without it surfacing in magit-diff-refresh (D); if it surfaces there, the advice ignores the switch when the current buffer is a magit-diff-mode buffer being refreshed. Saving the switch with C-x s is allowed and untouched. Out of scope, recorded for later: a per-file render filter from the section at point, a reverse jump from a Review into magit, an unstaged Source, a stash Source.
