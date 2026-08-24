---
id: dcr-01m0tm74sea7
title: 'Prompt-free day-to-day Reviews: scratch bucket, rename/open/discard, kill-ring Export, reviews/ and exports/ folders'
status: open
type: feature
priority: 2
mode: afk
created: '2026-08-24T19:33:36.174522639Z'
updated: '2026-08-24T19:33:36.174522639Z'
acceptance:
- title: No entry command prompts for a name without a prefix argument; the magit bridge opens silently
  done: false
- title: Open echoes the resumed annotation and orphaned counts
  done: false
- title: revu-rename moves both files and the buffer follows
  done: false
- title: revu-open lists every sidecar in .revu/reviews/ and reopens one with its original Source (including Narrowing)
  done: false
- title: revu-discard removes both files, kills the buffer, and refuses under the write guard
  done: false
- title: revu-export-kill puts the revdiff body on the kill ring and writes no file; revu-export still writes .revu/exports/<name>.md and hands off path + contract
  done: false
- title: Sidecars are written to .revu/reviews/ and exports to .revu/exports/; commentary and ADRs agree
  done: false
---

## Description

Day to day the reviewer opens a Source, annotates, and wants the rendering on the clipboard; naming a Review is the exception, decided late, for one worth coming back to. Today every entry command prompts for a name (RET takes the derived default), the only clipboard hand-off is the Export file's path plus the agent contract, there is no way to list or reopen a named Review, and sidecars and exports share one flat .revu/. Design grilled and recorded in the amendments to ADR-0005 and ADR-0006 (this commit); CONTEXT.md Sidecar entry updated.

## Design

1. Entry commands (revu-diff-worktree/-staged/-range/-buffer, revu-file, and the magit bridge) open on the derived name with no prompt; C-u asks for a name. 2. On open, echo what was resumed: 'Resumed <name>: N annotations (M orphaned)'. 3. revu-rename: move Sidecar and Export to a new name, rename the buffer. 4. revu-open: completing-read over .revu/reviews/*.json sorted by updated, derived names marked as scratch; rebuild the Source from the sidecar's source record (kind/base/head/path/paths). 5. revu-discard: delete Sidecar and Export, kill buffer; subject to the write guard (revu-sidecar-changed → reload first). 6. revu-export-kill (key W, in the dispatch palette): same revdiff rendering as revu-export, body on the kill ring, nothing written; revu-export and its path+contract hand-off unchanged. 7. Layout: sidecars in .revu/reviews/, exports in .revu/exports/; no migration code — note the one-time manual mv in the commentary. 8. Not in scope: a human-facing exporter; auto-clearing the scratch bucket; multiple concurrent Reviews per Source.
