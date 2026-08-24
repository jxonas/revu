---
id: dcr-01m0rne3grr6
title: Every render pays a marker tax from every render before it, so large diffs get slower with use
status: open
type: bug
priority: 2
mode: afk
created: '2026-08-24T01:16:23.957795805Z'
updated: '2026-08-24T01:18:08.912378515Z'
tags:
- render
- perf
acceptance:
- title: A render of a 500-file diff stays flat across at least a dozen successive renders
  done: false
- title: The immutability invariant the fix rests on is stated where render_diff builds the tree
  done: false
- title: A regression test asserts the twelfth render is no slower than the first
  done: false
links:
- dcr-01m0rkxmpxza
---

## Description

Reported against revu v0 QA: on a large diff, adding and removing Annotations and reloading all take a long time.

Measured against a 3.0 MB diff of 52875 lines, 502 files and 1233 hunks. Timings from `eldev emacs --batch`, so they exclude redisplay and font-lock and are a floor, not a ceiling.

| variant                          | first render | steady state                        |
|----------------------------------|--------------|-------------------------------------|
| as shipped                       | 0.73s        | 2.1-3.5s, still climbing at #12     |
| release the old markers first    | 0.73s        | 0.82s flat                          |
| `magit-section-inhibit-markers` t| 0.20s        | 0.20s flat over 12 renders          |

Cause. Every section holds `start`, `content` and `end` as markers into the review buffer. `erase-buffer` does not detach them, and the previous render's tree stays reachable, so each new render's ~52000 insertions must adjust thousands of markers belonging to renders that no longer exist. The cost is paid on every state change, because ADR-0008 routes all of them through a full re-render: annotate, edit, delete, Reviewed-mark toggle, both filter toggles, force-write and reload.

Everything else was measured and acquitted. From an ELP profile of one full render: `revu-reviewed-p` and its digests total 0.09s across 1735 calls, `revu-annotate-placements` 0.002s, `revu-diff-parse` 0.05s. Annotation count barely registers once markers are fixed: 0.27s at none, 0.31s at 50, 0.30s at 200, 0.35s at 1000.

Correction to an earlier reading taken during this investigation, recorded so it is not repeated: a measurement of 0.73s against 2.27s was once attributed to the Reviewed-mark predicates. It was wrong. That second render ran in the same buffer as the first and was paying its marker tax. The predicates are not the problem.

## Design

Bind `magit-section-inhibit-markers` to t around the build in `revu-render-diff`. Sections then carry plain integers for `start`, `content` and `end`, and no markers are created to accumulate.

This is sound here for one specific reason, which should be stated in the code where someone adding an in-place buffer tweak will trip over it: integers cannot go stale because nothing ever edits a review buffer in place. ADR-0008 makes every change a full re-render, and every `insert` in the package is inside the render pass. Verified by grep. If that invariant is ever broken, this optimisation breaks with it.

Prefer t over `delay`. Magit uses `delay` because its washers edit sections in place and need live markers, so it converts everything back to markers at finish — which recreates the population and brings the accumulation back on the next `erase-buffer`. revu does not mutate and does not need what `delay` buys.

Fallback if some magit-section codepath turns out to want real markers: walk the old tree before rebuilding and `set-marker` each position to nil. Measured at 0.82s flat — it stops the growth but leaves ~0.5s of marker overhead on every render.

Verified to compose with dcr-01m0rkxmpxza. The two fixes land together, so they were run together: with `inhibit-markers` t and the `magit-section-show` on the root both active, a collapsed section survives a reload with both `slot=t` and the overlay applied.

Not proposed: lazy per-file rendering. It would help a Source this size, but it amends ADR-0008 and trades away the invariant that keeps the buffer unable to drift from the Sidecar. A 13x improvement from a mechanical change does not justify reopening that.

## Notes

**2026-08-24T01:18:08.738903542Z**

Reviewer accepts ~0.2s per annotate and per reload on a 502-file diff as the bar. Lazy per-file rendering is not wanted, and ADR-0008 stays as it is.
