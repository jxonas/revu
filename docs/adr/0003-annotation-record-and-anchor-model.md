---
status: accepted
---

# The canonical Annotation record, and Anchors that re-locate against file content

An Annotation is `{id, kind, target, anchor, body, created, updated}`. `id` is a
ULID and is the record's identity, so two Annotations may share a Target (a
`question` and a `change` on the same line); revdiff cannot express that, and
resolving the resulting export collision belongs to the Export ticket. `target`
is a tagged object — `review`, `file`, `line`, or `range` — rather than
revdiff's `Line == 0` sentinel; the exporter flattens to sentinels on the way
out. A hunk annotation is a `range`, not a fifth type.

A diff-line Target carries `origin` (`added | removed | context`) alongside its
single file line number, following revdiff's rule that removals are numbered in
the old file and everything else in the new. `origin` determines the side, so
revdiff's `(File, Line, Type)` export key derives mechanically from the record.
A plain-file Target is the same shape with `origin` absent — the Source kind
lives once on the Review, not on every Annotation.

The Anchor stores the annotated line verbatim (no trailing newline), three lines
of leading and trailing context, and a digest of the anchored file's content;
a `range` anchors both endpoints independently plus the line count. Re-location
searches **file content, never the diff**: diff line offsets are an artifact of
the hunk algorithm and are regenerated on every `git diff`, while path plus side
plus content survives a rebase. Search order is digest match (line number
trusted), then exact line-text match nearest the recorded number, then the same
with leading and trailing whitespace stripped, then the context window; ties
inside the window orphan the Annotation rather than guess. Anchor state —
`fresh`, `moved`, `orphaned` — is derived on load and never persisted, because a
stored state is a lie as soon as the file is edited outside Emacs.

## Consequences

- Because removed lines are absent from the working tree, a Review records the
  Revisions its Source came from (`base`, and `head` for a ref range) and
  re-locates them inside `git show <base>:<path>`. An uncommitted working-tree
  Source has no base blob, so its removed-line Anchors are `fresh` while the
  worktree is unchanged and `orphaned` otherwise.
- Context size is fixed at three lines and baked into the record, so an agent
  reading the sidecar needs no Emacs configuration to interpret it. The search
  radius is a defcustom (default 500 lines) and only governs the degraded path.
- This ADR fixes only the Review fields anchoring requires (Source kind, `base`,
  `head`). Sidecar naming, schema version, ordering, and review-level note
  handling are the Export & sidecar commands ticket's to settle.
- No `author` field in v0. It is additive when a multi-reviewer story exists.

## Amendment: a patch Annotation carries no Anchor

An Anchor re-locates a Target against file content after the Source changes. A
patch Source (ADR-0005's amendment) has neither half of that. There is no file
content to search — the diff may have been taken on another machine, and
`git show` has nothing to give for a path this repository has never held — and
there is nothing to drift, because the record is the diff text the reviewer
read and a patch is immutable.

So a `line` or `range` Annotation on a patch is written with `anchor` absent,
and re-locates at the line it was recorded on: permanently `fresh`. That is the
same path an Annotation an agent appended without an Anchor already takes, and
it is exact here rather than a fallback. A patch also records no `base`: it was
not necessarily taken here, so there is no blob for a removed line to be read
from, and it needs none, because the diff text is what holds the line.
