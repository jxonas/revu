---
id: dcr-01m0r9smxsrv
title: A pasted unified diff is a Source of its own, recorded whole in the Sidecar
status: closed
type: feature
priority: 2
mode: afk
created: '2026-08-23T21:52:59.321719667Z'
updated: '2026-09-09T21:03:15.157932105Z'
closed: '2026-09-09T21:03:15.157932105Z'
tags:
- needs-triage
acceptance:
- title: ADR-0005 records the patch Source, its derived name and why it stores the diff text whole; ADR-0003 records why a patch Annotation carries no Anchor; the glossary names it
  done: true
- title: revu-diff-buffer reviews a diff with no index headers, and one whose headers name objects this repository lacks
  done: true
- title: Pasting the same text again resumes the same Review; a different text opens a different one
  done: true
- title: revu-reload and revu-open on a patch Review render every file of the recorded diff, with its Annotations and Reviewed marks in place
  done: true
- title: A buffer holding no file diff is refused and leaves no Sidecar
  done: true
- title: The header's Source line names the patch
  done: true
links:
- dcr-01m0rbfvtpkk
---

## Description


A unified diff that is already in a buffer is a Source of its own, not a range. ADR-0005 knows only worktree, staged, range and file, so v0 records a pasted diff as the range between the blob ids its first `index` header names, and refuses any diff whose headers name objects this repository lacks. That gets three things wrong. A diff from a mail, a review page or another machine cannot be reviewed at all. The Review's record claims a range the diff was not taken as. And because on resume the record is the truth (ADR-0005), `revu-reload`, `revu-open` and the first paint of a resumed pasted-diff Review re-read the record with `git diff <blob>..<blob>`, which renders the first file's blobs under a blob id as its path, drops every other file, and orphans every Annotation.

Build the pasted-diff Source end to end. Its kind is `patch` and its record is the diff text itself: the Sidecar is the Review's state (ADR-0002) and a Source must be readable again from its record alone, which a digest cannot do and this repository's objects cannot be relied on to do.

```json
{"kind": "patch", "text": "diff --git a/… b/…\n…"}
```

The derived name is `patch-` followed by a short prefix of the text's digest, so pasting the same text again resumes the same Review and a different text opens a different one. A prefix argument still asks for a name. A patch is immutable, so reading it again parses the recorded text, every file of it, and Reviewed marks keep their hunk digests. Its Annotations carry no Anchor and re-locate at the line they were recorded on: there is no file content on either side to search, and the content the reviewer read can never drift. `index` headers are neither required nor checked. What is refused is a buffer with no file diff in it at all, the same way an empty Source is refused today. The header's Source line names the patch by the digest prefix its name carries.

ADR-0005 records the kind, its record, its name and why the text is stored whole rather than a digest or the blob ids. ADR-0003 records that a patch Annotation needs no Anchor, and the glossary's Source entry names the patch. No schema bump: the kind is new, and a reader older than this refuses it by the kind it does not know. No migration: a Review already recorded as a blob-to-blob range is v0 personal state and is discarded by hand.

## Notes

**2026-08-23T22:49:35.407985322Z**

Phase 3 sharpened the cost of this gap. Anchor capture now reads the Source's own head side — the worktree for a worktree Review, the index for a staged one, `head:<path>` for a range — so a staged or ranged Annotation records the line the reviewer actually saw rather than whatever the worktree had drifted to.

A pasted diff's recorded head is a blob id, and `git show <blob>:<path>` has no file to give, so its line and range Annotations are now created with no Anchor at all and re-locate at the line they were recorded on, permanently fresh. Before, they anchored against the worktree, which was wrong for a diff taken elsewhere but not nothing.

The behaviour is pinned deliberate by `revu-annotate-leaves-a-pasted-diff-s-line-unanchored`: the Annotation is still written, still valid, still rendered. A first-class pasted-diff Source should carry enough per-file provenance to anchor against — note that source.head records only the *first* file's blob, so it cannot serve file N however this is resolved.

**2026-09-09T21:03:15.157932105Z**

A pasted diff is now the `patch` Source, recorded as its own diff text. The
name is `patch-` and a twelve-character prefix of that text's SHA-256, so the
same paste resumes the same Review; the header's Source line says `patch
<prefix>` from the same call, so name and header cannot disagree. `index`
headers are neither required nor looked up, and a buffer with no file diff in
it is refused and leaves no Sidecar. `revu-reload` and `revu-open` parse the
recorded text, so every file comes back with its Annotations and Reviewed
marks. Removed: revu-diff-buffer-revisions, revu-diff-buffer-objects,
revu-diff-object-exists-p and the index regexp, which only the old
blob-to-blob path read.

Two consequences a later ticket needs:

- A patch anchors in nothing on either side (ADR-0003's amendment), and it
  records no `base`. dcr-01m0rbfvtpkk ("every diff Source records a base
  blob") has to name the patch as the exception or be reworded: this ticket
  deliberately did not decide that.
- Path resolution answers `present` for every path of a patch without asking
  git, which no acceptance criterion asked for but AC4 needs: a diff taken
  elsewhere names files this repository has never held, and reading those as
  deleted would orphan Annotations on a Source that cannot change. Recorded in
  ADR-0005's amendment.

Not covered, and left alone: `revu-visit` on a patch Annotation opens the
worktree file at the recorded path, which for a foreign diff says "There is no
X to visit any more" and for a path this repository does have may land on a
line the patch never described. Outside the six criteria.
