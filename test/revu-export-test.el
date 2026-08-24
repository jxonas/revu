;;; revu-export-test.el --- Tests for the revdiff Export  -*- lexical-binding: t; -*-

;;; Commentary:

;; Tests for the Export and the agent handoff.  Every test drives the
;; commands in a review buffer over the fixture repository and asserts on
;; what leaves revu: the markdown file on disk, byte for byte against the
;; grammar the revdiff parser pins, and the kill ring the reviewer hands
;; their agent.

;;; Code:

(require 'ert)
(require 'ert-x)
(require 'revu)
(require 'revu-fixture)

(defconst revu-export-test-header-regexp
  "^## \\(.+?\\)\\(?::\\([0-9]+\\)\\(?:-\\([0-9]+\\)\\)?\\)? (\\(file-level\\|\\+\\|-\\| \\))$"
  "The header grammar the revdiff parser accepts, translated to Emacs regexp.
Kept verbatim from `headerRe' in revdiff's `app/annotation/parse.go'.")

(defun revu-export-test--exported (root name)
  "Return the text exported for the Review called NAME under ROOT, or nil."
  (let ((file (expand-file-name (format ".revu/exports/%s.md" name) root)))
    (when (file-exists-p file)
      (with-temp-buffer
        (insert-file-contents file)
        (buffer-string)))))

(defun revu-export-test--should-parse (text)
  "Fail unless every header line of TEXT satisfies the pinned grammar.
Body lines are exempt, so only lines that open a record are checked --
that is every `## ' line the Export writes without escaping it."
  (dolist (line (split-string text "\n"))
    (when (and (string-prefix-p "## " line)
               (not (string-prefix-p "##  " line)))
      (should (string-match-p revu-export-test-header-regexp line)))))

(ert-deftest revu-export-writes-the-four-header-shapes ()
  "A file, a context line, an added line and a removed line each get a header.
The four shapes are the whole of what revdiff's parser accepts for a
single line, and the file-level record sorts first."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree "worktree")
      (revu-fixture-goto-line-matching "^modified   beta\\.txt$")
      (revu-annotate-file "note" "About the whole file")
      (revu-fixture-goto-line-matching "^ beta one$")
      (revu-annotate-line "note" "On the context line")
      (revu-fixture-goto-line-matching "^\\+beta two staged$")
      (revu-annotate-line "note" "On the added line")
      (revu-fixture-goto-line-matching "^-beta two$")
      (revu-annotate-line "note" "On the removed line")
      (revu-export))
    (let ((text (revu-export-test--exported root "worktree")))
      (should (equal text
                     (concat "## beta.txt (file-level)\nAbout the whole file\n"
                             "\n"
                             "## beta.txt:1 ( )\nOn the context line\n"
                             "\n"
                             "## beta.txt:2 (+)\nOn the added line\n"
                             "\n"
                             "## beta.txt:2 (-)\nOn the removed line\n")))
      (revu-export-test--should-parse text))))

(ert-deftest revu-export-does-not-depend-on-the-line-number-prefix ()
  "The same Annotation exports the same way whether or not numbers are drawn.
`revu-line-numbers\' governs a prefix and nothing else: the line the
Annotation names comes from the `revu-target\' the line carries, which is
there either way."
  (revu-fixture-in-repo root
    (pcase-dolist (`(,name ,numbers ,line)
                   `(("off" nil "^\\+beta two staged$")
                     ("on" t "^ +2 \\+beta two staged$")))
      (let ((revu-line-numbers numbers))
        (with-current-buffer (revu-diff-worktree name)
          (revu-fixture-goto-line-matching line)
          (revu-annotate-line "note" "On the added line")
          (revu-export))))
    (should (equal (revu-export-test--exported root "off")
                   (revu-export-test--exported root "on")))
    (should (equal (revu-export-test--exported root "off")
                   "## beta.txt:2 (+)\nOn the added line\n"))))

(ert-deftest revu-export-writes-a-mixed-hunk-over-its-added-lines ()
  "A hunk that both removes and adds lines exports over what it added.
revdiff counts a range in one file's numbers and revu has to pick which,
so it picks the lines the reviewer is being asked to accept."
  (revu-fixture-in-repo root
    (revu-fixture-write-file
     root "alpha.txt"
     (replace-regexp-in-string
      "alpha seven" "alpha seven rewritten"
      (replace-regexp-in-string "alpha six" "alpha six rewritten"
                                revu-fixture-alpha-baseline t t)
      t t))
    (with-current-buffer (revu-diff-worktree "worktree")
      (revu-fixture-goto-line-matching "^\\+alpha six rewritten$")
      (revu-annotate-hunk "note" "The whole replacement")
      (revu-export))
    (let ((text (revu-export-test--exported root "worktree")))
      (should (equal text "## alpha.txt:6-7 (+)\nThe whole replacement\n"))
      (revu-export-test--should-parse text))))

(ert-deftest revu-export-writes-an-addition-only-hunk-over-its-added-lines ()
  "A hunk that only adds lines exports as a range over them."
  (revu-fixture-in-repo root
    (revu-fixture-write-file
     root "README.md"
     "# Fixture\n\nUntouched by any diff.\nadded four\nadded five\n")
    (with-current-buffer (revu-diff-worktree "worktree")
      (revu-fixture-goto-line-matching "^\\+added four$")
      (revu-annotate-hunk "note" "Two new lines")
      (revu-export))
    (let ((text (revu-export-test--exported root "worktree")))
      (should (equal text "## README.md:4-5 (+)\nTwo new lines\n"))
      (revu-export-test--should-parse text))))

(ert-deftest revu-export-writes-a-deletion-only-hunk-over-its-removed-lines ()
  "A hunk with nothing added exports over what it removed, in old numbers."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree "worktree")
      (revu-fixture-goto-line-matching "^-gamma one$")
      (revu-annotate-hunk "note" "Why did this go?")
      (revu-export))
    (let ((text (revu-export-test--exported root "worktree")))
      (should (equal text "## gamma.txt:1-2 (-)\nWhy did this go?\n"))
      (revu-export-test--should-parse text))))

(ert-deftest revu-export-degrades-a-one-line-range-to-a-plain-header ()
  "A range that covers one line says so as a single line, not as `N-N'.
That is what revdiff's own writer does, and the parser reads either."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree "worktree")
      (revu-fixture-goto-line-matching "^\\+alpha seven in the worktree$")
      (revu-annotate-hunk "note" "One line changed")
      (revu-export))
    (let ((text (revu-export-test--exported root "worktree")))
      (should (equal text "## alpha.txt:7 (+)\nOne line changed\n"))
      (revu-export-test--should-parse text))))

(ert-deftest revu-export-concatenates-what-revdiff-cannot-tell-apart ()
  "Two Annotations revdiff would key alike leave as one record, both bodies.
revdiff replaces a record with the next one of the same path, line and
change type, so emitting both would lose the first on the way back in.
The merged record keeps the widest range either of them drew."
  (revu-fixture-in-repo root
    (revu-fixture-write-file
     root "README.md"
     "# Fixture\n\nUntouched by any diff.\nadded four\nadded five\n")
    (with-current-buffer (revu-diff-worktree "worktree")
      (revu-fixture-goto-line-matching "^\\+added four$")
      (revu-annotate-hunk "note" "About both new lines")
      (revu-fixture-goto-line-matching "^\\+added four$")
      (revu-annotate-line "note" "And about the first of them")
      (revu-export))
    (let ((text (revu-export-test--exported root "worktree")))
      (should (equal text (concat "## README.md:4-5 (+)\n"
                                  "About both new lines\n"
                                  "\n"
                                  "And about the first of them\n")))
      (revu-export-test--should-parse text))))

(ert-deftest revu-export-keeps-each-kind-readable-through-a-merge ()
  "Merging bodies does not cost the Kind of any of them.
The format has nowhere to put a Kind, so a `question' carries its own
mark, and it has to survive being concatenated with a `note'."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree "worktree")
      (revu-fixture-goto-line-matching "^\\+beta two staged$")
      (revu-annotate-line "note" "Reads fine")
      (revu-fixture-goto-line-matching "^\\+beta two staged$")
      (revu-annotate-line "question" "Is staged the right word")
      (revu-export))
    (let ((text (revu-export-test--exported root "worktree")))
      (should (equal text (concat "## beta.txt:2 (+)\n"
                                  "Reads fine\n"
                                  "\n"
                                  "?? Is staged the right word\n")))
      (revu-export-test--should-parse text))))

(ert-deftest revu-export-keeps-an-orphaned-range-at-its-recorded-lines ()
  "A range whose endpoints were not found again keeps both recorded lines."
  (revu-fixture-in-repo root
    (revu-fixture-write-file
     root "README.md"
     "# Fixture\n\nUntouched by any diff.\nadded four\nadded five\n")
    (with-current-buffer (revu-diff-worktree "worktree")
      (revu-fixture-goto-line-matching "^\\+added four$")
      (revu-annotate-hunk "note" "About the new lines")
      (revu-fixture-write-file root "README.md" "nothing\nof\nit\nis\nleft\n")
      (revu-export))
    (let ((text (revu-export-test--exported root "worktree")))
      (should (equal text "## README.md:4-5 (+)\nAbout the new lines\n"))
      (revu-export-test--should-parse text))))

(ert-deftest revu-export-drops-review-level-annotations-and-says-how-many ()
  "What is said about the Review as a whole has no revdiff record.
It is dropped rather than smuggled in under a path that does not exist,
and the count is said out loud so the reviewer knows what did not go."
  (revu-fixture-in-repo root
    (let (echoed)
      (with-current-buffer (revu-diff-worktree "worktree")
        (revu-annotate-review "note" "The change reads well overall")
        (revu-annotate-review "question" "Is this the right branch?")
        (revu-fixture-goto-line-matching "^\\+beta two staged$")
        (revu-annotate-line "note" "Kept")
        (setq echoed (ert-with-message-capture messages
                       (revu-export)
                       messages)))
      (should (string-match-p "Dropped 2 Annotations on the Review itself"
                              echoed))
      (let ((text (revu-export-test--exported root "worktree")))
        (should (equal text "## beta.txt:2 (+)\nKept\n"))
        (should-not (string-match-p "reads well" text))))))

(ert-deftest revu-export-writes-no-file-for-a-review-revdiff-cannot-carry ()
  "An empty Export is no file at all, not a blank one.
Every revdiff plugin reads empty as a review with nothing to say, and a
Review holding nothing but Annotations on itself is exactly that."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree "worktree")
      (should-not (revu-export))
      (revu-annotate-review "note" "Nothing revdiff can carry")
      (should-not (revu-export)))
    (should-not (revu-export-test--exported root "worktree"))))

(ert-deftest revu-export-says-what-it-dropped-in-the-message-that-stays ()
  "The drop count reaches the reviewer, not just the *Messages* log.
A second `message' in the same command wipes the first from the echo
area, so a count echoed before the handoff is a count nobody reads.  It
travels with the handoff instead -- and not onto the kill ring, which
carries the path and the contract and nothing else."
  (revu-fixture-in-repo root
    (let (echoed)
      (with-current-buffer (revu-diff-worktree "worktree")
        (revu-annotate-review "note" "Says nothing about a file")
        (revu-fixture-goto-line-matching "^\\+beta two staged$")
        (revu-annotate-line "note" "Kept")
        (setq echoed (ert-with-message-capture messages
                       (revu-export)
                       messages)))
      ;; The message the reviewer is left looking at is the last one.
      (let ((last (car (last (split-string (string-trim-right echoed) "\n\n\n"
                                           t)))))
        (should (string-match-p "Dropped 1 Annotation on the Review itself"
                                last))
        (should (string-match-p "worktree\\.md" last)))
      (should-not (string-match-p "Dropped" (current-kill 0))))))

(ert-deftest revu-export-takes-back-an-export-the-review-no-longer-earns ()
  "Withdrawing the last exportable Annotation takes the Export with it.
An empty Export is no file at all, so a file left over from a fuller
Review is feedback the reviewer has withdrawn -- and an agent handed that
path would act on it."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree "worktree")
      (revu-fixture-goto-line-matching "^\\+beta two staged$")
      (revu-annotate-line "change" "Say this differently")
      (should (revu-export))
      (should (revu-export-test--exported root "worktree"))
      ;; The reviewer thinks better of it and withdraws the feedback.
      (revu-fixture-goto-line-matching "Say this differently")
      (revu-annotate-delete)
      (should-not (revu-export))
      (should-not (revu-export-test--exported root "worktree")))))

(ert-deftest revu-export-escapes-body-lines-that-would-open-a-record ()
  "A body line that reads as a header is pushed one space out of the way.
Only that exact shape moves; a deeper heading, a bare hash and a hash in
the middle of a line are the reviewer's words and go out as written.
Trailing blank lines go, which is what revdiff's editor does to them."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree "worktree")
      (revu-fixture-goto-line-matching "^\\+beta two staged$")
      (revu-annotate-line
       "note"
       "## looks like a header\n  ## indented\n### deeper\n##foo\nword ## mid\n\n")
      (revu-export))
    (let ((text (revu-export-test--exported root "worktree")))
      (should (equal text (concat "## beta.txt:2 (+)\n"
                                  " ## looks like a header\n"
                                  "   ## indented\n"
                                  "### deeper\n"
                                  "##foo\n"
                                  "word ## mid\n")))
      (revu-export-test--should-parse text))))

(ert-deftest revu-export-makes-a-question-readable-as-one ()
  "The format carries no Kind, so a `question' says so in its own body.
The `??' revdiff's plugins classify on is written in, unless the
reviewer's words already carry it or open with a word that asks."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree "worktree")
      (revu-fixture-goto-line-matching "^modified   beta\\.txt$")
      (revu-annotate-file "note" "plain")
      (revu-fixture-goto-line-matching "^ beta one$")
      (revu-annotate-line "question" "Why is this here?")
      (revu-fixture-goto-line-matching "^\\+beta two staged$")
      (revu-annotate-line "question" "What is this for?")
      (revu-fixture-goto-line-matching "^-beta two$")
      (revu-annotate-line "question" "really??")
      (revu-export))
    (let ((text (revu-export-test--exported root "worktree")))
      (should (equal text
                     (concat "## beta.txt (file-level)\nplain\n"
                             "\n"
                             "## beta.txt:1 ( )\n?? Why is this here?\n"
                             "\n"
                             "## beta.txt:2 (+)\nWhat is this for?\n"
                             "\n"
                             "## beta.txt:2 (-)\nreally??\n")))
      (revu-export-test--should-parse text))))

(ert-deftest revu-export-writes-the-path-a-file-has-today ()
  "A file renamed since the Annotation was written exports under its new name.
The Sidecar keeps the path the Target was recorded under; the agent
reading the Export has only today's files to act on."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree "worktree")
      (revu-fixture-goto-line-matching "^\\+beta two staged$")
      (revu-annotate-line "note" "Still the same line")
      (revu-fixture-git-output root "mv" "beta.txt" "beta-renamed.txt")
      (revu-export))
    (let ((text (revu-export-test--exported root "worktree")))
      (should (equal text "## beta-renamed.txt:2 (+)\nStill the same line\n"))
      (revu-export-test--should-parse text))))

(ert-deftest revu-export-writes-the-line-an-anchor-was-re-found-on ()
  "A line that moved exports where it is now, not where it was recorded."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree "worktree")
      (revu-fixture-goto-line-matching "^\\+alpha seven in the worktree$")
      (revu-annotate-line "note" "About seven")
      (revu-fixture-write-file
       root "alpha.txt"
       (concat "a new first line\na new second line\n"
               (revu-fixture-file-contents root "alpha.txt")))
      (revu-export))
    (let ((text (revu-export-test--exported root "worktree")))
      (should (equal text "## alpha.txt:9 (+)\nAbout seven\n"))
      (revu-export-test--should-parse text))))

(ert-deftest revu-export-keeps-an-orphan-at-the-line-it-was-recorded-on ()
  "An Anchor that was not found again is exported, not lost.
The body still says what the reviewer meant, and revdiff never checks
that the line is there."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree "worktree")
      (revu-fixture-goto-line-matching "^\\+alpha seven in the worktree$")
      (revu-annotate-line "note" "About seven")
      (revu-fixture-write-file root "alpha.txt"
                               "nothing\nof\nthe\nold\nfile\nis\nleft\n")
      (revu-export))
    (let ((text (revu-export-test--exported root "worktree")))
      (should (equal text "## alpha.txt:7 (+)\nAbout seven\n"))
      (revu-export-test--should-parse text))))

(ert-deftest revu-export-orders-paths-by-their-bytes ()
  "Files come out in the order revdiff sorts them, which is bytewise."
  (revu-fixture-in-repo root
    (revu-fixture-write-file
     root "README.md"
     "# Fixture\n\nUntouched by any diff.\nadded four\n")
    (with-current-buffer (revu-diff-worktree "worktree")
      (revu-fixture-goto-line-matching "^-gamma one$")
      (revu-annotate-line "note" "On gamma")
      (revu-fixture-goto-line-matching "^\\+alpha seven in the worktree$")
      (revu-annotate-line "note" "On alpha")
      (revu-fixture-goto-line-matching "^\\+added four$")
      (revu-annotate-line "note" "On README")
      (revu-export))
    (let ((text (revu-export-test--exported root "worktree")))
      (should (equal text (concat "## README.md:4 (+)\nOn README\n"
                                  "\n"
                                  "## alpha.txt:7 (+)\nOn alpha\n"
                                  "\n"
                                  "## gamma.txt:1 (-)\nOn gamma\n")))
      (revu-export-test--should-parse text))))

(ert-deftest revu-export-ignores-what-the-reviewer-has-marked-reviewed ()
  "A Reviewed mark is the reviewer's own bookkeeping and never leaves revu."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree "worktree")
      (revu-fixture-goto-line-matching "^\\+beta two staged$")
      (revu-annotate-line "note" "Read and understood")
      (revu-fixture-goto-line-matching "^@@ -1,3 \\+1,3 @@")
      (revu-reviewed-toggle)
      (revu-export))
    ;; The mark did land -- this is not a test that passes by doing nothing.
    (should (> (length (revu-review-marks (revu-fixture-sidecar root "worktree")))
               0))
    (should (equal (revu-export-test--exported root "worktree")
                   "## beta.txt:2 (+)\nRead and understood\n"))))

(ert-deftest revu-export-writes-where-it-is-told-to ()
  "A destination other than the one beside the Sidecar is written instead."
  (revu-fixture-in-repo root
    (let ((elsewhere (expand-file-name "handoff.md" root)))
      (with-current-buffer (revu-diff-worktree "worktree")
        (revu-fixture-goto-line-matching "^\\+beta two staged$")
        (revu-annotate-line "note" "Somewhere else")
        (should (equal (revu-export elsewhere) elsewhere)))
      (should-not (revu-export-test--exported root "worktree"))
      (with-temp-buffer
        (insert-file-contents elsewhere)
        (should (equal (buffer-string)
                       "## beta.txt:2 (+)\nSomewhere else\n"))))))

(ert-deftest revu-export-hands-the-agent-the-file-and-the-contract ()
  "The Export puts its absolute path and the agent contract on the kill ring.
The path alone is what breaks a Sidecar: an agent that was never told
the rules invents its own."
  (revu-fixture-in-repo root
    (let (echoed)
      (with-current-buffer (revu-diff-worktree "worktree")
        (revu-fixture-goto-line-matching "^\\+beta two staged$")
        (revu-annotate-line "note" "Something to hand over")
        (setq echoed (ert-with-message-capture messages
                       (revu-export)
                       messages)))
      (let ((handoff (current-kill 0))
            (file (expand-file-name ".revu/exports/worktree.md" root)))
        (should (string-prefix-p file handoff))
        (should (file-name-absolute-p file))
        (should (string-suffix-p revu-export-agent-contract handoff))
        (should (string-match-p "reply" handoff))
        (should (string-match-p "ULID" handoff))
        (should (string-match-p (regexp-quote file) echoed))))))

(ert-deftest revu-sidecar-path-hands-the-agent-the-sidecar-and-the-contract ()
  "The Sidecar is handed over the same way, path and contract together."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree "worktree")
      (revu-sidecar-path))
    (should (equal (current-kill 0)
                   (concat (expand-file-name ".revu/reviews/worktree.json" root)
                           "\n\n" revu-export-agent-contract)))))

;;;; The kill-ring sink

(ert-deftest revu-export-kill-copies-the-body-and-writes-nothing ()
  "`revu-export-kill' puts the markdown itself on the kill ring, and no file.
It is the sink for the pull request or the chat, so what lands there is
what `revu-export' would have written -- and nothing is written."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree "worktree")
      (revu-fixture-goto-line-matching "^\\+beta two staged$")
      (revu-annotate-line "note" "Copied, not filed")
      (let ((kill-ring nil) (kill-ring-yank-pointer nil))
        (should (equal (revu-export-kill) (current-kill 0)))
        (should (equal (current-kill 0)
                       "## beta.txt:2 (+)\nCopied, not filed\n"))))
    (should-not (revu-export-test--exported root "worktree"))
    (should-not (file-exists-p (expand-file-name ".revu/exports" root)))))

(ert-deftest revu-export-kill-renders-what-the-file-export-renders ()
  "One rendering, two sinks: the copy and the file cannot drift apart."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree "worktree")
      (revu-fixture-goto-line-matching "^modified   beta\\.txt$")
      (revu-annotate-file "question" "Why here?")
      (revu-fixture-goto-line-matching "^\\+alpha seven in the worktree$")
      (revu-annotate-line "change" "Rename this")
      (let ((kill-ring nil) (kill-ring-yank-pointer nil))
        (revu-export-kill)
        (revu-export)
        (should (equal (revu-export-test--exported root "worktree")
                       (current-kill 1)))))))

(ert-deftest revu-export-kill-copies-nothing-from-a-review-with-nothing-to-say ()
  "An empty rendering leaves the kill ring alone rather than blanking it."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree "worktree")
      (let ((kill-ring (list "what the reviewer had before"))
            (kill-ring-yank-pointer nil))
        (should-not (revu-export-kill))
        (should (equal (current-kill 0) "what the reviewer had before"))))))

(ert-deftest revu-export-kill-says-what-it-dropped ()
  "An Annotation on the Review has no record here either, and is counted out."
  (revu-fixture-in-repo root
    (with-current-buffer (revu-diff-worktree "worktree")
      (revu-annotate-review "note" "About the whole thing")
      (revu-fixture-goto-line-matching "^\\+beta two staged$")
      (revu-annotate-line "note" "About a line")
      (let ((kill-ring nil) (kill-ring-yank-pointer nil))
        (let ((echoed (ert-with-message-capture messages
                        (revu-export-kill)
                        messages)))
          (should (string-match-p "Dropped 1 Annotation" echoed))
          (should (string-match-p "kill ring" echoed)))
        (should (equal (current-kill 0)
                       "## beta.txt:2 (+)\nAbout a line\n"))))))

(provide 'revu-export-test)
;;; revu-export-test.el ends here
