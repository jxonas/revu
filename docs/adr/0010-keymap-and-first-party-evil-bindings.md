---
status: accepted
---

# One canonical keymap plus first-party evil bindings, transient as the palette

`revu-mode` derives from `magit-section-mode`, and modern evil setups (vanilla evil, Doom, evil-collection) put such buffers in **normal state** — a new mode is on no exception list, so every useful single letter (`SPC f F n j k g v m r e x a`) is shadowed by evil motions. Waiting on an evil-collection PR would leave evil users with a dead keymap we don't control. Emacs ergonomics win over revdiff key parity: revdiff compatibility is the export format (ADR-0006), not the keystrokes.

Decisions:

- **One canonical `revu-mode-map`** designed for the special buffer, on top of magit-section's native bindings (`TAB`/`S-TAB` folds, `n`/`p` sections, `M-n`/`M-p` siblings, `^` up, `1`–`4` levels) and special-mode's `q`/`SPC`-scroll: `a` add Annotation (region → range Target), `e` edit, `k` delete, `r` toggle Reviewed mark, `E` Export, `g` reload from Sidecar, `RET` visit Target, `?` dispatch.
- **First-party evil bindings, pr-review's pattern**: a `(when (fboundp 'evil-define-key*) …)` block binding `'(normal motion)` — no evil dependency, no `evil-set-initial-state` (buffers stay in normal state). Same mnemonics where the letter isn't a load-bearing motion: `a`/`e`/`r`/`E`/`RET`/`?`/`q` as canonical; motions stay motions, so `x` deletes (not `k`), `gr` reloads (not `g`), `C-j`/`C-k` + `gj`/`gk` move by section, `gh` up, `[`/`]` siblings, `za`/`zo`/`zc`/`zr` fold — all matching evil-collection-magit-section conventions but bound by us, so behavior is identical on vanilla evil, Doom, and bare evil-collection. Cost accepted: ~30 lines kept in sync with the canonical map.
- **`revu-dispatch` transient on `?`** is the complete command palette (discoverability, magit-style) and the *only* home of force-write (ADR-0007's escape hatch — deliberately friction-ful) and the annotated-only / hide-reviewed render-filter toggles (ADR-0009's auto-advance reduces the need for direct keys; promote later only if it chafes). Transient is an accepted dependency.
- **`RET` visits the Target** — resolved current path at the Anchor's re-located line — in v0 scope, minimally: removed-line and orphaned Targets message and stay put.
- **All revu interaction happens in the dedicated read-only revu buffer**; plain-file review never installs a minor mode on the user's editable file buffer. This keeps single-key bindings safe everywhere and constrains the Plain-file review UX ticket.

## Considered options

- Emacs-state special buffer, evil via a future evil-collection module (classic magit posture): least code, but degrades badly — evil users get a shadowed, mostly dead keymap until an upstream PR we don't control lands. The maintainer is a Doom evil user; this fails dogfooding.
- Evil-tolerant single keymap (avoid contested letters): no such keymap exists — the survey showed every useful letter is contested in normal/motion state; the result contorts the vanilla experience and still breaks under evil.
