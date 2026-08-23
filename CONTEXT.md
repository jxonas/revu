# Diff Reviewer (revu)

An Emacs package for reviewing diffs and files with inline annotations, persisted as structured data that AI agents and scripts can read.

## Language

**Review**:
A named collection of Annotations over one Source, stored as one sidecar file.
_Avoid_: Session, annotation set

**Annotation**:
One note written by the reviewer and attached to a Target. Carries a Kind.
_Avoid_: Comment, remark, note (as a noun for the record)

**Kind**:
What the reviewer means by an Annotation: a `question` to be answered, a `change` to be made, or a `note` with no action expected.
_Avoid_: Severity, type, category

**Target**:
What an Annotation is attached to: a line, a line range, a whole file, or the Review as a whole.
_Avoid_: Location, position, scope

**Anchor**:
The data stored with a Target that re-locates it against file content after the
Source changes. An Anchor is `fresh` when it still matches, `moved` when it was
re-found elsewhere, and `orphaned` when it was not found at all.
_Avoid_: Position, offset

**Origin**:
Which side of a diff a line belongs to: `added`, `removed`, or `context`.
Removed lines are numbered in the old file, the rest in the new.
_Avoid_: Side, change type

**Path resolution**:
Where a Target's `path` stands at load time: `present`, `renamed` (with the new
path), or `deleted`. Derived per path on load, like Anchor state; never
persisted. _Avoid_: File status, rename state

**Revision**:
The immutable commit a diff Source was generated from.
_Avoid_: Ref, version, base (bare)

**Source**:
The thing under review: a diff or a plain file.
_Avoid_: Input, document, subject

**Export**:
A rendering of a Review in a consumer-facing format, such as revdiff markdown.
_Avoid_: Output, dump, report
