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

## What the fold invariant rests on

The invariant is magit's visibility cache, and two magit-section
variables decide whether that cache works. `magit-section-cache-visibility`
gates whether a fold is ever written to it — it is a defcustom, and it
takes a list of section types as well as a boolean, so a value naming
magit's own types excludes revu's without the reviewer ever intending
to. `magit-section-preserve-visibility` gates whether the cache is read
back: it can be perfectly populated and still never consulted. That one
is a plain variable rather than a defcustom, so a reviewer arrives at it
through magit's own documentation rather than through `customize` — but
its default is settable all the same.

With either off every hand-set fold dies on every render. There is no
error and nothing on screen to diagnose — the buffer simply comes back
expanded, which is the failure this ADR exists to prevent. revu keeps no
fold memory of its own; the writes are magit's.

So `revu-mode` binds both buffer-locally, and a review buffer keeps the
invariant whatever the reviewer configured for magit. This is a
deliberate exception to revu's posture of inheriting the reviewer's
magit-section configuration rather than overriding it, and it is narrow:
these two control a mechanism revu builds on, not an appearance the
reviewer is entitled to choose. Defending only one would be the worst
outcome — the posture cost paid without the protection bought, since the
write and the read are halves of one guarantee.

ADR-0008 turned down `magit-section-highlight-current` set to nil partly
because it "reaches into the reviewer's own magit-section configuration",
and that is the nearest precedent for this. The line between them is what
the variable governs: the highlight is an affordance the reviewer is
choosing the look of, and these two are the mechanism a documented
invariant is built on.

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
