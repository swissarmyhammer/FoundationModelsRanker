---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3vyvk9gmzs7nhh8y95mgqdp
  text: |-
    Measurement on the on-device system model, with the exact-id preamble and the description-only summary (HEAD 30b6d91, no source change).

    Method: `swift test --package-path IntegrationTests --filter FunctionCatalogRealModelTests`, three runs in sequence. Each run asks the ten queries one time each. Each query makes its own `SelectionTier`, so each query has a cold session. Three runs = three rounds = 30 cold searches.

    Result:
    - Round 1: 10 of 10 answered, 0 issues (47.5 s).
    - Round 2: 10 of 10 answered, 0 issues (46.1 s).
    - Round 3: 10 of 10 answered, 0 issues (45.1 s).
    - Total: 30 of 30 answered. Issues recorded: none. No `.unknownSelectedId` diagnostic. No empty answer.

    Per query, 3 of 3 each: "Search the astropy codebase for files, read code, and run tests"; "list files and read file contents"; "grep search for text pattern in files"; "run a shell command or python script, execute code"; "run pytest tests, execute"; "write file, edit file, create file"; "edit code, modify source file, patch"; "apply changes to a file, save file contents"; "file operations: create, write, append, delete, move"; "create a new text file with given content on disk".

    Then one full `swift test --package-path IntegrationTests` run, with the full output kept: 6 tests in 6 suites passed, and the function-catalog suite passed 10 of 10 again while the other suites ran in parallel (86.3 s). That is a fourth round: 40 of 40 in all.

    Conclusion: the count is 30 of 30, so the second acceptance criterion (find and correct the cause) does not apply. No prompt text and no test catalog changed. The single issue that the ^knyvhkf full run recorded did not occur again in 40 cold searches. Its query and text are not known, because that output was cut. If it occurs again, keep the full output of the run (for example with the `shell` history) so that the query and the issue text are known.
  timestamp: 2026-10-01T14:45:52.048235+00:00
- actor: claude-code
  id: 01m3vyvp1dx1bwzhjxt4yb091d
  text: |-
    ### implement — no-change
    - evidence: no files changed. `swift test --package-path IntegrationTests --filter FunctionCatalogRealModelTests` x3 in sequence: 10/10, 10/10, 10/10 passed (30 of 30, 0 issues). `swift test`: 302 tests in 24 suites passed. `swift test --package-path IntegrationTests`: 6 tests in 6 suites passed. The only warning in each build is the toolchain line "missing creator for mutated node" for the mlx-swift_Cmlx.bundle, which comes from the build system for a dependency, not from this package's sources.
    - next: review of the recorded measurement.
  timestamp: 2026-10-01T14:45:54.861526+00:00
- actor: claude-code
  id: 01m3vz2j442wzvq3kwh3ttkpwk
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (commit 7f1f2b5). 0 findings, 0 confirmed, 0 refuted. The commit changes 4 files. All 4 files are in .kanban/, and .reviewignore excludes them. No code changed.
    - next: none. The task is in done.
  timestamp: 2026-10-01T14:49:40.228744+00:00
- actor: claude-code
  id: 01m3vz2tk9c974g8c7gv7taxh8
  text: |-
    ### finish iteration 1 — clean
    - implement: no-change — measurement only, 30 of 30 on the system model
    - test: green — swift test 302 passed; IntegrationTests 6 passed
    - commit: 7f1f2b5 (.kanban files only)
    - review: clean — 0 findings
  timestamp: 2026-10-01T14:49:48.905357+00:00
position_column: done
position_ordinal: b280
title: Measure the function-catalog suite on the system model with the exact-id preamble
---
## What
During ^knyvhkf, one full run of `swift test --package-path IntegrationTests` recorded 1 issue in `FunctionCatalogRealModelTests` ("A function catalog on the live system model"). The run output was cut, so the failing query and the issue are not known. The next run of that suite alone passed 10 of 10, and the next full run passed 6 of 6 suites.

The cause can be the new `SelectionConfig.selectionDefault` text, or the change to `LiveToolCatalog.summaryBlock(forID:)`, which now gives the description alone (the summary does not repeat the id). Card ^zxm99zs measured the earlier default at 30 of 30 on the on-device system model.

## Acceptance Criteria
- [x] Run the ten function-catalog queries three rounds each on the system model, one cold session for each query, and record the count of answered queries and each issue on this card.
- [x] If the count is less than 30 of 30, find the query and the cause, and correct the prompt text or the test catalog so that the suite passes each run. (Not applicable: the count is 30 of 30. See the comments.)

## Tests
- [x] `swift test --package-path IntegrationTests --filter FunctionCatalogRealModelTests` passes three runs in sequence. #selection