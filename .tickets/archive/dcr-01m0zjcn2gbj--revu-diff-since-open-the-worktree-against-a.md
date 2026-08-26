---
id: dcr-01m0zjcn2gbj
title: 'revu-diff-since: open the worktree against a prompted Revision'
status: closed
type: feature
priority: 2
mode: afk
created: '2026-08-26T17:37:51.689166627Z'
updated: '2026-08-26T22:56:45.302167754Z'
closed: '2026-08-26T22:56:45.302167754Z'
acceptance:
- title: M-x revu-diff-since prompts for a Revision with completion over local branches and tags and accepts free text, and opens the worktree against it under the derived name
  done: true
- title: A prefix argument asks for a name of the Review's own
  done: true
- title: A Revision naming HEAD's commit opens the scratch worktree Review, and a Revision naming nothing is refused with the same message as the other entry commands
  done: true
- title: Re-entering with the same Revision after commits have landed on top resumes the pinned Review, and g shows the new commits and edits against the original base
  done: true
- title: The command is bound alongside the other entry commands and documented where they are
  done: true
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

## Notes

**2026-08-26T22:56:45.302167754Z**

revu-diff-since prompts for a Revision and opens the worktree against it. Completion is over the repository's local branches and tags, read from git (revu-diff-revision-names, for-each-ref over refs/heads and refs/tags) so core revu still does not touch magit; remote branches are not offered, the prompt requires no match, and there is no default. The command delegates to revu-diff-worktree, so there is no new Source kind and no new noun: the Review is the worktree-vs one, named worktree-vs-<rev as typed>, and a prefix argument asks for a name of its own. A Revision naming HEAD's commit opens the everyday worktree Review. A Revision naming nothing is refused where every other unreadable one is, and so is nothing at all -- revu-diff-since resolves up front, because revu-diff-worktree would have read a base of nothing as HEAD. Resuming is the path the dependency fixed: the recorded commit stands however far the Revision has moved, and g shows the commits landed on top and the edits still uncommitted against it. Bound as dS in the revu-dispatch palette beside the other entry commands, and ADR-0005's worktree amendment now names the command. Eight tests in test/revu-render-test.el; 317 tests, lint and compile clean. Commit 1781540.
