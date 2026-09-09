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

## Amendment: the worktree may be taken against a Revision, and says so in its name

A worktree Source is a diff against a Revision, and that Revision no longer
has to be `HEAD`: `git diff <rev>` is everything the worktree carries that
`<rev>` does not, committed and uncommitted alike, which is what a reviewer
asking for "everything since the tag" means.

The name is what keeps the two apart. The worktree against `HEAD` is called
`worktree` whatever commit `HEAD` is on — the Review of what is about to be
committed must not fork every time a commit lands — and the worktree against
anything else is `worktree-vs-<revision>`, with the Revision slugged as the
reviewer wrote it. Deriving both from the recorded commit was rejected: the
`HEAD` Review would fork on every commit. Deriving neither was rejected the
other way: a Review against a tag would resume the `HEAD` Review's Sidecar
and read the wrong Source under the wrong Annotations.

The name is derived from the Revision as it was typed and the Source records
the commit it resolved to, exactly as a range does, and for the same reason:
re-anchoring a removed line needs the commit. Whether a base *is* `HEAD` is
asked of the commits, not of the strings: `HEAD` itself and the branch that
is checked out both open the one `worktree` Review rather than a second one
beside it. A Revision naming nothing is refused rather than read as `HEAD`.

Which Reviews read as their Source's scratch bucket follows from that. A
worktree Review is recognised by the name it derives against `HEAD`, so the
everyday one keeps saying it is scratch however far `HEAD` has moved; one
taken against another Revision reads as named, exactly as a Review over a
range does, because its name was what the reviewer typed and its record
holds what that resolved to.

On resume the name is the handle and the record is the truth. A Review whose
Sidecar is already there is over the Source that Sidecar records, and that is
what the first paint renders — not the diff the entry command was about to take
against whatever the Revision resolves to now. The two part as soon as the
branch does: the worktree taken against `main` recorded `C1`, `main` moved on to
`C2`, and opening the worktree against `main` again is that same Review, still
over `C1`.

Rendering the caller's diff instead was a bug rather than a second reading of
what a Review is over. `revu-reload` replays the record and a removed line
re-locates in the recorded base blob, so the buffer swapped its content on the
first `g` and the Annotations made before that had been placed against content
the Review does not hold. Because the record decides, the caller's diff is not
taken at all once the two have parted, and a Review refused for being over
nothing still leaves no Sidecar behind.

The everyday `worktree` Review follows the same rule, and it is the same Review
throughout: it does not fork when `HEAD` moves, and it does not re-base either.
Opened before a commit lands, it stays over the commit it recorded until it is
discarded, which is what starting a fresh one is. Re-basing the record on every
open was rejected for the reason the name is derived the way it is: an
Annotation is anchored in the Source the Review records, and a Review that
quietly moves its base moves the ground under everything already written on it.

What the reviewer is not left to discover is the parting itself. The header says
which commit the Review is over but not that the branch has walked off it, so
the resume echo names both — `Resumed worktree-vs-main against a1b2c3 (main is
now d4e5f6)`. A range says as much of either Revision it was typed with. A
staged Review never says it, because `git diff --cached` is against `HEAD`
whatever the record holds: its recorded base says where a removed line is read
from, not what the reviewer is looking at.

The separator is `-vs-`, not `--`: `--` is already the Narrowing's, and a
Narrowing still slugs its pathspecs onto either name —
`worktree-vs-qa-2026-08-17--src-foo`. The two cannot be confused for one
another, because a slug collapses every run of awkward characters to a
single hyphen and so no Revision can spell `--`.

The Revision is asked for by `revu-diff-since`, which prompts with completion
over the repository's local branches and tags and takes any other Revision as
free text — `revu-diff-worktree`'s own prefix argument is already spent on the
Review's name, so the base needed a command of its own rather than a second
prefix reading. That command adds no Source kind and no noun: "since" is the
reviewer's gesture, and what opens is the worktree-vs Review, named and headed
as such.

No schema change: `base` already holds the commit, and a reader older than
this amendment reads such a Sidecar as the worktree Source it is.

## Amendment: a pasted diff is a Source of its own, recorded whole

A unified diff that is already in a buffer is not a range. It may have come from
a mail, a review page or another machine, and the objects its `index` headers
name may be ones this repository has never held. So it gets a kind of its own:

```json
{"kind": "patch", "text": "diff --git a/… b/…\n…"}
```

The record is the diff text itself. A Source must be readable again from its
record alone — the Sidecar is the Review's state (ADR-0002), and `revu-reload`,
`revu-open` and the first paint of a resumed Review all read the record rather
than whatever the entry command was about to show. A digest cannot do that, and
the blob ids of the `index` headers cannot be relied on to: they are objects of
some other repository. Recording the text is what makes the patch Review reopen
over every file it was taken over instead of over the first file's two blobs.

The name is `patch-` followed by a twelve-character prefix of the text's
SHA-256, taken over the text exactly as recorded. Pasting the same diff again
resumes the same Review; a text differing anywhere opens a different one. A
prefix argument still asks for a name, and the header's Source line says `patch
<prefix>`, so the name and the header can never disagree about which diff is on
screen.

A patch is immutable. Reading it again parses the recorded text, every file of
it; Reviewed marks keep their hunk digests; and Path resolution answers
`present` for every path without asking git, because a diff taken elsewhere
names files this repository need not have and reading those as deleted would
orphan Annotations on a Source that cannot change. `index` headers are neither
required nor checked. What is refused is a buffer holding no file diff at all,
the same way an empty Source is refused, and the refusal leaves no Sidecar.

No schema bump: the kind is new, and a reader older than this refuses it by the
kind it does not know — which is the right answer, since it could not read the
Source either. There is no migration. A Review recorded as a blob-to-blob range
by the version before this one is v0 personal state and is discarded by hand.
