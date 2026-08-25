---
id: dcr-01m0v6r6k74h
title: 'Review buffer header: name, Source, Narrowing and progress at the top of the buffer'
status: closed
type: task
priority: 2
mode: afk
created: '2026-08-25T00:57:29.446875737Z'
updated: '2026-08-25T01:16:43.351882708Z'
closed: '2026-08-25T01:16:43.351882708Z'
acceptance:
- title: Header section renders at the top of every Review (diff kinds and plain file) with the layout above, and re-renders current after each change
  done: true
- title: Revisions show short sha + subject, bare sha when the commit is unknown to git
  done: true
- title: Narrowing line appears only for a narrowed Source
  done: true
- title: Reviewed figure counts the whole Source regardless of view filters
  done: true
- title: Review-level Annotations render under the header; orphan-path ones stay loose
  done: true
- title: TAB folds the header and the fold survives re-render
  done: true
- title: '`a` on the header annotates the Review, on a file heading annotates the file, on a line/region as before'
  done: true
- title: Commentary of revu-render.el describes the header; tests cover render, a-dispatch and fold persistence
  done: true
---

## Description

The review buffer has no header: the root section is headingless and the first thing rendered is a loose Annotation or the first file heading. Once the resume echo clears, nothing persistent says which Source the Review is over, whether it is narrowed, or how far along it is. The buffer name carries only the Review name.

## Design

Header as a dedicated `revu-header-section`, first child of the root (not a root heading — folding the root would fold the whole buffer). Rendered from state like everything else (ADR-0008), so it is always current. Expanded by default, foldable with TAB, fold remembered through magit-section's visibility cache (stable ident).

Layout, magit-status style, aligned labels, blank line after:

    Review:    worktree-vs-main (scratch)
    Source:    worktree vs abc1234 Add the header section
    Narrowing: revu-render.el test/
    Annotations: 7 (3 questions · 2 changes · 2 notes), 2 answered, 1 orphaned
    Reviewed:  12/20 hunks, 1 stale

- Review: the name; `(scratch)` badge when `revu-review-scratch-name-p`, mirroring `revu-open`'s completion.
- Source per kind: `worktree vs <rev>`, `staged vs <rev>`, `<rev> .. <rev>` for range, `file <path>` for plain. A Revision renders as `<short sha> <subject>` via `git log -1 --format=%s`; falls back silently to the bare SHA when git cannot find the commit (rebased away; pasted-diff blob hashes). Cached per buffer: Revisions are immutable.
- Narrowing line only when the Source carries pathspecs. Without it two scratch buckets over the same Revisions are indistinguishable (a narrowed Source is a different Source).
- Annotations: total, Kind breakdown, answered (Reply present), orphaned Anchors. Reviewed: reviewed/total hunks over the WHOLE Source (view filters are a lens, not a change of Source), plus stale count. Plain file: a single state word (`unreviewed`/`reviewed`/`stale`) instead of `0/1 files`. Both lines always present (stable shape); zero sub-components omitted.
- Not shown: Sidecar path, created/updated, file count.

Loose Annotations: Review-level Annotations become children of the header section; orphan-path Annotations stay loose between header and first file.

`revu-annotate` (`a`) dispatches on the section under point: header → `revu-annotate-review`, file heading → `revu-annotate-file`, line/region → line/range as today. `f` and `R` stay as explicit routes.

Faces: one new `revu-header-label` inheriting `magit-section-heading` for the labels; values default; `(scratch)` in `shadow`, stale/orphaned figures in `warning`.

Unaffected: Export (renders from the record), Sidecar schema. No glossary term, no ADR (a view of existing terms; easily reversed).

## Notes

**2026-08-25T01:16:43.351882708Z**

Every Review now opens with a header section: name (with the scratch badge), Source per kind with each Revision as its short id and subject, a Narrowing line only when the Source carries pathspecs, the Annotations broken down by Kind with answered and orphaned figures, and the Reviewed figure over the whole Source with a stale count. A plain file says the one word it is in instead of counting hunks it has none of.

The header is the first child of the root and not the root's heading, so folding it leaves the Source. It is drawn from a revu-header the caller hands over (ADR-0008), TAB folds it and the fold survives a re-render on the section's stable value. Review-level Annotations render under it; Annotations on a path the Source does not carry stay loose between the header and the first file.

'a' now dispatches on the section point is in -- header to the Review, file heading to the file, line or selection as before -- passing over an Annotation section, which is not a Target. 'f' and 'R' stay as the explicit routes.

Two fixes fell out of it: revu-rename now re-renders, because the name is on screen; and the per-buffer Revision memo is forgotten on reload, because a commit git did not know may have been fetched since. revu-reviewed-totals answers an unmarked Review by counting alone, which keeps the header off the render path's hot loop on a large Source (93ms to 1ms over 3000 hunks).

300 tests pass, byte-compile and the doc linter clean. New: test/revu-header-test.el (22 tests).
