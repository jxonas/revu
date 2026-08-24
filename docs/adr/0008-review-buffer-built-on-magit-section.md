---
status: accepted
---

# Review buffer is built on magit-section, not diff-mode plus overlays

The review buffer needs inline annotations, navigation between them, folding, and collapsing of reviewed hunks and files. Two throwaway prototypes on the same fixture diff (branch `prototype/review-buffer-base`) compared built-in `diff-mode` with overlays and `outline-minor-mode` against the standalone `magit-section` library (pr-review's pattern: parse the diff, render a section tree, re-render from state on every change). We build on `magit-section`.

What decided it:

- Reviewed collapsing — the criterion added by the Reviewed-tracking ticket — is the `HIDE` argument of `magit-insert-section` at render time. The diff-mode version needed hand-built pairs of invisible-text and header-tag overlays, the most fragile code in that prototype.
- An annotation is a real section: point can rest on it, `TAB` folds it, delete targets it. As an overlay `after-string` it is visible but never addressable.
- Folding is native and uniform across files, hunks, and annotations; diff-mode needed `outline-minor-mode` bolted on and it only covers diff headings.
- Render-from-state extends directly to plain-file review — render file lines instead of hunk lines. The diff-mode version carries diff assumptions a plain file doesn't satisfy.

Visibility is rendered like everything else. The buffer is built anew every time, so what is folded is resolved — from the Reviewed marks, and from magit-section's visibility cache for the folds the reviewer set by hand — and then applied to the buffer at the end of the render. Nothing carries over on its own: resolving visibility only fills in a slot, and a render that stops there hands back a buffer that is fully expanded, whatever it decided.

The costs, accepted: a dependency on `magit-section` from NonGNU ELPA (within the tolerance already set in the map's notes — never full magit internals), and owning a small diff parser plus renderer (~90 lines in the prototype) instead of getting the substrate free from `diff-mode`. Buffer text must be faced with `font-lock-face`, not `face`, or `global-font-lock-mode` strips it.

## Considered options

- `diff-mode` + overlays: zero dependencies and a free substrate (fontification, hunk bounds, jump-to-source), but every review feature is an overlay hand-rolled onto a buffer with no addressable structure; the prototype was smaller (148 vs 216 lines) yet its reviewed-collapsing was the fragile part, and the gap would widen with every feature.
