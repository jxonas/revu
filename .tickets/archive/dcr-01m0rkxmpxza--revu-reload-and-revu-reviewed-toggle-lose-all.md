---
id: dcr-01m0rkxmpxza
title: revu-render never applies the visibility it resolves, so every re-render shows the buffer fully expanded
status: closed
type: bug
priority: 1
mode: hitl
created: '2026-08-24T00:49:55.931669512Z'
updated: '2026-08-24T01:39:39.689971173Z'
closed: '2026-08-24T01:39:39.689971173Z'
tags:
- render
acceptance:
- title: Folds survive revu-reload and revu-reviewed-toggle in the reviewer's own Emacs
  done: true
- title: A collapsed section survives revu-reload and revu-reviewed-toggle with the overlay applied, not just the slot set
  done: true
- title: A Reviewed mark collapses its section on a fresh render, without revu-reviewed calling magit-section-hide itself
  done: true
- title: A regression test asserts on-screen invisibility, not the hidden slot
  done: true
links:
- dcr-01m0rkx3k23r
- dcr-01m0rkwmzs2m
- dcr-01m0rmwaeggd
- dcr-01m0rne3grr6
---

## Description

Reported against revu v0 QA. Doom Emacs, Emacs 30.2.50, Magit b6c5125, Transient 0.13.5, Git 2.54.0, gnu/linux.

Open a Review, collapse everything with `magit-section-cycle-global`, `revu-reload`: every fold is gone and the buffer is fully expanded. Happens on every reload and on `revu-reviewed-toggle`.

Root cause. In magit-section, a section's `hidden` slot is only the model; what actually hides text is an `invisible` overlay, and only `magit-section-hide` creates one. A section built with `hidden` non-nil — whether from `magit-insert-section's HIDE argument or from the visibility cache — gets the slot and no overlay. Magit applies the slots afterwards, by calling `magit-section-show` on the root, which walks the children and calls hide or show per slot (magit-section.el:957-960). `revu-render-diff` builds the tree and never does this.

So the resolution machinery is working perfectly and its result is thrown away. Reproduced in batch: after `revu-reload` a collapsed file section reads `slot=t` (the cache hit landed) and `ovl=nil` (nothing on screen is hidden).

Two things this also explains:

- The HIDE argument revu derives from Reviewed marks (revu-render.el:312 and 326) has never had a visual effect. A reviewed section does not come back collapsed on a fresh render, which is what ADR-0008/0009 say it should do. The workaround at revu-reviewed.el:227-232 — calling `magit-section-hide` outright on the just-toggled section after the render — is this bug being routed around for one section at a time, and its comment records the false assumption that a re-render preserves visibility.
- Why annotation insertion and deletion appeared to preserve folds: they re-render the same way and lose the overlays the same way. The difference was in what was folded at the time, not in the code path.

Retired hypotheses, recorded so they are not chased again:

- Version skew in magit-section. Not it. The mechanism is identical in 4.7.0 and in the reviewer's build.
- `magit-diff-expansion-threshold` sitting ahead of `magit-section-cached-visibility` on `magit-section-set-visibility-hook`. Not it. Setting the hook buffer-locally to just `(magit-section-cached-visibility)` did not help.
- A cache miss. Not it. The reviewer confirmed the same `magit-section-ident` before and after `g`, `magit-section-cached-visibility` returning `hide` both times, and the cache holding 53 entries both times.

Four earlier batch runs reported "folds preserved" wrongly, because they inspected the `hidden` slot rather than the overlays. The slot does survive. Only the screen does not.

## Design

Apply the resolved visibility to the buffer at the end of `revu-render-diff`, once the tree is built:

    (magit-section-show magit-root-section)

That is magit's own applier: it recurses over children and calls `magit-section-hide` or `magit-section-show` for each according to its `hidden` slot, creating the overlays. Verified in batch — with this in place a collapsed section survives `revu-reload` with `onscreen-hidden=t`, and the fold the reviewer set is still there.

Follow-on work once this lands:

- Drop the workaround at revu-reviewed.el:227-232 and the comment at 224-226, which asserts something untrue about re-renders. The mark's collapse then comes from the HIDE argument like every other section's, which is what the code was written to expect. Keep the `goto-char` and the advance to the next unread hunk.
- Re-run QA cases 41-47. Every Reviewed-mark case that turns on a section collapsing was passing or failing for the wrong reason.
- ADR-0008 says rendering the same state twice produces the same buffer. It has not been true of visibility. Worth a sentence saying visibility is applied from the model on every render, so that the invariant is stated where someone will read it.

## Notes

**2026-08-24T00:52:09.556621687Z**

Probe run in the live review buffer returned:

    ("/home/jonasrodrigues/.config/emacs/.local/straight/build-30.2.50/magit-section/magit-section.elc"
     t t
     (magit-diff-expansion-threshold magit-section-cached-visibility)
     53)

So: preserve-visibility t, cache-visibility t, cache populated with 53 entries. Nothing is disabled and the cache is being written.

The difference from every batch repro is the hook. `magit-section-set-visibility-hook` runs until the first non-nil return, and in this session full Magit has put `magit-diff-expansion-threshold` AHEAD of `magit-section-cached-visibility`. Every batch run loaded standalone magit-section only, where the hook is just `(magit-section-cached-visibility)`. That is why four repros came up clean, and it retires the version-skew hypothesis in favour of a load-order one: this is about full Magit being loaded, not about which magit-section version is.

`magit-diff-expansion-threshold` is magit's own: past a threshold of seconds spent refreshing, it keeps diff sections collapsed. Its docstring warns it 'can cause sections that were previously expanded to be collapsed'. revu never opted into it; revu-mode inherits it because the hook is global and revu-mode derives from magit-section-mode.

The build is .elc-only and outside this sandbox, so the function body could not be read to confirm what it returns for a `revu-file-section` (which derives from `magit-section`, not `magit-file-section`).

Awaiting the A/B: setq-local the hook to (magit-section-cached-visibility) in the review buffer, collapse, reload. Folds surviving confirms the hook; folds still lost sends this to a cache-lookup-miss investigation instead.

**2026-08-24T00:55:37.040626851Z**

Q1 A/B failed: setq-local'ing the hook to (magit-section-cached-visibility) did NOT restore folds. `magit-diff-expansion-threshold` is innocent; retract the load-order hypothesis from the previous note.

Q2 probe, point on a hunk section, before collapsing and after `g`:

    (((revu-hunk-section "bb.edn" . "@@ -5,11 +5,12 @@") (revu-file-section . "bb.edn") (magit-section . revu-review)) show 53)

Identical both times. Reading: the ident is stable across the render, the cache is not cleared (53 both times), so lookups are hitting. The value looked up is simply wrong. Also note this sample is a hunk, and `magit-section-cycle-global` only hides the root's children (the file sections) -- a hunk inside a collapsed file correctly keeps hidden=nil and caches 'show. So this particular 'show is expected and not itself the defect.

New leading hypothesis, and it does not need any version or config skew: the collapse never writes the cache.

In magit-section, only `magit-section-show` and `magit-section-hide` call `magit-section-maybe-cache-visibility`. `magit-section-cycle-global` has three branches:

  1. `magit-section-show-headings` -- sets visibility with bare `oset child hidden nil`, caches nothing
  2. `magit-section-show-children` -- same, bare oset, caches nothing
  3. `(mapc #'magit-section-hide children)` -- caches

Which branch a given S-TAB takes depends on the buffer's current visibility state. So whether a collapse is recorded at all is state-dependent, which explains both the reviewer's 'every reload' experience and the batch non-repro (that run happened to land on branch 3).

If confirmed, the defect is not a magit bug. It is that revu treats magit-section's visibility cache as its view-state store, and that cache is only ever as complete as whichever magit commands happened to write to it. The assumption recorded at revu-reviewed.el:224-226 is unsound for that reason, independently of any magit version.

Awaiting two checks: (a) does a fold set with `zc`/TAB (which always routes through magit-section-hide) survive `g`, where an S-TAB fold does not; (b) a dump of value/:hidden/:cached over `(oref magit-root-section children)` taken after collapsing and after `g`.

**2026-08-24T01:30:15.027529532Z**

Fixed, with one correction to the Design.

The applier -- (magit-section-show magit-root-section) at the end of revu-render-diff -- is right and is in. But it is not enough on its own, and it makes one thing worse: magit-section-show calls magit-section-maybe-cache-visibility on every section it walks, so after the first render every section has a 'show entry in the visibility cache. In magit-insert-section--create the hook (magit-section-cached-visibility) is consulted first and HIDE is the last cond branch, so a cache entry outranks HIDE. Dropping the revu-reviewed workaround with only the applier in place would have left a Reviewed mark taken in a live buffer collapsing nothing.

So revu-reviewed-toggle now drops what magit memoised for the file section it touched -- that section, and every file or hunk section under it -- before rendering. With no memo the hook returns nil and HIDE, which is the reviewed state, decides: marking collapses, unmarking opens. Every other fold keeps its memo and comes back. Unmarking a file also opens the hunks inside it, which reads as what unmarking means.

Retired hypothesis, recorded so it is not chased again: 'the collapse never writes the cache' (note 2) is wrong. All three branches of magit-section-cycle-global end in magit-section-show -- branches 1 and 2 through magit-section-show-headings and -show-children, which call it on the root -- and that caches recursively. The cache is written on every route.

**2026-08-24T01:35:23.897371451Z**

Review pass found the invalidation over-reaching: toggling one hunk forgot the whole file's memoised visibility, so a sibling hunk the reviewer had folded by hand and not read sprang open. Narrowed to the section toggled, what it covers, and the file it is in; the sibling case now has a test (checked to fail against the wide version). Forgetting a fold moved to revu-render, beside the applier that reads the memo back.

Left for the reviewer: QA cases 41-47, and the acceptance criterion that folds survive in their own Emacs. Everything asserted here is batch, on the overlay rather than the slot.

**2026-08-24T01:39:39.689971173Z**

revu-render-diff now ends by calling magit's own applier, (magit-section-show magit-root-section), so the visibility every render resolves reaches the screen as invisible overlays instead of stopping at the hidden slot. Folds survive revu-reload and revu-reviewed-toggle.

The Design needed one correction. The applier memoises what it applies, and a memo outranks the HIDE a render derives from the Reviewed marks, so dropping the revu-reviewed workaround on its own would have left a mark taken in a live buffer collapsing nothing. revu-reviewed-toggle now forgets the memo where the marks have just changed -- the section toggled, what it covers, and the file it sits in -- and the marks decide again. Every other fold comes back, sibling hunks in the same file included.

Tests assert on-screen invisibility rather than the slot, which is how four earlier repros reported folds preserved when they were not. ADR-0008 gained the invariant: visibility is applied from the model on every render. Reviewer confirmed the fix in their own Emacs.

Commits e8913ac and 518d435.
