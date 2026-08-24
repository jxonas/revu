---
id: dcr-01m0tm74sea7
title: 'Prompt-free day-to-day Reviews: scratch bucket, rename/open/discard, kill-ring Export, reviews/ and exports/ folders'
status: closed
type: feature
priority: 2
mode: afk
created: '2026-08-24T19:33:36.174522639Z'
updated: '2026-08-24T21:26:33.184636422Z'
closed: '2026-08-24T21:26:33.184636422Z'
acceptance:
- title: No entry command prompts for a name without a prefix argument; the magit bridge opens silently
  done: true
- title: Open echoes the resumed annotation and orphaned counts
  done: true
- title: revu-rename moves both files and the buffer follows
  done: true
- title: revu-open lists every sidecar in .revu/reviews/ and reopens one with its original Source (including Narrowing)
  done: true
- title: revu-discard removes both files, kills the buffer, and refuses under the write guard
  done: true
- title: revu-export-kill puts the revdiff body on the kill ring and writes no file; revu-export still writes .revu/exports/<name>.md and hands off path + contract
  done: true
- title: Sidecars are written to .revu/reviews/ and exports to .revu/exports/; commentary and ADRs agree
  done: true
---

## Description

Day to day the reviewer opens a Source, annotates, and wants the rendering on the clipboard; naming a Review is the exception, decided late, for one worth coming back to. Today every entry command prompts for a name (RET takes the derived default), the only clipboard hand-off is the Export file's path plus the agent contract, there is no way to list or reopen a named Review, and sidecars and exports share one flat .revu/. Design grilled and recorded in the amendments to ADR-0005 and ADR-0006 (this commit); CONTEXT.md Sidecar entry updated.

## Design

1. Entry commands (revu-diff-worktree/-staged/-range/-buffer, revu-file, and the magit bridge) open on the derived name with no prompt; C-u asks for a name. 2. On open, echo what was resumed: 'Resumed <name>: N annotations (M orphaned)'. 3. revu-rename: move Sidecar and Export to a new name, rename the buffer. 4. revu-open: completing-read over .revu/reviews/*.json sorted by updated, derived names marked as scratch; rebuild the Source from the sidecar's source record (kind/base/head/path/paths). 5. revu-discard: delete Sidecar and Export, kill buffer; subject to the write guard (revu-sidecar-changed → reload first). 6. revu-export-kill (key W, in the dispatch palette): same revdiff rendering as revu-export, body on the kill ring, nothing written; revu-export and its path+contract hand-off unchanged. 7. Layout: sidecars in .revu/reviews/, exports in .revu/exports/; no migration code — note the one-time manual mv in the commentary. 8. Not in scope: a human-facing exporter; auto-clearing the scratch bucket; multiple concurrent Reviews per Source.

## Notes

**2026-08-24T21:26:33.184636422Z**

Entry commands and the magit Bridge open on the name derived from the Source with no prompt; a prefix argument asks for one, read in the interactive form so a caller never inherits another command's prefix. A resumed Review echoes 'Resumed <name>: N Annotations (M orphaned)', counted off the render rather than a second re-anchoring pass. revu-rename moves the Sidecar and the Export and takes the buffer with them, refusing a name that is a path or one either file already sits under; revu-open completes over every Sidecar in .revu/reviews/ newest-updated first, marks the scratch buckets, and rebuilds the Source from the record including its Narrowing; revu-discard deletes both files and kills the buffer. All three honour the write guard through revu-sidecar-ensure-unchanged. revu-export-kill is the Export's second sink on W (force-write moved to ! in the palette): same rendering, body on the kill ring, nothing written. Sidecars moved to .revu/reviews/ and Exports to .revu/exports/, no migration code. ADR-0002, ADR-0005, ADR-0006 and ADR-0010 carry the amendments; CONTEXT.md gained the scratch bucket. 266 tests green, lint at baseline.
