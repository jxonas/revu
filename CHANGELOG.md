# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- A malformed Sidecar is refused with the right line and column on
  Emacs 29 and 31 as well as 30. Each signals `json-parse-error` with
  differently shaped data, so the place is now counted from the offset,
  which all three put last.

## [0.1.0] - 2026-09-10

### Added

- Review buffers built on `magit-section` for the worktree against HEAD or
  any revision, the index, a revision range, a unified diff in a buffer,
  and a plain file.
- Annotations of three Kinds, `question`, `change` and `note`, on a line,
  a range, a hunk, a file or the Review as a whole.
- Anchors that re-locate an Annotation after the file changes, shown as
  `fresh`, `moved` or `orphaned`, and followed across renames and deleted
  paths.
- Reviewed marks on hunks and files, tied to a digest of the content they
  were taken over, with render filters to hide what is reviewed or show
  only what is annotated.
- The Sidecar: one JSON file per Review under `.revu/reviews/`, written
  atomically on every change, with a write guard against a file an agent
  changed since it was read and a deliberate `revu-force-write` past it.
- Round trip with agents: an agent answers a `question` by writing a reply
  into the Sidecar and may append Annotations of its own; `revu-reload`
  shows both.
- Export as revdiff markdown to `.revu/exports/`, or onto the kill ring,
  with the hand-off contract an agent writes under.
- Reviews resumed by name derived from their Source, with `revu-open`,
  `revu-rename` and `revu-discard`.
- A canonical keymap on top of `magit-section`, first-party evil bindings,
  and a `revu-dispatch` transient palette.
- `revu-magit-mode`, experimental: a switch on the `magit-diff` transient
  that routes magit's diff commands into a Review.

[Unreleased]: https://github.com/jxonas/revu/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/jxonas/revu/releases/tag/v0.1.0
