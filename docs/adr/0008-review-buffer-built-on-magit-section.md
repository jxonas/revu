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

The current-section highlight is specialised, not left alone. magit-section covers a section's whole body when point is in it, which flattens the faces the render put on the very lines the reviewer is reading: the Origin colouring of a diff line, and the Reply that tells an answered Annotation from an unanswered one (ADR-0007). A plain file has no hunk section at all (ADR-0011), so its lines sit under the file section and lose their faces the moment point is on the file. Revu gives its three section classes a shared `revu-section` parent and specialises `magit-section-highlight` on it once: the heading is highlighted, the body is left as rendered. That is a public `cl-defmethod`, the same extension point `magit-section-ident-value` is specialised through (ADR-0012), not a reach into magit internals — the boundary this decision drew. No face is passed, so the heading takes whatever the reviewer has themed `magit-section-highlight` to; revu has no opinion about what "you are here" should look like.

The costs, accepted: a dependency on `magit-section` from NonGNU ELPA (within the tolerance already set in the map's notes — never full magit internals), and owning a small diff parser plus renderer (~90 lines in the prototype) instead of getting the substrate free from `diff-mode`. Buffer text must be faced with `font-lock-face`, not `face`, or `global-font-lock-mode` strips it.

## Considered options

- Magit's paint protocol for the highlight — bind the `painted` slot and implement `magit-section-paint`, the way magit's own diff buffers keep their colours. It is the one escape that covers every section shape, at the cost of a repaint method, a pair of highlight-variant faces and a repaint on every move of point between sections. It can be adopted later without changing anything outside the renderer, so it is not foreclosed.
- `magit-section-highlight-current` set to nil — zero code, but it buys readability back by discarding the current-section affordance altogether, and reaches into the reviewer's own magit-section configuration to do it.
- `diff-mode` + overlays: zero dependencies and a free substrate (fontification, hunk bounds, jump-to-source), but every review feature is an overlay hand-rolled onto a buffer with no addressable structure; the prototype was smaller (148 vs 216 lines) yet its reviewed-collapsing was the fragile part, and the gap would widen with every feature.
