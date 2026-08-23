# revdiff annotation export format

What an Emacs exporter must reproduce to be byte-compatible with the markdown
that revdiff writes on quit (`-o` / stdout) and reads back with `--annotations`.

Source: https://github.com/umputun/revdiff at commit
`052619343a6ccdeeff3319a52142b48b1f99f339` (master, 2026-08-20). Every file
path below is relative to that checkout. Code is quoted verbatim.

Ticket: dcr-01m0nekbb7zp.

## 1. Data model

`app/annotation/store.go`:

```go
// Annotation represents a user comment on a specific diff line.
type Annotation struct {
	File    string // file path relative to repo root
	Line    int    // line number in the diff
	EndLine int    // end line of hunk range, 0 means no range
	Type    string // change type: "+", "-", or " "
	Comment string // user comment text
}
```

Identity of a record is `(File, Line, Type)`. `Store.Add` replaces an existing
record with the same key (comment and `EndLine` both overwritten), so
duplicates in a file resolve last-write-wins. File-level records have
`Line == 0` and `Type == ""`.

Change type values come from `app/diff/diff.go`:

```go
	ChangeAdd     ChangeType = "+"
	ChangeRemove  ChangeType = "-"
	ChangeContext ChangeType = " "
	ChangeDivider ChangeType = "~" // marks a skipped unchanged region (leading, between-hunk, or trailing)
```

Divider rows cannot be annotated; only `+`, `-`, and the literal space appear
in the file.

## 2. Line numbers

`Line` is a file line number, not an offset into the diff. Removals are
numbered in the old file, everything else in the new file.
`app/ui/annotate.go`:

```go
// diffLineNum returns the display line number for a diff line.
func (m Model) diffLineNum(dl diff.DiffLine) int {
	if dl.ChangeType == diff.ChangeRemove {
		return dl.OldNum
	}
	return dl.NewNum
}
```

The import side mirrors this exactly (`app/annotations_load.go`,
`buildLineSet`):

```go
// buildLineSet maps each renderable diff line to its (line-number, change-type)
// key. Mirrors Model.diffLineNum: removals key on OldNum, all other change
// types key on NewNum.
```

So for a hunk `@@ -10,3 +12,4 @@`, a `-` on the first hunk row is
`path:10 (-)`, a `+` on the same visual row is `path:12 (+)`, and a context
row is keyed by its new-file number.

## 3. Serialisation (`Store.FormatOutput`)

`app/annotation/store.go`:

```go
func (s *Store) FormatOutput() string {
	if len(s.annotations) == 0 {
		return ""
	}

	files := s.Files()

	var buf strings.Builder
	first := true
	for _, file := range files {
		anns := s.Get(file) // sorted by line: file-level (0) first, then ascending
		for _, a := range anns {
			if !first {
				buf.WriteString("\n")
			}
			first = false
			body := s.escapeHeaderLines(a.Comment)
			switch {
			case a.Line == 0:
				fmt.Fprintf(&buf, "## %s (file-level)\n%s\n", a.File, body)
			case a.EndLine > 0:
				fmt.Fprintf(&buf, "## %s:%d-%d (%s)\n%s\n", a.File, a.Line, a.EndLine, a.Type, body)
			default:
				fmt.Fprintf(&buf, "## %s:%d (%s)\n%s\n", a.File, a.Line, a.Type, body)
			}
		}
	}
	return buf.String()
}
```

Byte-level rules that follow from this:

- **Empty store → empty string.** No trailing newline, nothing. With `-o` the
  file is not written at all when there are no annotations (see §7), and
  `TestStore_WriteFileEmptyStore` shows a direct `WriteFile` produces an empty
  file.
- **Record shape:** header line, `\n`, body, `\n`. The body is the comment
  verbatim (after escaping, §4); embedded `\n` in the comment flow through.
- **Separator:** exactly one blank line (`\n`) between records, none before the
  first, none after the last. The file therefore ends with a single `\n`.
- **Header shapes (4):**
  - `## <path> (file-level)` — `Line == 0`; `EndLine` is ignored
    (`TestStore_FormatOutputFileLevelIgnoresEndLine`).
  - `## <path>:<N> (+)`, `## <path>:<N> (-)`, `## <path>:<N> ( )` — single line.
    Note the space type renders as `( )` with a literal space.
  - `## <path>:<N>-<M> (<T>)` — range, emitted only when `EndLine > 0`.
- **Sort order:** files by `sort.Strings` (bytewise on the path), then records
  within a file by `Line` ascending, so the file-level record (`Line 0`)
  comes first. The in-file sort is `sort.Slice` on `Line` only; when a `+` and
  a `-` share the same number their relative order is unspecified (in
  practice insertion order for short lists). An exporter cannot rely on a
  byte-identical tie order here; both orders parse identically.

Worked example from `app/annotation/store_test.go`
(`TestStore_FormatOutputMixedFileLevelAndLineMultiFile`):

```go
	expected := "## a_file.go (file-level)\nfile-level note for a\n" +
		"\n" +
		"## a_file.go:10 (+)\nline note for a\n" +
		"\n" +
		"## b_file.go (file-level)\nfile-level note for b\n" +
		"\n" +
		"## b_file.go:5 (-)\nline note for b\n"
```

and `TestStore_FormatOutputMixedSingleAndMultiLine`:

```go
	expected := "## handler.go:10 (+)\none-liner\n" +
		"\n" +
		"## handler.go:20 (-)\nmulti\nline\ncomment\n" +
		"\n" +
		"## handler.go:30 ( )\nanother one-liner\n"
```

## 4. Body escaping and un-escaping

Writer (`app/annotation/store.go`):

```go
// escapeHeaderLines prefixes any body line whose first non-space content is
// "## " with a single extra space. The parser inverts this by stripping one
// leading space from any body line that, after left-trimming, begins with
// "## ". Escaping pre-indented variants (e.g. " ## ") keeps the round-trip
// symmetric for arbitrary user content. Other heading forms like "### " are
// not escaped since they cannot collide with the record-header split marker.
func (s *Store) escapeHeaderLines(body string) string {
	if !strings.Contains(body, "## ") {
		return body
	}
	lines := strings.Split(body, "\n")
	for i, line := range lines {
		if strings.HasPrefix(strings.TrimLeft(line, " "), "## ") {
			lines[i] = " " + line
		}
	}
	return strings.Join(lines, "\n")
}
```

Reader (`app/annotation/parse.go`):

```go
// appendBody adds a body line, stripping the inverse of escapeHeaderLines:
// exactly one leading space when the line's first non-space content begins
// with "## ".
func (p *parser) appendBody(line string) {
	if strings.HasPrefix(line, " ") && strings.HasPrefix(strings.TrimLeft(line, " "), "## ") {
		line = line[1:]
	}
	p.body = append(p.body, line)
}
```

Rules:

- Only the exact prefix `## ` (two hashes then a space) triggers escaping, and
  only when it is the first non-space content of the line. `##foo`, `### x`,
  `# x`, and `word ## mid` pass through untouched
  (`TestStore_FormatOutputDoesNotEscapeNonHeaderHash`,
  `TestStore_FormatOutputDoesNotEscapeDeeperMarkdownHeaders`).
- Leading spaces only; tabs are not trimmed by `TrimLeft(line, " ")`, so a
  body line `\t## x` is neither escaped nor un-escaped.
- Escaping is one space added regardless of existing indent, and parsing
  strips exactly one, so `"  ## two spaces"` round-trips
  (`TestParse_RoundTripPreservesIndentedHashHeader`).
- The escaping is applied to the first body line too
  (`TestStore_FormatOutputEscapesHeaderLinesAtStart`).

## 5. Header grammar (`Parse`)

`app/annotation/parse.go`:

```go
// headerRe matches the four record-header shapes emitted by Store.FormatOutput:
//
//	## path (file-level)
//	## path:N (T)
//	## path:N-M (T)
//
// where T is one of "+", "-", or " " (literal space).
var headerRe = regexp.MustCompile(`^## (.+?)(?::(\d+)(?:-(\d+))?)? \((file-level|\+|-| )\)$`)
```

Consequences for an exporter:

- The path group is lazy and may contain any characters including spaces,
  colons, and parentheses; the header is anchored on the final ` (T)` and `$`.
  A path that itself ends in `:N` or `:N-M` is handled specially only for the
  file-level form (`parseHeader` re-attaches the numeric tail,
  `TestParse_FileLevelPathWithColonNumberSuffix`). For line-level records such
  a path is ambiguous; avoid it.
- `N` and `M` are unsigned decimals (`\d+`). `M` is accepted for every type,
  including `( )`, and is stored as `EndLine`.
- Any `## `-prefixed line that does not match the regex is an error **before**
  the first header and body text **after** one:

```go
		if strings.HasPrefix(line, "## ") {
			ann, err := p.parseHeader(line)
			if err != nil {
				// non-grammar "## " line inside a record: treat as body content
				// (post-strip of any leading-space escape) so authored bodies
				// can mention "## foo" without escaping. Before the first
				// header, propagate the error.
				if !p.seenHeader {
					return nil, err
				}
				p.appendBody(line)
				continue
			}
```

- Non-blank content before the first header is an error
  (`"annotation input has content before any header"`); blank lines before it
  are skipped. `TestParse_MalformedHeader` lists rejected headers:
  `## not a real header`, `## file.go:abc (+)`, `## file.go:10 (?)`,
  `## file.go:10`.
- Line ends: `bufio.Scanner` with `ScanLines` strips an optional `\r` before
  `\n`, so CRLF input parses, but the writer always emits bare `\n`.
- Scanner buffer is 4 MiB per line (`p.scanner.Buffer(make([]byte, 64*1024), 4*1024*1024)`).
- Body termination (`flush`): strip exactly one trailing empty body line, which
  is the record separator:

```go
	// FormatOutput always emits a trailing newline after the body. Strip
	// exactly one trailing empty line that came from the format separator.
	if n := len(p.body); n > 0 && p.body[n-1] == "" {
		p.body = p.body[:n-1]
	}
	p.current.Comment = strings.Join(p.body, "\n")
```

  Edge: a comment that itself ends in `\n` survives when it is not the last
  record (two empty lines, one stripped) but loses its trailing newline when it
  is the last record. The TUI never produces such comments (the external
  editor path does `strings.TrimRight(string(data), "\n")` in
  `app/editor/editor.go`), so an exporter should trim trailing newlines from
  comments for parity.
- `Parse` returns records in source order including duplicates;
  `Store.Load` feeds them through `Add` (last-write-wins,
  `TestParse_DuplicateLastWriteWins`).

## 6. The `hunk` keyword and ranges

Ranges are never typed by the user. When a line-level comment contains the
whole word `hunk` (case-insensitive) the TUI expands `EndLine` at save time.
`app/ui/annotate.go`:

```go
// hunkKeywordRe matches whole-word "hunk" (case-insensitive).
// "block" was removed as it triggers false positives in casual usage (e.g., "this code block is fine").
var hunkKeywordRe = regexp.MustCompile(`(?i)\bhunk\b`)
```

```go
	a := annotation.Annotation{File: fileName, Line: line, Type: changeType, Comment: text}
	if hunkKeywordRe.MatchString(text) && fileName == m.file.name {
		// re-derive the diff-line index from (line, changeType) so hunk-end
		// detection survives cursor drift during an external editor session.
		// only scan when the captured file still matches the loaded one —
		// otherwise m.file.lines describes a different file and would mislead.
		for i, dl := range m.file.lines {
			if string(dl.ChangeType) != changeType {
				continue
			}
			if m.diffLineNum(dl) != line {
				continue
			}
			if endLine := m.hunkEndLine(i); endLine > line {
				a.EndLine = endLine
			}
			break
		}
	}
```

```go
// hunkEndLine returns the display line number of the last line in the change hunk
// containing diffLines[idx]. only walks forward through lines of the same change type
// as the starting line, so both start and end use the same number space (old or new).
// returns 0 if idx is not inside a change hunk.
func (m Model) hunkEndLine(idx int) int {
	if idx < 0 || idx >= len(m.file.lines) {
		return 0
	}
	dl := m.file.lines[idx]
	if dl.ChangeType != diff.ChangeAdd && dl.ChangeType != diff.ChangeRemove {
		return 0
	}

	// walk forward from idx to find the last contiguous line of the same change type
	startType := dl.ChangeType
	last := idx
	for i := idx + 1; i < len(m.file.lines); i++ {
		if m.file.lines[i].ChangeType != startType {
			break
		}
		last = i
	}
	return m.diffLineNum(m.file.lines[last])
}
```

Rules to reproduce:

- Only `+` and `-` lines get a range; context lines never do, and the
  keyword on a file-level comment does nothing.
- The range runs **forward only** from the annotated line to the last
  contiguous line of the **same change type**; it does not extend backward,
  and does not cross into the other side of a replacement hunk.
- `M` is in the same number space as `N` (old for `-`, new for `+`).
- Emitted only when `M > N`; a one-line hunk stays `path:N (+)`.
- The keyword is not removed from the comment text.

The parser and `--annotations` accept `N-M` for any type and preserve
`EndLine` through `Store.Add`; the preload check keys on `(Line, Type)` only
and ignores `EndLine`. An Emacs exporter that derives ranges from a region
rather than the keyword is therefore still importable, but not byte-identical
to what the TUI would have produced.

## 7. Where the output goes

`app/main.go`:

```go
func writeAnnotationOutput(r annotationOutputReq) (int, error) {
	code := annotationExitCode(r.opts.ExitCodeOnAnnotations, r.output)
	if r.opts.Output != "" {
		if err := fsutil.AtomicWriteFile(r.opts.Output, []byte(r.output)); err != nil {
			return 0, fmt.Errorf("write output: %w", err)
		}
		return code, nil
	}
	if _, err := fmt.Fprint(r.stdout, r.output); err != nil {
		return 0, fmt.Errorf("write output: %w", err)
	}
	return code, nil
}
```

`finalize` returns early without writing anything when the review was
discarded or `FormatOutput()` is empty; a signal-driven exit saves history
only and never the `-o` file. `Store.WriteFile` (used by the `O` mid-session
flush) writes atomically via temp file + rename with mode `0o600`. Exit code
is `10` only when `--exit-code-on-annotations` /
`REVDIFF_EXIT_CODE_ON_ANNOTATIONS=true` is set and output is non-empty;
otherwise `0`.

## 8. Path relativity

- Git/hg/jj renderers report `FileEntry.Path` as "file path relative to repo
  root" (`app/diff/diff.go`), and revdiff runs VCS commands with
  `cmd.Dir = workDir` where `workDir` is the repo root
  (`app/renderer_setup.go`, `makeGitRenderer` returns `repoRoot`). So
  annotation keys are repo-root-relative, forward-slash paths, never
  prefixed with `./`, regardless of the cwd revdiff was launched from.
- `--only` files that are in the diff keep their repo-relative path. `--only`
  files not in the diff are keyed by the **pattern as given** on the command
  line (`app/diff/fallback.go`: `entries = append(entries, FileEntry{Path: pattern})`),
  resolved against the repo root for existence. Outside any VCS,
  `FileReader.ChangedFiles` keys by `resolvePath(workDir, f)`, i.e. the
  absolute path for absolute input, or `cwd/f` for relative input.
- `--stdin` diffs are keyed by the paths inside the patch (skill text:
  "Annotations come back keyed by the real file paths from the diff (not by
  `--stdin-name`)").
- Renames are a known limitation (`app/annotations_load.go`): "Files renamed
  since the annotations file was generated are keyed under their old path and
  will orphan-drop here — a known limitation of the path-based format."

## 9. `--annotations` import and orphans

`app/annotations_load.go`, `preloadAnnotations` doc comment:

```go
// preloadAnnotations parses the markdown file at path (same format as
// Store.FormatOutput) and feeds each record through store.Add after dropping
// orphans against the resolved diff. file-level records (Line == 0) require
// only that the file be present in ChangedFiles. Line-scoped records require
// both the file and a matching DiffLine (same line number for the record's
// change type) to be present. Untracked files (surfaced in the UI via the
// show-untracked toggle) are folded in via untrackedFn so annotations saved
// against them round-trip; their line-set is read from disk as all-added
// lines, mirroring ui.resolveEmptyDiff. Dropped records are warned to warnOut.
```

The loop:

```go
	for _, a := range records {
		// Sanitize the comment text before it reaches Store.Add: the
		// preload source is user- or LLM-supplied and may carry stray
		// ANSI / CR-overwrite / C1 bytes that Renderer.AnnotationInline
		// wraps into the TUI verbatim. Mirrors diff.SanitizeCommitText
		// usage on commit Author/Subject/Body.
		a.Comment = diff.SanitizeCommitText(a.Comment)

		status, ok := known[a.File]
		if !ok {
			p.warnf("warning: --annotations: file %q not in diff, dropping annotation\n", a.File)
			continue
		}
		if a.Line == 0 {
			p.store.Add(a)
			continue
		}
		lines := p.lookupLineSet(a.File, status)
		if _, ok := lines[lineKey{line: a.Line, kind: a.Type}]; !ok {
			p.warnf("warning: --annotations: %s:%d (%s) not in diff, dropping\n", a.File, a.Line, a.Type)
			continue
		}
		p.store.Add(a)
	}
```

Summary:

- Orphans are **dropped with a warning on stderr**, never an error. The
  warning strings are `warning: --annotations: file "X" not in diff, dropping
  annotation` and `warning: --annotations: X:N (T) not in diff, dropping`
  (see `TestPreloadAnnotations_DropsOrphans`).
- A line record must match both line number **and** type against the diff the
  session is actually showing, so `path:5 (+)` on a context line, or
  `path:5 ( )` on an added line, is dropped.
- File-level records need only the file to be in the visible set (changed
  files, plus untracked files always, plus staged-only added files in
  working-tree mode).
- Untracked files are validated as all-added lines read from disk.
- Comment text is passed through `SanitizeCommitText` (strips ANSI CSI
  sequences, C1/unsafe runes, invalid UTF-8 bytes).
- Hard errors (exit 1): missing file, non-regular file, size over 1 MiB
  (`maxAnnotationsFileSize = 1 << 20`), parse error (`parse annotations: ...`),
  or failure to resolve the diff. `--annotations` is mutually exclusive with
  `--stdin` and with `--compare-old/--compare-new`.
- Duplicates apply last-write-wins after orphan filtering
  (`TestPreloadAnnotations_DuplicateLastWriteWins`).

## 10. What the plugins do with the file

### Claude Code (`.claude-plugin/skills/revdiff/scripts/launch-revdiff.sh`)

```bash
TMPBASE="${TMPDIR:-/tmp}"
OUTPUT_FILE=$(mktemp "$TMPBASE/revdiff-output-XXXXXX")
ERR_FILE=$(mktemp "$TMPBASE/revdiff-err-XXXXXX")
trap 'rm -f "$OUTPUT_FILE" "$ERR_FILE"' EXIT
```

```bash
REVDIFF_CMD="REVDIFF_EXIT_CODE_ON_ANNOTATIONS=true $REVDIFF_CMD $(sq "--output=$OUTPUT_FILE")"
```

```bash
print_output_and_exit() {
    local rc="${1:-0}"
    # 0 is a clean quit and 10 means annotations were captured; both are
    # successes, and revdiff writes ordinary warnings to stderr, so relaying
    # them would put noise on every successful review
    if [ "$rc" -ne 0 ] && [ "$rc" -ne 10 ] && [ -s "$ERR_FILE" ]; then
        cat "$ERR_FILE" >&2
    fi
    cat "$OUTPUT_FILE"
    exit "$rc"
}
```

The launcher `cat`s the file to stdout verbatim, exits with revdiff's code,
and the `EXIT` trap deletes it. The skill (`SKILL.md`, Step 3) reads the
stdout text; its timeout fallback instead reads the newest
`${TMPDIR:-/tmp}/revdiff-output-*` file with `ls -t ... | head -1` and
`cat`s it, then falls back to `read-latest-history.sh`. The Codex skill
(`plugins/codex/skills/revdiff/SKILL.md`) and its launcher are the same flow;
OpenCode's `setup.sh` copies the Claude launcher to
`~/.config/opencode/tools/launch-revdiff.sh` and `plugins/opencode/tools/revdiff.ts`
returns `stdout.trim()` or the string `"(no annotations)"`.

An Emacs tool that wants the Claude/Codex timeout fallback to pick up its
export should write it to `${TMPDIR:-/tmp}/revdiff-output-<suffix>`; any
other path is invisible to that fallback.

### pi (`plugins/pi/extensions/revdiff.ts`)

```ts
		const tempDir = mkdtempSync(path.join(tmpdir(), "revdiff-pi-"));
		const outputFile = path.join(tempDir, "annotations.txt");
		const commandArgs = [...launch.args, `--output=${outputFile}`];
```

```ts
		const outputExists = existsSync(outputFile);
		const rawOutput = outputExists ? readFileSync(outputFile, "utf8").trim() : "";
		try {
			rmSync(tempDir, { recursive: true, force: true });
		} catch {
			// ignore temp cleanup failures
		}
```

pi parses the text with its own regex and also hands `rawOutput.trim()` to
the agent verbatim:

```ts
const ANNOTATION_HEADER_RE = /^## (.+?)(?::(\d+)(?:-\d+)?)? \(([^)]+)\)$/;
```

Differences from the Go parser (all looser, not stricter): any type token
inside the parentheses is accepted; the range end is discarded; the header is
matched after `trimEnd()`; non-matching `## ` lines are body even before the
first header; the leading-space escape is **not** stripped (body is
`bodyLines.join("\n").trim()`), so an escaped ` ## x` line reaches the pi
agent with its extra space.

### Planning hook (`plugins/revdiff-planning/scripts/plan-review-hook.py`)

Reads `result.stdout.strip()` from the plan launcher and embeds it in a
prompt: "user reviewed the plan in revdiff and added annotations. each
annotation references a specific line and contains the user's feedback."

## 11. The `??` / leading-word question convention

This is plugin-side classification only; the format carries no flag.
`.claude-plugin/skills/revdiff/SKILL.md`, Step 3.5 (identical text in the
Codex skill):

```
**Explanation requests** — annotation matches either rule (case-insensitive):
- contains two or more consecutive question marks anywhere in the text (`??`, `???`, etc.) — a language-neutral shortcut for "please explain"
- OR starts with one of: `explain`, `remind`, `describe`, `what is`, `what are`, `how does`, `how do`, `clarify`

These are questions the user wants answered, not code changes.

**Code-change directives** — everything else. These are instructions to modify code.
```

`references/usage.md` gives the user-facing examples:

```
## renderer.go:142 (+)
why a pointer here??

## store.go:88 (-)
explain what this lock protects
```

Claude and Codex answer questions as a markdown file reopened via `--only`
with a TOC; pi classifies "explanation requests" vs "code-change directives"
in prose (`plugins/pi/skills/revdiff/SKILL.md`) and answers in chat. OpenCode's
command (`plugins/opencode/commands/revdiff.md`) has no question rule at all:
"Wait for the annotations, then address each one with code changes."

An Emacs exporter need only preserve the comment text; a `??` anywhere or one
of the opener words at the start of the body triggers the question path.

## 12. Where the plugins are stricter (or narrower) than the format

- **Documented shapes.** The Claude and Codex `SKILL.md` Step 3 text lists
  only `(+)`, `(-)`, and `(file-level)`; it does not mention `( )` context
  records or `N-M` ranges. `references/usage.md` ("Output Format") does
  document `[-end]` and the `hunk` rule but still omits `( )`. Context-line
  annotations are valid output (`TestStore_ContextOnlyAnnotations`, and the
  no-VCS `--only` mode produces nothing else), so an exporter may emit them,
  but the agent prompt never explains the token.
- **In-session preload format.** When a plugin writes a file for
  `--annotations` it is told to use "the format documented in
  `references/usage.md`"; the Go parser is the real contract, and it is
  stricter than the plugin regexes (exact `(file-level|\+|-| )` type set,
  decimal line numbers, error on content before the first header).
- **Whitespace.** pi trims the whole output and each body; Claude/Codex read
  stdout as-is. Neither depends on the blank-line separator, but the Go parser
  does rely on it to strip exactly one trailing empty body line.
- **Empty output.** Every plugin treats empty stdout as "no annotations, review
  complete". An exporter should emit zero bytes, not a blank line, for the
  empty case.
- **Exit codes.** Plugins set `REVDIFF_EXIT_CODE_ON_ANNOTATIONS=true` and treat
  `10` as success; anything else non-zero is a failure and the launcher relays
  stderr. Irrelevant to a file exporter but relevant if Emacs drives the
  launcher.

## 13. Minimal exporter checklist

1. Key records by repo-root-relative path, `(line, type)`; removals use
   old-file numbers, adds and context use new-file numbers.
2. Sort paths bytewise, then records by line with file-level (`0`) first.
3. Emit `## path (file-level)` / `## path:N (T)` / `## path:N-M (T)` with `T`
   in `+`, `-`, or a single space, a `\n`, the body, a `\n`; join records
   with one extra `\n`; no leading or trailing blank lines; zero bytes when
   empty.
4. Trim trailing newlines from each comment; prefix one space to any body line
   whose first non-space content is `## `.
5. Add `-M` only for `+`/`-` records, forward to the end of the contiguous
   same-type run, and only when `M > N`; the TUI does this only when the
   comment matches `(?i)\bhunk\b`.
6. Expect `--annotations` to drop silently (with stderr warnings) any record
   whose file or `(line, type)` is not in the diff revdiff is showing.
