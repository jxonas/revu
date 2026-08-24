;;; revu-magit-test.el --- Tests for the magit Bridge mapping  -*- lexical-binding: t; -*-

;;; Commentary:

;; Tests for what the magit Bridge (ADR-0013) does with the recipe
;; magit's diff commands funnel through.  Magit is not loaded here and
;; is not a test dependency: the mapping is a pure function over the
;; arguments magit would have passed, and this file calls it directly,
;; against the fixture repository where a merge base or a rev-parse has
;; to be real.  The advice and the transient switch are compile-checked
;; only.

;;; Code:

(require 'ert)
(require 'revu)
(require 'revu-fixture)
(require 'revu-magit)

(defun revu-magit-test--commit (root revision)
  "Return the full object id REVISION names in ROOT."
  (revu-fixture-git-output root "rev-parse" (concat revision "^{commit}")))

(defun revu-magit-test--short (root revision)
  "Return the object id REVISION names in ROOT, abbreviated as git does.
That is the length magit's log shows an id at, and so the length the
derived Review name carries."
  (revu-fixture-git-output root "rev-parse" "--short"
                           (concat revision "^{commit}")))

(ert-deftest revu-magit-loads-without-magit ()
  "The Bridge's mapping is reachable with magit absent."
  (should-not (featurep 'magit))
  (should (fboundp 'revu-magit-plan))
  (should (fboundp 'revu-magit-mode)))

;;;; Committed ranges

(ert-deftest revu-magit-passes-a-committed-range-through ()
  "A range magit built is reviewed as magit built it, oldest excluded."
  (revu-fixture-with-repo root
    (let ((default-directory root))
      (should (equal (revu-magit-plan "main..feature" nil nil 'committed)
                     '(revu-diff-range "main" "feature" nil nil))))))

(ert-deftest revu-magit-abbreviates-the-object-ids-a-range-names ()
  "A log selection arrives as full object ids and is named by short ones."
  (revu-fixture-with-repo root
    (let* ((default-directory root)
           (base (revu-magit-test--commit root "main"))
           (head (revu-magit-test--commit root "feature")))
      (should (equal (revu-magit-plan (format "%s..%s" base head)
                                      nil nil 'committed)
                     (list 'revu-diff-range
                           (revu-magit-test--short root "main")
                           (revu-magit-test--short root "feature")
                           nil nil))))))

(ert-deftest revu-magit-resolves-a-three-dot-range-to-its-merge-base ()
  "`A...B' is reviewed from where A and B last diverged, against B."
  (revu-fixture-with-repo root
    (let* ((default-directory root)
           (base (revu-fixture-git-output root "merge-base" "main" "feature")))
      (should (equal (revu-magit-plan "main...feature" nil nil 'committed)
                     (list 'revu-diff-range
                           (revu-fixture-git-output root "rev-parse" "--short"
                                                    base)
                           "feature" nil nil))))))

(ert-deftest revu-magit-fills-in-the-end-of-a-range-magit-left-out ()
  "An omitted end of a range is HEAD, which is the diff git would take."
  (revu-fixture-with-repo root
    (let ((default-directory root))
      (should (equal (revu-magit-plan "..feature" nil nil 'committed)
                     '(revu-diff-range "HEAD" "feature" nil nil)))
      (should (equal (revu-magit-plan "feature.." nil nil 'committed)
                     '(revu-diff-range "feature" "HEAD" nil nil))))))

(ert-deftest revu-magit-reviews-a-commit-as-its-own-changes ()
  "A commit from `d c' is reviewed as `commit^..commit', both ends resolved."
  (revu-fixture-with-repo root
    (let ((default-directory root))
      (should (equal (revu-magit-revision-plan
                      (revu-magit-test--commit root "feature") nil)
                     (list 'revu-diff-range
                           (revu-magit-test--short root "feature^")
                           (revu-magit-test--short root "feature")
                           nil nil)))
      ;; A symbolic name resolves too, so the Review's name does not come
      ;; to mean a different range tomorrow.
      (should (equal (revu-magit-revision-plan "feature" nil)
                     (revu-magit-revision-plan
                      (revu-magit-test--commit root "feature") nil))))))

(ert-deftest revu-magit-refuses-a-root-commit-and-an-unknown-revision ()
  "There is no range with a base to review for either."
  (revu-fixture-with-repo root
    (let ((default-directory root))
      (should (equal (car (revu-magit-revision-plan "main" nil)) 'refuse))
      (should (string-match-p
               "root commit" (cdr (revu-magit-revision-plan "main" nil))))
      (should (equal (car (revu-magit-revision-plan "no-such-thing" nil))
                     'refuse)))))

;;;; The worktree and the index

(ert-deftest revu-magit-reviews-the-staged-source ()
  "`d s' is the staged Source, whatever magit's own base would have been."
  (revu-fixture-with-repo root
    (let ((default-directory root))
      (should (equal (revu-magit-plan nil "--cached" nil 'staged)
                     '(revu-diff-staged nil nil)))
      (should (equal (revu-magit-plan "HEAD" "--cached" nil 'staged)
                     '(revu-diff-staged nil nil)))
      ;; A revision magit read from a prefix argument is compared as the
      ;; commit it names: `main' is HEAD while that branch is checked out.
      (should (equal (revu-magit-plan "main" "--cached" nil 'staged)
                     '(revu-diff-staged nil nil)))
      (should (equal (revu-magit-plan (revu-magit-test--commit root "HEAD")
                                      "--cached" nil 'staged)
                     '(revu-diff-staged nil nil)))
      ;; The index against anything but HEAD is a Source revu has not got.
      (should (equal (car (revu-magit-plan "feature" "--cached" nil 'staged))
                     'refuse))
      (should (equal (car (revu-magit-plan "no-such-thing" "--cached" nil
                                           'staged))
                     'refuse)))))

(ert-deftest revu-magit-widens-unstaged-to-the-worktree ()
  "`d u' has no Source of its own and becomes the worktree, with a word said."
  (revu-fixture-with-repo root
    (let ((default-directory root))
      (should (equal (revu-magit-plan nil nil nil 'unstaged)
                     '(revu-diff-worktree nil nil)))
      (should (seq-find (lambda (note)
                          (string-match-p "worktree" note))
                        (revu-magit--caveats nil 'unstaged))))))

(ert-deftest revu-magit-reviews-a-lone-revision-as-the-worktree ()
  "`d w' diffs the worktree against HEAD, and so does revu."
  (revu-fixture-with-repo root
    (let ((default-directory root))
      (should (equal (revu-magit-plan "HEAD" nil nil 'committed)
                     '(revu-diff-worktree nil nil)))
      (should (equal (revu-magit-plan "main" nil nil 'committed)
                     '(revu-diff-worktree nil nil)))
      ;; The worktree against anything else is not a Source revu has.
      (should (equal (car (revu-magit-plan "feature" nil nil 'committed))
                     'refuse))
      (should (equal (car (revu-magit-plan "no-such-thing" nil nil 'committed))
                     'refuse)))))

;;;; Pathspecs, arguments and refusals

(ert-deftest revu-magit-turns-magits-pathspecs-into-a-narrowing ()
  "The pathspecs magit was limited to are the Narrowing, in the order given."
  (revu-fixture-with-repo root
    (let ((default-directory root)
          (files '("alpha.txt" "docs/")))
      (should (equal (revu-magit-plan "main..feature" nil files 'committed)
                     '(revu-diff-range "main" "feature" nil
                                       ("alpha.txt" "docs/"))))
      (should (equal (revu-magit-plan nil "--cached" files 'staged)
                     '(revu-diff-staged nil ("alpha.txt" "docs/"))))
      (should (equal (revu-magit-plan nil nil files 'unstaged)
                     '(revu-diff-worktree nil ("alpha.txt" "docs/"))))
      (should (equal (revu-magit-revision-plan "feature" files)
                     (list 'revu-diff-range
                           (revu-magit-test--short root "feature^")
                           (revu-magit-test--short root "feature")
                           nil files))))))

(ert-deftest revu-magit-reports-the-diff-arguments-it-drops ()
  "Magit's own defaults pass unremarked; anything the reviewer set is named."
  (should-not (revu-magit--caveats '("--stat" "--no-ext-diff") 'committed))
  (should-not (revu-magit--caveats
               '("--stat" "--no-ext-diff" "--revu") 'committed))
  (let ((notes (revu-magit--caveats '("--stat" "-U7" "--ignore-all-space" "--revu")
                                 'committed)))
    (should (equal (length notes) 1))
    (should (string-match-p "-U7" (car notes)))
    (should (string-match-p "--ignore-all-space" (car notes)))
    (should-not (string-match-p "--revu" (car notes)))
    (should-not (string-match-p "--stat" (car notes))))
  ;; The widening and the dropped arguments are both worth saying.
  (should (equal (length (revu-magit--caveats '("-w") 'unstaged)) 2)))

(ert-deftest revu-magit-reads-the-switch-out-of-magits-arguments ()
  "The switch is revu's and never reaches anything that runs git."
  (should (revu-magit--switch-on-p '("--stat" "--revu")))
  (should-not (revu-magit--switch-on-p '("--stat")))
  (should (equal (revu-magit--strip-switch '("--stat" "--revu" "-w"))
                 '("--stat" "-w"))))

(ert-deftest revu-magit-refuses-a-range-it-cannot-take-two-revisions-from ()
  "A range notation revu cannot decompose is refused, not guessed at."
  (revu-fixture-with-repo root
    (let ((default-directory root))
      (should (equal (car (revu-magit-plan "main^-" nil nil 'committed))
                     'refuse))
      (should (equal (car (revu-magit-plan "main^!" nil nil 'committed))
                     'refuse)))))

(ert-deftest revu-magit-refuses-a-no-index-diff ()
  "`d p' diffs two files on disk, and there are no Revisions in that."
  (revu-fixture-with-repo root
    (let* ((default-directory root)
           (plan (revu-magit-plan nil "--no-index" '("a" "b") 'undefined)))
      (should (equal (car plan) 'refuse))
      (should (string-match-p "--no-index" (cdr plan))))))

(ert-deftest revu-magit-refuses-a-stash ()
  "A stash is not a Source revu has, and the Bridge does not invent one."
  (revu-fixture-with-repo root
    (let ((default-directory root))
      (should-error (revu-magit--stash-setup #'ignore "stash@{0}" '("--revu")
                                             nil)
                    :type 'user-error)
      ;; With the switch off, magit gets its own buffer as it always did.
      (should (equal (revu-magit--stash-setup (lambda (&rest arguments)
                                                arguments)
                                              "stash@{0}" '("--stat") nil)
                     '("stash@{0}" ("--stat") nil))))))

;;;; Carrying a plan out

(ert-deftest revu-magit-refuses-loudly-and-opens-nothing ()
  "A refusal is a `user-error', and no Review is opened behind it."
  (should-error (revu-magit--run '(refuse . "no") nil) :type 'user-error))

(ert-deftest revu-magit-opens-silently-on-the-abbreviated-name ()
  "The Bridge asks nothing: the Review opens under its abbreviated name."
  (revu-fixture-in-repo root
    (cl-letf (((symbol-function 'read-string)
               (lambda (&rest _) (error "The Bridge must not prompt"))))
      (revu-magit--run (revu-magit-revision-plan "feature" nil) nil))
    (should (get-buffer
             (revu-buffer-name (format "%s..%s"
                                       (revu-magit-test--short root "feature^")
                                       (revu-magit-test--short root "feature")))))))

(ert-deftest revu-magit-opens-a-narrowed-review-over-magits-pathspecs ()
  "The pathspecs magit filtered by are the Narrowing the Review records."
  (revu-fixture-in-repo root
    (revu-magit--run (revu-magit-plan nil nil '("beta.txt") 'unstaged)
                     (revu-magit--caveats nil 'unstaged))
    (should (equal (revu-source-paths
                    (revu-review-source
                     (revu-fixture-sidecar root "worktree--beta.txt")))
                   '("beta.txt")))))

(provide 'revu-magit-test)
;;; revu-magit-test.el ends here
