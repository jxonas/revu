;;; revu-narrowing-test.el --- Tests for a narrowed diff Source  -*- lexical-binding: t; -*-

;;; Commentary:

;; Tests for the Narrowing a diff Source may carry (ADR-0005's
;; amendment): the pathspecs the Source is limited to, recorded only when
;; one was given, replayed when the Source is read again, and part of the
;; Review name so that a narrowed Review is a different Review from the
;; full one over the same Revisions.

;;; Code:

(require 'ert)
(require 'magit-section)
(require 'revu)
(require 'revu-fixture)

;;;; The record

(ert-deftest revu-narrowing-is-recorded-only-when-one-was-given ()
  "A Source without a Narrowing carries exactly the fields it carried before."
  (should (equal (revu-source-worktree "HEAD")
                 '((kind . "worktree") (base . "HEAD"))))
  (should (equal (revu-source-staged "HEAD")
                 '((kind . "staged") (base . "HEAD"))))
  (should (equal (revu-source-range "main" "feature")
                 '((kind . "range") (base . "main") (head . "feature"))))
  (should-not (revu-source-paths (revu-source-range "main" "feature")))
  ;; An empty Narrowing is no Narrowing: it means every path.
  (should-not (assq 'paths (revu-source-worktree "HEAD" nil)))
  (should-not (assq 'paths (revu-source-worktree "HEAD" [])))
  ;; And it reaches the Sidecar as the same bytes it did before.
  (should (string-match-p
           (regexp-quote "\"source\":{\"kind\":\"worktree\",\"base\":\"HEAD\"},")
           (revu-review-encode
            (revu-review-create "worktree" (revu-source-worktree "HEAD")))))
  (should (string-match-p
           (regexp-quote (concat "\"source\":{\"kind\":\"range\",\"base\":\"main\","
                                 "\"head\":\"feature\",\"paths\":[\"docs\"]},"))
           (revu-review-encode
            (revu-review-create "n" (revu-source-range "main" "feature"
                                                       '("docs")))))))

(ert-deftest revu-narrowing-is-recorded-as-an-array-of-pathspecs ()
  "A Narrowing is stored as a JSON array and read back as a list."
  (let ((source (revu-source-range "main" "feature" '("src/foo/" "docs"))))
    (should (equal (alist-get 'paths source) ["src/foo/" "docs"]))
    (should (equal (revu-source-paths source) '("src/foo/" "docs")))
    (should (equal (revu-review-decode (revu-review-encode
                                        (revu-review-create "n" source)))
                   (revu-review-create "n" source))))
  (should (equal (revu-source-paths (revu-source-worktree "HEAD" ["src/"]))
                 '("src/")))
  (should (equal (revu-source-paths (revu-source-staged "HEAD" '("src/")))
                 '("src/"))))

(ert-deftest revu-narrowing-refuses-a-sidecar-whose-paths-are-not-pathspecs ()
  "A `paths' field that is not an array of strings refuses the Sidecar."
  (dolist (paths '("src/" [7] [:null]))
    (let ((error-data
           (should-error
            (revu-review-validate
             `((schema . 1) (name . "n")
               (source . ((kind . "range") (base . "a") (head . "b")
                          (paths . ,paths)))
               (annotations . [])))
            :type 'revu-invalid-sidecar)))
      (should (string-match-p "paths" (format "%s" (cadr error-data)))))))

;;;; The name

(ert-deftest revu-narrowing-appends-a-slug-of-its-pathspecs-to-the-name ()
  "A narrowed Source derives its own Review name, so it is its own Review."
  (should (equal (revu-review-name-for-source
                  (revu-source-range "main" "feature" '("src/foo/" "docs")))
                 "main..feature--src-foo--docs"))
  (should (equal (revu-review-name-for-source
                  (revu-source-worktree "HEAD" '("src/foo/")))
                 "worktree--src-foo"))
  (should (equal (revu-review-name-for-source
                  (revu-source-staged "HEAD" '("docs")))
                 "staged--docs"))
  ;; The same Narrowing resumes the same Review; the full one is another.
  (should (equal (revu-review-name-for-source
                  (revu-source-range "main" "feature" '("src/foo/")))
                 (revu-review-name-for-source
                  (revu-source-range "main" "feature" ["src/foo/"]))))
  (should-not (equal (revu-review-name-for-source
                      (revu-source-range "main" "feature" '("src/foo/")))
                     (revu-review-name-for-source
                      (revu-source-range "main" "feature")))))

;;;; The diff

(defun revu-narrowing-test--commit-everything (root)
  "Commit everything the fixture worktree carries under ROOT.
The commit touches four files at once, so `HEAD^..HEAD' is a range a
Narrowing has something to leave out of."
  (revu-fixture-git-output root "add" "-A")
  (revu-fixture-git-output root "commit" "-q" "-m" "Everything at once"))

(ert-deftest revu-narrowing-limits-the-diff-a-source-is-read-from ()
  "The diff text of a narrowed Source carries the narrowed files only."
  (revu-fixture-in-repo root
    (revu-narrowing-test--commit-everything root)
    (let ((full (revu-diff-range-text root "HEAD^" "HEAD"))
          (narrowed (revu-diff-range-text root "HEAD^" "HEAD" '("beta.txt"))))
      (should (string-match-p "alpha\\.txt" full))
      (should (string-match-p "beta\\.txt" narrowed))
      (should-not (string-match-p "alpha\\.txt" narrowed)))
    (let ((narrowed (revu-diff-worktree-text root "HEAD^" '("beta.txt"))))
      (should (string-match-p "beta\\.txt" narrowed))
      (should-not (string-match-p "alpha\\.txt" narrowed)))
    ;; Stage two files, so the staged diff has one to leave out.
    (revu-fixture-write-file root "alpha.txt" "alpha staged\n")
    (revu-fixture-write-file root "beta.txt" "beta staged\n")
    (revu-fixture-git-output root "add" "-A")
    (let ((full (revu-diff-staged-text root))
          (narrowed (revu-diff-staged-text root '("beta.txt"))))
      (should (string-match-p "alpha\\.txt" full))
      (should (string-match-p "beta\\.txt" narrowed))
      (should-not (string-match-p "alpha\\.txt" narrowed)))))

(ert-deftest revu-narrowing-survives-the-first-reload ()
  "A narrowed Review renders the narrowed files, and still does after `g'.
This is what the Narrowing exists for: reload reads the Source again, and
a reload that widened the diff would re-anchor every Annotation against
files the reviewer never asked for."
  (revu-fixture-in-repo root
    (revu-narrowing-test--commit-everything root)
    (let ((buffer (revu-diff-range "HEAD^" "HEAD" "narrowed" '("beta.txt"))))
      (with-current-buffer buffer
        (should (string-match-p "beta\\.txt" (revu-fixture-render)))
        (should-not (string-match-p "alpha\\.txt" (revu-fixture-render)))
        (revu-reload)
        (should (string-match-p "beta\\.txt" (revu-fixture-render)))
        (should-not (string-match-p "alpha\\.txt" (revu-fixture-render)))))))

;;;; The Sidecar

(ert-deftest revu-narrowing-round-trips-through-the-sidecar ()
  "A Sidecar carrying paths loads, renders and writes back with them intact."
  (revu-fixture-in-repo root
    (revu-narrowing-test--commit-everything root)
    (let ((buffer (revu-diff-range "HEAD^" "HEAD" "narrowed" '("beta.txt"))))
      (with-current-buffer buffer
        (should (equal (alist-get 'paths
                                  (revu-review-source
                                   (revu-fixture-sidecar root "narrowed")))
                       ["beta.txt"]))
        ;; A write of the Review keeps the Narrowing on the record.
        (revu-fixture-goto-line-matching "beta two staged")
        (revu-annotate-line "question" "Why staged?")
        (let ((review (revu-fixture-sidecar root "narrowed")))
          (should (equal (revu-source-paths (revu-review-source review))
                         '("beta.txt")))
          (should (equal (length (revu-review-annotations review)) 1)))
        ;; And a load of that Sidecar renders the narrowed set again.
        (revu-reload)
        (should (string-match-p "Why staged\\?" (revu-fixture-render)))
        (should-not (string-match-p "alpha\\.txt" (revu-fixture-render)))))))

(ert-deftest revu-narrowing-loads-from-a-sidecar-revu-did-not-write ()
  "A Sidecar carrying paths, written by something else, loads narrowed.
This is the Bridge\='s own case: the Narrowing on the record is what the
Review is read through, whoever wrote the record."
  (revu-fixture-in-repo root
    (revu-narrowing-test--commit-everything root)
    (let ((base (revu-fixture-git-output root "rev-parse" "HEAD^"))
          (head (revu-fixture-git-output root "rev-parse" "HEAD")))
      (make-directory (expand-file-name ".revu/reviews" root) t)
      (write-region
       (format (concat "{\"schema\":1,\"name\":\"foreign\","
                       "\"source\":{\"kind\":\"range\",\"base\":\"%s\","
                       "\"head\":\"%s\",\"paths\":[\"beta.txt\"]},"
                       "\"annotations\":[]}\n")
               base head)
       nil (expand-file-name ".revu/reviews/foreign.json" root) nil 'silent)
      ;; The Review resumes off that record, and reads its Source through
      ;; the Narrowing the record carries.
      (with-current-buffer (revu-diff-range base head "foreign")
        (revu-reload)
        (should (string-match-p "beta\\.txt" (revu-fixture-render)))
        (should-not (string-match-p "alpha\\.txt" (revu-fixture-render)))
        ;; A write of the Review leaves the Narrowing where it was.
        (revu-fixture-goto-line-matching "beta two staged")
        (revu-annotate-line "note" "Read.")
        (should (equal (revu-source-paths
                        (revu-review-source
                         (revu-fixture-sidecar root "foreign")))
                       '("beta.txt")))))))

(ert-deftest revu-narrowing-is-only-what-a-caller-asked-for ()
  "The entry commands narrow when a caller passes pathspecs, and not otherwise."
  (revu-fixture-in-repo root
    (revu-narrowing-test--commit-everything root)
    (revu-diff-range "HEAD^" "HEAD" "full")
    (should-not (assq 'paths (revu-review-source
                              (revu-fixture-sidecar root "full"))))
    (revu-diff-worktree "worktree-full")
    (should-not (assq 'paths (revu-review-source
                              (revu-fixture-sidecar root "worktree-full"))))
    (revu-diff-staged "staged-full")
    (should-not (assq 'paths (revu-review-source
                              (revu-fixture-sidecar root "staged-full"))))))

(provide 'revu-narrowing-test)
;;; revu-narrowing-test.el ends here
