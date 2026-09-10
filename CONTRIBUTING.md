# Contributing

Bugs and requests go to [GitHub Issues](https://github.com/jxonas/revu/issues).
For a bug, say which Emacs and which `magit-section` you run, what you
reviewed, and what the buffer showed; the Sidecar under `.revu/reviews/`
is often the most useful attachment.

## Checks

The project builds with [Eldev](https://github.com/emacs-eldev/eldev).
Every change must leave these three clean:

```
eldev test -B
eldev lint
eldev compile
```

How to run them, how to run one test file, and how to open a real Review
in a scratch Emacs are in [`docs/agents/checks.md`](docs/agents/checks.md).

## Standards

The rules a change is reviewed against, from linting as a gate to the
docstring escapes Emacs renders correctly, are in
[`docs/agents/standards.md`](docs/agents/standards.md).

## Design

The vocabulary is in [`CONTEXT.md`](CONTEXT.md); use those words in code,
docstrings and commit messages. Decisions that were hard to reverse are
recorded in [`docs/adr/`](docs/adr/). A change that goes against one of
them should say so and amend the record rather than work around it.
