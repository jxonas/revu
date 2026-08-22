# Diff Reviewer

## Agent skills

### Issue tracker

Issues are tracked with the `knot` CLI — markdown tickets under `.tickets/`, project prefix `dcr`. Never read or write `.tickets/` directly. See `docs/agents/issue-tracker.md`.

### Triage labels

The five canonical triage roles map onto knot's native fields: `needs-triage` and `needs-info` are tags, `ready-for-agent`/`ready-for-human` are the `afk`/`hitl` modes, and `wontfix` is a tagged close. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `CONTEXT.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.
