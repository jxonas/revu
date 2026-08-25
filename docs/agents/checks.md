# Checks

How to run this repo's checks, and what each one needs. The rules they enforce are in
`docs/agents/standards.md`.

## The three commands

| Command | What it does |
| --- | --- |
| `eldev test -B` | Runs the suite. `-B` drops the ert backtraces — roughly 30 lines of expanded macro per failure, which bury the `:form` line you actually want. |
| `eldev lint` | Runs all three linters (`doc`, `package`, `re`). Must report `Linters have no complaints`. |
| `eldev compile` | Byte-compiles every file. |

One test file: `eldev test -B -f revu-render-test.el`.

## Opening a Review by hand

The fixture repository is the only way to get a real Review buffer to look at. `Eldev` gives the
`emacs` command the `test` loading root, so a scratch script can require it:

```elisp
;; peek.el
(require 'revu)
(require 'revu-fixture)
(revu-fixture-in-repo root
  (with-current-buffer (revu-diff-worktree nil "worktree")
    (princ (buffer-substring-no-properties (point-min) (point-max)))))
```

```
eldev emacs --batch -l peek.el
```

`revu-fixture-in-repo` builds the repository, binds `root`, and deletes the repository and every
review buffer when the body finishes. An entry command returns its review buffer; `revu-file` does
not, so reach that one through `(revu-buffer-name "name")`.

## What a render costs

`test/revu-render-cost-test.el` renders through `revu-render`, over a Review with a Sidecar and a
Source, because that is the render a reviewer pays for. A test that times `revu-render-diff` on its
own measures a buffer nobody gets: it was written that way once, and a header that cost a fifth of a
second per render went in under it.
