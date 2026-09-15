---
assignees:
- claude-code
position_column: todo
position_ordinal: '8380'
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
- [ ] Before the first edit, record the baseline. Count the `warning:` lines from `swift build 2>&1`, and record the test count from `swift test`.
- [ ] Edit the comments in the files above.
- [ ] Run the checks below.

## Acceptance Criteria
- [ ] `rg -n "plan\.md" Package.swift Examples` gives no match.
- [ ] `rg -n "§" Package.swift Examples` gives no match.
- [ ] Comment-only: `git diff -U0 -- Package.swift Examples | rg '^[+-][^+-]' | rg -v '^[+-]\s*//'` gives no match.
- [ ] `swift build` gives the same number of `warning:` lines as the baseline.
- [ ] `swift run FullMonty --no-model` exits with status 0.
- [ ] `swift test` passes with the same test count as the baseline.

## Tests
- [ ] No new test. This is a comment-only change.
- [ ] Run the `rg` and `git diff` commands above. Expected result: no match.
- [ ] Run `swift build`, `swift run FullMonty --no-model`, and `swift test`. Expected result: all pass, and the results agree with the baseline.