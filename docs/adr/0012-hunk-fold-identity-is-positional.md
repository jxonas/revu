---
status: accepted
---

# A hunk's fold identity is positional, its Reviewed-mark identity is content

A hunk in the review buffer carries two identities, and they want opposite
things from an edit.

The **Reviewed mark** identifies a hunk by the digest of its content
(ADR-0009). That is the whole point of the mark: "I have read this" must stop
being true when "this" changes, so an edit un-matches the assertion and the
hunk renders unreviewed or stale. Content-keyed, and deliberately fragile.

A **fold** identifies the same hunk as a place in the buffer. A fold the
reviewer set is a view state, not an assertion about content, and it should
outlive the edit — reload exists to show the reviewer what changed, and losing
their folds is the buffer sliding out from under them on the one render they
asked for.

Until now both rode on the section's value, `(PATH . HEADER)`. The header text
is derived from content: `@@` numbers regenerate on every `git diff`, so
editing a file anywhere above a hunk gives that hunk a header it never had.
magit-section keys its visibility cache on the identifier it builds from the
value, so the edited file's hunks came back expanded while an untouched file's
stayed folded.

Decision: the value stays `(PATH . HEADER)`, and `revu-hunk-section`
implements `magit-section-ident-value` — the seam magit-section provides for
exactly this — returning `(PATH . INDEX)`. Nothing that looks a hunk up by
value changes, `revu-reviewed` included, and the two identities stay honestly
distinct: content decides what has been read, position decides what is folded.

INDEX counts the hunks the file was **parsed** with, not the hunks a render
kept. The view filters (annotated-only, hide-reviewed) drop hunks before they
are rendered; an index over what was rendered would renumber every hunk below
a dropped one and hand its fold to a different hunk on the next filter toggle.

This decision is positional, so it is honest about its limits: an edit that
adds or removes a hunk above a folded one moves that hunk's index, and the
fold lands on its neighbour. Position is the only thing about a hunk that
survives its content changing, which is the case this exists for; the
alternative is losing the fold every time.

## Considered options

- Making the value itself `(PATH . INDEX)`: touches every caller that looks a
  hunk up by value, and takes away the content identity `revu-reviewed`
  reads off it.
- Keying on the hunk's old-start line: the base side holds still under a
  worktree edit, but not under a rebase or a changed base Revision — and it
  still moves when the change itself moves. The mark's `span` (ADR-0009) is
  the same data serving locality, where being approximate is acceptable; a
  fold lookup is an equality test.
- Keying on the digest of the hunk's content: that is the Reviewed mark's
  identity, and it is fragile on purpose. It fails on exactly the render this
  ADR exists for.
