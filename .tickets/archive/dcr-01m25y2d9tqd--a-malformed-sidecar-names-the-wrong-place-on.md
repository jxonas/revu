---
id: dcr-01m25y2d9tqd
title: A malformed Sidecar names the wrong place on Emacs 29 and 31
status: closed
type: bug
priority: 2
mode: afk
created: '2026-09-10T15:13:07.386599049Z'
updated: '2026-09-10T15:21:59.208417158Z'
closed: '2026-09-10T15:13:07.723583116Z'
acceptance:
- title: eldev -p -dtT test -B, lint, compile clean in a fresh eldev environment
  done: true
---

## Description

CI's first run failed on Emacs 29.1 and snapshot: revu-review-decode reads (nth 0) and (nth 1) of the json-parse-error data as line and column, which is only true on Emacs 30. Emacs 29 puts the parser's message and source first; Emacs 31 puts nil for the column and deprecates the line. The 30.2 job failed too, for a different reason: eldev's packaged mode byte-compiles revu with only its declared dependencies active, so transient-define-prefix expanded under Emacs 30's built-in transient 0.7.2 while the tests ran under 0.13.8, and the keymap test read the older layout format straight off the symbol. transient upgrades that format at runtime, so only the test was wrong.

## Notes

**2026-09-10T15:13:07.723583116Z**

revu-record--json-error-place derives line and column from the offset, the last element of the json-error data in Emacs 29, 30 and 31, checked against each shape. The keymap test reads the palette layout through transient--get-layout, which upgrades a layout compiled under an older transient, instead of the raw symbol property. Reproduced both failures locally by rebuilding .eldev/30.2 from scratch and running eldev -p -dtT test -B; all 337 pass after the fix, lint and compile clean.

**2026-09-10T15:21:59.208417158Z**

The layout fix in 1a86385 was not enough: on Emacs 30 CI byte-compiles and runs revu under the bundled transient 0.7.2, where transient--get-layout does not exist and the layout is (LEVEL CLASS PLIST) inside [LEVEL CLASS ARGS CHILDREN]. The local rebuild had 0.13.8 active, so it never saw that shape. The palette walker now finds the symbol after :command in any list, whichever transient wrote the layout. Verified with emacs -Q against the built-in 0.7.2 and against 0.13.8. Note: magit-section 4.7.1 force-loads transient and warns at load time if it is older than 0.13, without declaring it in Package-Requires.
