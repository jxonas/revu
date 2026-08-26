---
id: dcr-01m0zjcn2gbj
title: 'revu-diff-since: open the worktree against a prompted Revision'
status: open
type: feature
priority: 2
mode: afk
created: '2026-08-26T17:37:51.689166627Z'
updated: '2026-08-26T17:37:51.689166627Z'
acceptance:
- title: M-x revu-diff-since prompts for a Revision with completion over local branches and tags and accepts free text, and opens the worktree against it under the derived name
  done: false
- title: A prefix argument asks for a name of the Review's own
  done: false
- title: A Revision naming HEAD's commit opens the scratch worktree Review, and a Revision naming nothing is refused with the same message as the other entry commands
  done: false
- title: Re-entering with the same Revision after commits have landed on top resumes the pinned Review, and g shows the new commits and edits against the original base
  done: false
- title: The command is bound alongside the other entry commands and documented where they are
  done: false
deps:
- dcr-01m0zjc68crm
links:
- dcr-01m0tkej1jg9
---

## Description

The reviewer wants a Review of everything that changed since a starting point — a tag, a branch, a commit — committed and uncommitted alike, and to refresh it while an agent keeps committing and editing on top. That is already a Source: the worktree taken against a Revision (ADR-0005's worktree amendment), named `worktree-vs-<rev>`, read anew by `revu-reload`, pinned to the commit the Revision resolved to when it was first opened. What is missing is a way to ask for it from Emacs: `revu-diff-worktree` takes no base interactively, so the Source is reachable only from Lisp or through the magit Bridge.

Add `revu-diff-since`, an entry command that prompts for the base Revision and opens the worktree against it. Decisions from the grill (2026-08-26):

- No new Source kind and no new glossary noun. The command's "since" is the reviewer's gesture; the Review is still the worktree-vs Source and is named and headed as such. The doubled wording is accepted.
- The prompt is `completing-read` over local branches and tags, with free text allowed so any git revision (`HEAD~3`, an abbreviated sha, `@{u}`) can be written. No default: the reviewer knows what they mean. Remote branches are not offered.
- A prefix argument asks for a name of the Review's own, as the other entry commands do. Without one the Review opens on the derived name, `worktree-vs-<rev as typed>`, which reads as named rather than scratch.
- A Revision naming HEAD's commit opens the plain `worktree` Review, exactly as `revu-diff-worktree` decides it; a Revision naming nothing is refused.
- Refresh is the reviewer's `g`. No automatic reload.
- Resuming an existing `worktree-vs-<rev>` keeps the recorded commit even when the typed Revision has moved; the first paint and the resume echo come from the bug ticket this depends on, so this ticket only needs to route through the same path.

Core revu does not depend on magit, so the completion must come from git directly.
