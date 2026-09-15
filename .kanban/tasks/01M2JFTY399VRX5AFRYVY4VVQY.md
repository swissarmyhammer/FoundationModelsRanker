---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m2jgzb2xfxdmzzc7123m6hpa
  text: |-
    Baseline before the first edit (HEAD 080ab9e):
    - Clean `swift build` into a new build path: 0 `warning:` lines. An incremental `swift build` also gives 0, but it compiles nothing, so the clean build is the true baseline.
    - `swift test`: "Test run with 283 tests in 22 suites passed". XCTest: 0 tests. `swift test` output: 0 `warning:` lines.

    Research: `rg -n "plan\.md|§" Package.swift Examples` gives 13 match lines, all in comments: Package.swift (4), Demo.swift (4), Catalog.swift (3 lines, 2 references; one reference goes across two lines), DemoEmbedder.swift (1), main.swift (1). The style reference is commit 080ab9e: it removes the pointer and keeps the rest of the sentence.
  timestamp: 2026-09-15T12:34:22.941522+00:00
- actor: claude-code
  id: 01m2jh3zf11xp5dbtgrr3vsq8w
  text: |-
    ### implement — changed
    - evidence: 5 files changed (17 insertions, 18 deletions), comments only — Package.swift, Examples/FullMontyCore/Demo.swift, Examples/FullMontyCore/Catalog.swift, Examples/FullMontyCore/DemoEmbedder.swift, Examples/FullMonty/main.swift. `rg -n "plan\.md" Package.swift Examples`: no match. `rg -n "§" Package.swift Examples`: no match. `git diff -U0 -- Package.swift Examples | rg '^[+-][^+-]' | rg -v '^[+-]\s*//'`: no match. Warnings: clean build 0 before, 0 after; plain `swift build` 0 after. Tests: 283 tests in 22 suites passed before and after (XCTest 0 before and after). `swift run FullMonty --no-model`: exit 0, 4 query blocks. No change in Sources/, Tests/, IntegrationTests/, or plan.md. Nothing committed.
    - design reasons written in place of plan pointers: Package.swift gives macOS 27 as the floor for FoundationModels v2. Demo.swift gives the `--no-model` path as safe to run in CI, and says that an earlier design used a `--model default` flag. The Searcher.swift header still explains `.default` versus `.fast`, so the pointer to it stays correct. The lineage notes ("New to FoundationModelsRanker — no source file to port", the FoundationModelsMetadataRegistry models) are kept.
    - next: /review
  timestamp: 2026-09-15T12:36:54.881794+00:00
- actor: claude-code
  id: 01m2jh6q60cntyn65ky69ktxdy
  text: |-
    ### test — green
    - evidence: `swift build` (clean, after `rm -rf .build`) — build complete, 0 warnings. `swift test` — Test run with 283 tests in 22 suites passed after 0.178 seconds. 0 failed. 0 skipped. `swift run FullMonty --no-model` — exit code 0. `swift build --package-path IntegrationTests --build-tests` — build complete, 0 warnings.
    - next: none. The suite is clean. No fix was needed.
  timestamp: 2026-09-15T12:38:24.704683+00:00
position_column: doing
position_ordinal: '80'
title: Remove plan.md references from Package.swift and the FullMonty example
---
## What
`plan.md` is the original extraction plan. The user wants it removed because the work that it describes is complete. Before we delete it, the comments that point to it must stop pointing to it. This task changes comments in the root manifest and in the example targets only. It is a comment-only change: no target, no dependency, and no behavior changes.

Files and reference counts:
- `Package.swift` (4): lines 22, 30, 39, 73 ("plan.md §3", "plan.md §3a").
- `Examples/FullMontyCore/Demo.swift` (4)
- `Examples/FullMontyCore/Catalog.swift` (3)
- `Examples/FullMontyCore/DemoEmbedder.swift` (1)
- `Examples/FullMonty/main.swift` (1)

Rules for each reference:
- If the comment only points to the plan, remove the pointer.
- Remove the section number (`§…`) and any quoted plan heading together with `plan.md`. Do this also when they are on the next comment line. An example is `(plan.md` on one line and `/// §3a "a handful of queries")` on the next line, in `Examples/FullMontyCore/Catalog.swift`. Every `§` in these files is a plan section number.
- If the comment uses the plan as the reason for a design choice, write the reason in the comment itself, in one short sentence. Then remove the pointer. For example, `Package.swift` lines 38-39 can say that macOS 27 is the FoundationModels v2 floor, with no plan reference.
- Do not add references to Router.

Do not add a test for this. The user does not want guard tests.

## Subtasks
- [x] Before the first edit, record the baseline. Count the `warning:` lines from `swift build 2>&1`, and record the test count from `swift test`.
- [x] Edit the comments in the files above.
- [x] Run the checks below.

## Acceptance Criteria
- [x] `rg -n "plan\.md" Package.swift Examples` gives no match.
- [x] `rg -n "§" Package.swift Examples` gives no match.
- [x] Comment-only: `git diff -U0 -- Package.swift Examples | rg '^[+-][^+-]' | rg -v '^[+-]\s*//'` gives no match.
- [x] `swift build` gives the same number of `warning:` lines as the baseline.
- [x] `swift run FullMonty --no-model` exits with status 0.
- [x] `swift test` passes with the same test count as the baseline.

## Tests
- [x] No new test. This is a comment-only change.
- [x] Run the `rg` and `git diff` commands above. Expected result: no match.
- [x] Run `swift build`, `swift run FullMonty --no-model`, and `swift test`. Expected result: all pass, and the results agree with the baseline.