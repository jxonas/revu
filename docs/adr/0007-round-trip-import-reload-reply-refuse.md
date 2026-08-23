---
status: accepted
---

# Round-trip import: manual reload, a Reply field, refuse-don't-salvage

Round-trip import is in v0, at its minimal surface: a revert-style **reload
command** that re-reads the sidecar and re-renders the review buffer. No
file-notify watching, no merging — a `question` Kind would be a dead letter if
the agent's answer could only be read outside Emacs, so the return leg ships,
but as one command the load path already mostly implements.

The agent's write contract is fixed in schema v1: an Annotation may carry one
optional **`reply`** string, written by the agent and rendered inline under the
body with a distinct face. A present Reply *is* the answered signal — no
`resolved` flag, threading, or re-open workflow in v0. Agents may also append
their own Annotations (fresh ULIDs) and edit bodies; they delete nothing.

Reads are **tolerant of unknown fields** everywhere (additive evolution is what
made `reply` cheap) but refuse the **whole file** on malformed JSON, a higher
`schema`, or a structurally invalid record. No per-record salvage: reload
errors loudly with the failure position, the buffer keeps its last-good
in-memory state, and the file on disk is left untouched. The write guard from
the same decision — remember mtime/hash at load, block any mutation when the
file changed on disk until a reload — means revu can never silently clobber
agent edits, broken or not. The one escape hatch is an explicit force-write
command that overwrites the sidecar from memory, for when the reviewer judges
the agent's edits garbage. Salvage-what-parses was rejected because silently
dropping an agent's answer is the trust-killer this file format exists to
avoid; auto-restore was rejected because it destroys the evidence.

Root cause of broken sidecars is an uninformed agent, so the kill-ring handoff
(ADR-0006) carries the contract, not just the path: a terse instruction block
("answer questions by setting `reply`; append new annotations with fresh
ULIDs; don't delete or reorder; keep valid JSON"). A separate schema spec file
is post-v0 maintenance we skip.
