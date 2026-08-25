# Coding standards

Rules the reviewer enforces on a diff. Each one is checkable by reading the change. The design
decisions live in `docs/adr/`, and the vocabulary in `CONTEXT.md`.

## Lint is a gate, not a report

`eldev lint` must be clean before a change is committed.

**A warning already in the code is not permission to add another.** When a warning looks like the
project's style, look at the rendered result before you match it. Two faults in this repo were read
that way and then copied:

- 27 `Ineffective string escape ‘\=’` warnings, each putting a stray `=` into a docstring that
  `C-h f` showed to the reader.
- an `;;;###autoload` cookie stranded on a private helper, because a new function was inserted
  between the cookie and the command it belonged to. The command silently lost its autoload.

Counting the warnings on `HEAD` first and matching that count is the wrong move. It answers whether a
new warning is the same *kind* as the old ones, when the question is whether the kind is legitimate.

## Write an apostrophe in a docstring as `\\='`

In a Lisp string, `\='` reads as plain `=`, so Emacs shows `SOURCE=’s` to the reader. The form that
renders `SOURCE's` is `\\='`. The `re` linter catches every miss.

## A write to the Sidecar renders before it returns

ADR-0008 makes the review buffer a render of state: every change to a Review is a change to the state
followed by a fresh render. So every command that calls `revu-sidecar-write` renders before it
returns.

```
grep -n 'revu-sidecar-write' revu*.el
```

`revu-rename` broke this rule from the day it was written. Nothing found it until the header put the
Review name on screen, because until then no part of the buffer showed the state it changed.

## A cost test exercises the real call path

A test that guards what something costs must call it the way the product calls it. Arguments the real
caller passes and the test omits are cost the test cannot see.
