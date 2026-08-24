---
status: accepted
---

# The sidecar file is the review state, not a flush of it

revdiff keeps annotations in memory and prints them on quit; annotate.el keeps a global database under `user-emacs-directory`. We persist each Review to `<project-root>/.revu/<review>.json` as it is edited, so there is no "flush" step, a review survives an Emacs restart, and an agent outside Emacs can read the file at any moment the reviewer points at it. The cost is that Anchors must survive Source changes between sessions, which makes re-anchoring a first-class design concern rather than an afterthought.

## Amendment: the Sidecar moved into `reviews/`

Per the amendment to ADR-0005, a Sidecar is
`<project-root>/.revu/reviews/<review>.json` rather than sitting directly
under `.revu/`. Nothing else here changes: the file is still the review
state itself, still written through on every mutation, and still what an
agent reads.
