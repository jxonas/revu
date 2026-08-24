---
status: accepted
---

# The revdiff Export renders the resolved present, and drops what revdiff cannot say

revdiff compatibility is table stakes, not the model (ADR-0001): the Export
exists so revdiff's agent plugins work unchanged, and anything richer reads
the sidecar. Additional export formats are additive later — new exporters
over the same record, no migration. Three lossy mappings follow.

**Collisions concatenate.** revdiff identity is `(File, Line, Type)` with a
last-write-wins importer, while two Annotations may share a Target
(ADR-0003). The exporter merges colliding records into one, bodies separated
by a blank line, Kind still visible per body via the `??` convention on
`question`s. Emitting both would silently drop one on any round-trip.

**Review-level Annotations are dropped, loudly.** revdiff has no
review-level record and its parser errors on content before the first `## `
header, so a prose preamble would break importability, and a pseudo-path
file-level header would poison agents with a file that does not exist. The
export command echoes a warning with the dropped count.

**Paths and line numbers are today's, not annotation-time's.** The sidecar
keeps annotation-time paths (ADR-0004) and recorded numbers; the consumer of
an Export acts on today's files. So the exporter emits resolved current
paths — merging a file that appears under old and new path into one group —
and the re-found line number for `moved` Anchors. `orphaned` Annotations are
included at their recorded numbers rather than silently lost: the body still
tells the agent what was meant, and revdiff never validates line existence
on import.

The Export writes to `.revu/<review>.md` beside the sidecar, overwritten on
each export; a prefix argument prompts for an alternate destination. The
export command and `revu-sidecar-path` both push the absolute path to the
kill ring and echo it — that path is what the reviewer hands the agent.

## Amendment: the Export has a second sink, the kill ring; files move to `exports/`

The file Export hands an agent a path plus the agent contract on the kill
ring; nothing put the rendered text itself where a reviewer could paste it
into a pull request, a chat, or a prompt. `revu-export-kill` renders the same
revdiff markdown and puts the body on the kill ring, writing nothing to disk.
It is a separate command rather than a prefix-argument mode of `revu-export`
so that the two hand-offs — a path with a contract, and a body — are never
confused, and the file Export keeps its contract intact. The rendering is
shared unchanged: one rendering, two sinks, so what is pasted and what is on
disk never drift. A human-facing rendering that keeps review-level
Annotations is a separate exporter, additive later as this ADR already
allows, not a variant of this one.

Per the amendment to ADR-0005, the file Export now writes to
`.revu/exports/<review>.md` rather than beside the Sidecar.
