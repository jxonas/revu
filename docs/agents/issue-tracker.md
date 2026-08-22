# Issue tracker: knot

Issues live as markdown files under `.tickets/`, managed by the `knot` CLI. Config is `.knot.edn` at the repo root.

## Ground rules

**The CLI is the contract.** `.tickets/` is an implementation detail. Never `cat`, `grep`, `sed`, `mv`, or hand-edit
anything under it — knot keeps `updated` timestamps, the derived graph, and terminal-status/archive placement
consistent on every write, and a hand-edit silently breaks all three. Ids also resolve across live *and* archive, so a
file glob sees only half the corpus.

| Instead of…             | Run                                                                |
| ----------------------- | ------------------------------------------------------------------ |
| `cat` / `head`          | `knot show <id>`                                                   |
| `grep` / `rg`           | `knot list --json \| jq …`                                         |
| `ls`                    | `knot list`                                                        |
| writing a file          | `knot create "<title>" -d "…"`                                     |
| editing a file          | `knot update <id> …` (replace) / `knot add-note <id> "…"` (append) |
| `mv` to/from `archive/` | `knot close <id> --summary "…"` / `knot reopen <id>`               |

Other rules:

- **Drive logic off `--json`, never table output.** Every command takes it; the envelope is
  `{"schema_version": 1, "ok": true, "data": …}`. Column widths shift and titles contain whitespace.
- **Don't read after write.** Mutating commands return the full post-mutation ticket under `.data`:
  `knot create "T" --json | jq -r '.data.id'`. Chaining `knot show` re-reads what you already hold.
- **Filter, don't eyeball.** When the question names a subset, pass the filter (`--type bug`, `--tag needs-triage`,
  `--parent <id>`) rather than listing everything and scanning.
- **Pass partial ids through verbatim.** 6–8 suffix characters usually resolve. On ambiguity knot prints candidates —
  relay them, don't guess.
- `knot info` reports the allowed statuses/types/modes and create-time defaults. `knot <cmd> --help` is the flag
  reference and wins over this file if the two ever disagree.

## This project's vocabulary

- **Prefix**: `dcr` — ids look like `dcr-01kqa9sh4b2c`
- **Statuses**: `open` → `in_progress` → `closed` (`closed` is terminal and archives the file)
- **Types**: `bug`, `feature`, `task`, `epic`, `chore`
- **Modes**: `afk` (agent-runnable) / `hitl` (human in the loop) — default `hitl`
- **Priority**: `0`–`4`, `0` highest, default `2`

## When a skill says "publish to the issue tracker"

`knot create "<title>" [flags]`.

- Always pass `--description`. A title-only ticket makes the next reader reconstruct intent from scratch.
- Write acceptance criteria with `--acceptance "<title>"` (repeatable). It lands in frontmatter and `knot show`
  renders the checklist. A hand-written `## Acceptance Criteria` body section is display-only and never syncs back.
- Set `--mode afk` when the ticket is specified well enough for an agent to run end to end. Otherwise leave the `hitl`
  default. See `triage-labels.md` — this field *is* the ready-for-agent/ready-for-human decision.
- `--tags` at create time is comma-separated (`--tags auth,p0`); after create, use the `--add-tag` / `--remove-tag`
  deltas on `update`.

Multi-line bodies need a quoted-delimiter heredoc so `$vars`, backticks, and quotes pass through literally:

```sh
knot create "Title" -t bug -p 1 --description "$(cat <<'EOF'
body with `code`, $vars, and "quotes" — all literal
EOF
)"
```

**Publishing a spec plus its implementation tickets** (`/to-spec` → `/to-tickets`): create the spec as an
`-t epic`, then create each implementation ticket with `--parent <epic-id>`. Where one ticket must land before
another, wire it at create time with `--dep <id>` — deps gate `knot ready`, so the ordering becomes queryable
instead of prose. Use `--link` for "related context" that carries no scheduling meaning.

## When a skill says "fetch the relevant ticket"

`knot show <id>` — reads archived tickets too. The user will normally pass the id or a partial id directly.

## When a skill says "comment" / "record a finding"

`knot add-note <id> "…"` appends a timestamped entry. It reads stdin, so a heredoc works directly:

```sh
knot add-note dcr-01abc <<'EOF'
note body
EOF
```

Use `add-note` for anything additive. `knot update` **never** appends — `--description` replaces the Description
section and `--body` replaces the whole body, destructively, with git as the only undo.

The same set-semantics trap applies to `--tags`, which replaces the entire tag list. For a one-tag change use
`--add-tag` / `--remove-tag`; for one criterion, `--add-ac` / `--remove-ac`. The deltas are idempotent.

## Lifecycle

```sh
knot start <id>                              # → in_progress
knot status <id> <new-status>                # any transition
knot close <id> --summary "<what shipped>"
knot reopen <id>                             # back out of the archive
```

Always give `knot close` a `--summary`. It lands as a timestamped note and becomes the answer to "what did we ship?"
months later.

Two gates block a transition with exit 1 and a JSON `error.code`:

- `acceptance_incomplete` — closing with an unchecked acceptance criterion. Clear it properly with
  `knot update <id> --ac "<title>" --done`, which composes with `--status`.
- `open_children` — starting *or* closing a ticket with a child in a non-terminal status. Finish the children.

`--force` overrides either; on a terminal target it requires `--summary "<reason>"`.

`knot update` also takes `--status`, `--summary`, and `--force`, so a transition composes with field changes in a
single atomic write — `knot update <id> --add-tag wontfix --status closed --summary "…"`. Prefer that over a mutation
followed by a separate `knot close` whenever the two belong together.

## Wayfinding operations

Used by `/wayfinder`. Knot's graph replaces the map-file-plus-children convention wholesale.

- **Map**: an `-t epic` ticket. Its Notes / Decisions-so-far / Fog accumulate as `knot add-note` entries on the epic.
- **Child ticket**: `knot create "<question>" --parent <epic-id> -d "<the question>"`, with the ticket type
  (`research` / `prototype` / `grilling` / `task`) as a `--tags` value.
- **Blocking**: `knot dep <child> <blocker>`. Directional; knot refuses cycle-creating edges at write time.
- **Frontier**: `knot ready --parent <epic-id>` — open, unblocked children, ordered. Add `--mode afk` for the
  agent-runnable subset. `knot dep tree <id>` shows why something is waiting.
- **Claim**: `knot start <id>`.
- **Resolve**: `knot add-note <id>` with the answer, `knot close <id> --summary "<answer gist>"`, then
  `knot add-note <epic-id>` with the context pointer so the map's Decisions-so-far stays current.

## Project health

- `knot prime` — the whole-project briefing. Its *Ready to close* section lists active tickets with every AC checked.
- `knot blocked` — what's waiting and on what.
- `knot check` — dep cycles, dangling refs, invalid field values, terminal-vs-archive misplacement. Exit `0` clean,
  `1` errors, `2` couldn't scan.

A `SessionStart` hook already runs `knot prime --limit 10`, so project state is usually near the top of the
conversation — read it from there rather than re-running `prime`.
