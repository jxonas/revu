# Diff Reviewer

## Agent skills

### Issue tracker

Issues are tracked with the `knot` CLI — markdown tickets under `.tickets/`, project prefix `dcr`. Never read or write `.tickets/` directly. See `docs/agents/issue-tracker.md`.

### Triage labels

The five canonical triage roles map onto knot's native fields: `needs-triage` and `needs-info` are tags, `ready-for-agent`/`ready-for-human` are the `afk`/`hitl` modes, and `wontfix` is a tagged close. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `CONTEXT.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.

## Checks

`eldev test -B`, `eldev lint` and `eldev compile` must all be clean. How to run them, and how to open a Review in a scratch Emacs, is in `docs/agents/checks.md`.

## Coding standards

The rules the reviewer enforces on a diff — lint as a gate, the docstring apostrophe escape, a Sidecar write that renders. See `docs/agents/standards.md`.
