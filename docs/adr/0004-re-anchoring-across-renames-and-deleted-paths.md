---
status: accepted
---

# Re-anchoring follows git renames; path resolution is derived, never persisted

Extends ADR-0003. When a Review loads and a Target's `path` no longer exists,
revu follows renames for git Sources: one `git diff -M --name-status
<base>..worktree` call per load (git's default 50% similarity — a false
positive just orphans the lines when content search fails). Plain-file Sources
never follow: a missing file orphans its Annotations, even inside a git repo,
so behavior does not depend on whether a directory happens to be a repository.
A content-digest fallback for plain files is additive later if this stings.

The rename yields a **path resolution** — `present`, `renamed` (with the new
path), or `deleted` — derived per path at load, beside the per-Annotation
anchor states and under the same rule: never persisted. Anchor states stay
line-scoped: a pure rename with an intact line derives `fresh`; `moved` keeps
its single meaning of "the line was re-found elsewhere than recorded". Deletion
adds no fourth anchor state — the file's Annotations derive `orphaned`, and the
`deleted` path resolution says why, so the UI badges the file header instead of
every line.

The Target `path` is immutable: it records the path at annotation time and is
never rewritten, on load or on save. Removed-line re-location depends on this —
the base blob lives at `git show <base>:<old-path>`, not the new path. After a
rename, new Annotations record the new path, so one file may legitimately
appear under two paths in a sidecar; whoever groups by file resolves them
together.

## Consequences

- An agent reading the sidecar sees paths as they were at annotation time.
  Rendering resolved current paths is the exporter's job: path resolution facts
  are derived and available at export time (Export & sidecar commands ticket).
- Rename following costs one extra git call on load, only when a path is
  missing from the worktree.
