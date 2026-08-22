---
status: accepted
---

# Canonical annotation record is ours; revdiff markdown is an exporter

revdiff's `## path:N (+)` markdown is already understood by its Claude Code, Codex and OpenCode plugins, so adopting it verbatim would buy plugin compatibility for free. It carries no kind, no range beyond the "hunk" keyword, and no review-level note, and it is lossy for scripts. We keep a richer canonical record (explicit Kind, explicit line ranges, file-level and review-level Targets) in the sidecar file, and emit revdiff markdown as one Export that maps Kind `question` onto revdiff's `??` convention. Consumers that want plugin compatibility read the Export; everything else reads the sidecar.

## Considered options

- revdiff format as the only format: simplest, but locks the data model to what a Go TUI chose.
- Our own format only: loses the existing agent plugins for no gain.
