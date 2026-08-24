---
status: accepted
---

# Sidecar schema v1: deterministic names, atomic write per mutation

The sidecar `<project-root>/.revu/<review>.json` is:

```json
{"schema": 1,
 "name": "…",
 "source": {"kind": "worktree" | "staged" | "range" | "file",
            "base": "…", "head": "…", "path": "…"},
 "created": "…", "updated": "…",
 "annotations": [ … ]}
```

`schema` is a flat integer, bumped only on breaking shape changes; a reader
refuses a version higher than it knows. Annotations are kept in ULID order —
ULIDs sort by creation time, so append order and sorted order agree and a
diff of the sidecar stays readable. Timestamps are ISO-8601 UTC. Annotation
records themselves are fixed by ADR-0003.

The Review name defaults deterministically from the Source — `worktree`,
`staged`, `main..feature` (with `/` sanitized to `-`), `file-<slugified
path>` — so invoking revu on the same Source *resumes* the existing Review
instead of creating a new one. The command prompts with the default; an
existing sidecar is loaded, never clobbered. Multiple concurrent Reviews per
Source stay out of v0.

Per ADR-0002 the sidecar is the state, not a flush: every Annotation add,
edit, or delete triggers an atomic write (temp file + rename), no debounce,
no explicit save. Reviews are small; a crash window would cost trust in "an
agent can read the file at any moment".

`.revu/` is personal working state in v0 (no `author` field, one reviewer):
documentation recommends git-ignoring it, and revu never edits the user's
`.gitignore` itself.

## Amendment: a Source may be narrowed by pathspecs

A diff Source may carry `paths`, a list of git pathspecs, added for the magit
bridge (ADR-0013): `{"kind": "range", "base": "…", "head": "…", "paths":
["src/foo/", "docs/"]}`. Absent means every path. Reading the Source again
(`revu-reload`) replays the pathspecs, so a narrowed Review stays narrowed;
the alternative, where the first reload widens the diff and re-anchors every
Annotation against it, is the one-shot bridge this amendment exists to
prevent. Nothing else about how the diff is cut is recorded: context count,
whitespace and rename handling stay pinned by revu, because the Reviewed-mark
digests and Path resolution key on them.

A narrowed Source derives a different Review name: the revisions' name with
a slug of the pathspecs appended, `main..feature--src-foo--docs`. The same
narrowing resumes the same Review; the full Review over the same revisions is
a different sidecar and is left alone.

No schema bump: `paths` is optional, and a flat-integer bump would refuse
every v1 reader for one optional field. The known cost is a revu older than
this amendment reading a narrowed sidecar, ignoring `paths`, and rendering
the full diff. The field is experimental with ADR-0013 and may be dropped
with it.
