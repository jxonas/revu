# Triage Labels

The skills speak in terms of five canonical triage roles. knot has no "labels" — it has **tags**, plus two native
fields that already carry the meaning of two of the roles. This file maps each role onto the knot representation.

| Role in mattpocock/skills | knot representation    | Meaning                                                 |
| ------------------------- | ---------------------- | ------------------------------------------------------- |
| `needs-triage`            | tag `needs-triage`     | Maintainer needs to evaluate this ticket                |
| `needs-info`              | tag `needs-info`       | Waiting on the reporter for more information            |
| `ready-for-agent`         | `mode: afk`            | Fully specified, ready for an AFK agent                 |
| `ready-for-human`         | `mode: hitl`           | Requires human implementation (the create-time default) |
| `wontfix`                 | tag `wontfix` + closed | Will not be actioned                                    |

## Applying them

```sh
knot update <id> --add-tag needs-triage      # needs-triage
knot update <id> --add-tag needs-info        # needs-info
knot update <id> --mode afk                  # ready-for-agent
knot update <id> --mode hitl                 # ready-for-human

# wontfix — tag and close in one write; the summary is the record
knot update <id> --add-tag wontfix --status closed --summary "wontfix: <why this won't be actioned>"
```

Use `--add-tag`, never `--tags` — the latter replaces the whole list and would drop tags you hadn't read first.

When triaging, clear the intake tag as you assign the outgoing role:
`knot update <id> --remove-tag needs-triage --mode afk`.

## Why modes rather than tags for the two ready- roles

`mode` is knot's native afk/hitl dimension and other tooling routes off it. Expressing the ready-for-agent decision
as `--mode afk` means `knot ready --mode afk` and `knot prime --mode afk` return exactly the triaged, agent-runnable
queue with no extra bookkeeping. A `ready-for-agent` tag would leave `mode` at its `hitl` default and those queries
would silently disagree with the triage decision.

## Why wontfix is a close, not just a tag

`closed` is this project's only terminal status, so closing archives the file and takes the ticket out of `list`,
`ready`, and `blocked`. The `wontfix` tag is what keeps it distinguishable from work that actually shipped, and the
`--summary` is the durable record of *why* it was declined — recovered later with `knot show <id>`, which reads the
archive, or `knot list --tag wontfix`.

Use `knot update` rather than `knot close` here. `update` takes `--status`, `--summary`, and `--force` alongside the
tag deltas, so the tag and the transition land as a single atomic write with the reason attached. Splitting it into
`--add-tag` then `knot close` is two writes that can half-succeed, leaving an archived ticket with no `wontfix` tag.

If the ticket carries unchecked acceptance criteria, the transition hits the `acceptance_incomplete` gate. That's the
intended case for an override — on a terminal target `--force` requires `--summary`, which you are already passing:

```sh
knot update <id> --add-tag wontfix --status closed --force --summary "wontfix: <reason>"
```

## Finding triaged work

```sh
knot list --tag needs-triage        # the intake queue
knot list --tag needs-info          # waiting on the reporter
knot ready --mode afk               # triaged, unblocked, agent-runnable
knot list --tag wontfix             # declined, across live and archive
```
