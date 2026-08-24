---
id: dcr-01m0tf5gqcc1
title: 'revu-magit: an experimental mode that routes magit''s diff commands into a Review'
status: closed
type: feature
priority: 2
mode: afk
created: '2026-08-24T18:05:19.977014267Z'
updated: '2026-08-24T18:50:16.081784130Z'
closed: '2026-08-24T18:50:16.081784130Z'
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

## Notes

**2026-08-24T18:48:45.996997764Z**

Deviation from the acceptance line 'every other diff argument is dropped with a message when any were set': magit always passes its own defaults --stat and --no-ext-diff, so reporting literally every argument would put a message on every single invocation. Those two pass unremarked -- --stat asks for a summary section revu does not render, and revu's own diffs already pass --no-ext-diff, so neither changes how a change is cut. Everything else is named. Recorded in ADR-0013.

**2026-08-24T18:50:16.081784130Z**

revu-magit.el: a global minor mode, off by default, that appends a 'Review in revu' switch to the magit-diff transient and advises magit's diff-setup funnels. The mapping lives in revu-magit-plan and revu-magit-revision-plan, which never touch magit; 19 tests cover it with magit absent, against the fixture repo for merge-base and rev-parse. Magit is a build/lint dependency only.

Three findings the design did not anticipate. (1) Stashes needed a third advice: magit-stash-show has its own funnel, magit-stash-setup-buffer, and never reaches magit-diff-setup-buffer. (2) The switch would have surfaced in magit-diff-refresh (D) through the shared magit-diff-infix-arguments group, so it is appended beside the transient's own actions instead; verified with magit 4.7 that disable restores magit-diff's layout exactly and leaves magit-diff-refresh's untouched. (3) Magit always passes --stat and --no-ext-diff, so those two are dropped unremarked -- see the note above.

Object ids are abbreviated through git rev-parse --short, which is the length magit's log shows. The worktree and staged Sources are both against HEAD, so a prefix-argument revision is compared as the commit it names and refused when it is another one. ADR-0013 amended with the stash funnel, the switch placement, the corrected magit-revision-setup-buffer signature and the version guard. 228 tests pass; compile and lint clean.
