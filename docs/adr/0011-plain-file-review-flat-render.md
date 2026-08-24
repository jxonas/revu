---
status: accepted
---

# Plain-file review is one flat file section in the dedicated buffer

ADR-0010 already fixed *where* plain-file review happens: the dedicated read-only revu buffer, rendered from state (ADR-0008), never a minor mode on the user's editable file buffer. This ADR fixes what that rendering is and what the entry command accepts.

Decisions:

- **Section tree**: one file section containing all of the file's lines, flat, with Annotations interleaved as child sections at their Anchor lines — the diff renderer minus hunk splitting. Folding works at file and annotation level. Synthetic context windows or outline-derived sections (headings, defuns) can layer on later without touching the record; the outline variant is where revdiff's markdown-TOC idea would land, and it stays out of v0.
- **One file per Review**: `Source` stays "a diff or a plain file". The record's Targets could carry any path, but the UX and entry command are single-file; reviewing a set of files in one sidecar is deliberately not offered — that is what diff review is for.
- **Accepted Sources**: the entry command refuses buffers not visiting a saved file (no `*scratch*`, no unsaved new files) — Anchors and digests need on-disk content, and disk is what the agent reads. A modified buffer prompts to save first. Files outside a project root are refused rather than inventing a fallback Sidecar location. TRAMP is not special-cased.
- **Disk is the single truth**: the buffer renders on-disk content even when a visiting buffer has unsaved edits (with a message). `g` re-reads Sidecar and Source in one pass and re-anchors — same reload as ADR-0007.
- **Region at entry** only positions point on the region's start line in the revu buffer; nothing is pre-seeded. Inside the buffer, a region straddling annotation sections targets the file lines it touches; the interleaved sections are ignored.
- **Line numbers** are rendered as a dim text prefix per line — for plain files and diffs alike — because reviewers talk to agents in line numbers. `display-line-numbers-mode` would number annotation sections too, so it is not used.

## Considered options

- Synthetic all-context hunks around annotations: closer to the diff look, but adds windowing logic v0 doesn't need; a flat file with folding covers it.
- Multi-file plain Reviews (Source as a file set): a record and model change for a use case (folder-of-docs review) not yet asked for; left in the fog.
- `display-line-numbers-mode` for numbering: free, but numbers buffer lines, not file lines, once annotation sections are interleaved.

## Amendment: drawing the numbers is optional, and off by default

The prefix bullet above reads as though the numbers only exist when they are drawn. They do not depend on it: every rendered line carries its number in the `revu-target` property it is propertized with, and every Annotation records it, so a reviewer who quotes a line at an agent has the number to quote whether or not the buffer draws it. What this ADR decided is the drawing, and the drawing is a view — revu's own inserted text, four columns at least on every line, and most reading does not want it.

`revu-line-numbers` governs the prefix and nothing else. It defaults to nil, off, because the diff itself is what the reviewer came to read. Turning it on renders the prefix exactly as the bullet above describes. Nothing downstream of the render sees the difference: Annotations, visiting, Export and Reviewed marks all read the Target on the line, never the text in front of it.
