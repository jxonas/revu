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

## Amendment: the name is not prompted for, and a Review can be renamed, reopened and discarded

The name prompt on every open was the wrong default for day-to-day use: the
reviewer opens a Source, annotates, hands the Export off, and only later —
if at all — decides a Review deserves a name of its own. So the entry
commands open on the derived name with no prompt; a prefix argument asks for
one. The derived-name Review is the *scratch* bucket for its Source: it keeps
resuming, as before, and the open command echoes what it resumed (annotation
count, orphaned count) so a stale bucket is never a surprise. The alternatives
were an ephemeral unnamed Review (rejected: ADR-0002 says every Review
survives a restart, and losing annotations to a crash costs more than a
stray file) and clearing the scratch bucket when the Source moved on or
after an Export (rejected: both guess at intent and would destroy
annotations mid-rebase or mid-conversation).

Three commands make the name worth having. `revu-rename` moves the Sidecar
and its Export to a new name, because the decision to keep a Review usually
arrives after the annotating. `revu-open` completes over every Sidecar on
disk, scratch ones included and marked as such, and rebuilds the Source from
the Sidecar's `source` record; before it, a hand-typed name was reachable
only by retyping it at the prompt. `revu-discard` deletes the Sidecar and its
Export and kills the buffer; it honours the write guard like any other
mutation, so an agent's Reply the reviewer has not loaded cannot be deleted
by reflex.

Sidecars live in `<project-root>/.revu/reviews/<review>.json` and Exports in
`<project-root>/.revu/exports/<review>.md`, no longer side by side: `revu-open`
globs one directory, rename and discard move or delete a pair, and a Review
name can never collide with another kind of file. The folders are named for
the glossary nouns rather than the file types, so `exports/` stays right
when a second exporter arrives (ADR-0006). There is no migration: `.revu/`
is personal, git-ignored, single-user v0 state, and a reviewer with flat
files from before this amendment moves them by hand once.
