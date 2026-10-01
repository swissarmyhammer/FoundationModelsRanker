---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3w0pvaes3sx3m3d4d09jr0x
  text: |-
    Research and cause.

    - The default factory (`Searcher.defaultSessionFactory`) makes a bare `LanguageModelSession`. The tier asks it for `Selection` by guided generation, but the `ids` field has no enum constraint. So the model can write any string as an id.
    - Baseline measurement (HEAD 30b6d91 text, a temporary probe test that drove `SelectionTier` with the default factory, one cold tier for each search, 20 searches for each query):
      - "write file, edit file, create file": 3 of 20 bad, each `[files.write, files.edit, !files.create]`. 15x `[files.write, files.edit]`, 2x `[files.write, files.edit, files.patch]`.
      - "file operations: create, write, append, delete, move": 1 of 20 bad, `[files.write, !files.delete]`.
      - "create a new text file with given content on disk": 0 of 20 bad.
    - Cause: each made-up id takes the `files.` prefix of the catalog and a verb of the request that no candidate serves (create, delete). The ^knyvhkf preamble removed the earlier sentence "Use only the ids shown." and kept only a negative instruction ("do not ... make one up"). No sentence said what to do with a part of the request that no candidate serves.
    - Change: two sentences in `String.selectionDefault`. Paragraph 1 gets "A request can ask for more than the candidates do: choose the candidates for the parts that they serve, and leave out each part that no candidate serves." Paragraph 2 gets "Use only the ids written after "id:" below." The entry format, the prompt and the `@Guide` did not change.
    - Probe with the new text, 30 searches for each of the two failing queries: 0 of 30 bad and 0 of 30 bad (26x `[files.write, files.edit]`, 4x `[files.write]` for the second query). Under the baseline rate, 0 bad in 60 has a probability of less than 1 percent.
    - The probe file was temporary and is deleted.
  timestamp: 2026-10-01T15:18:13.582557+00:00
- actor: claude-code
  id: 01m3w3gb9xsrq9fswhtn2mhzm7
  text: |-
    Regression found, and more variants measured.

    The first change (variant A: the "parts" sentence and "Use only the ids written after "id:" below.") passed `FunctionCatalogRealModelTests` 5 of 5 runs (10/10 each, shell commands 64-68) and the Qwen3-4B URI suite 5/5 (command 69). But the full `swift test --package-path IntegrationTests` run (command 71) failed in `ZeroConfigSearcherRealModelTests`: query "how do I list or delete a branch" gave `.unknownSelectedId(id: "delete")`.

    Probe results (system model, one cold tier for each search; later probes run 10 searches in parallel, and parallel searches give correlated answers, so the effective sample is smaller than the count):
    - HEAD text: branch query 0/20 bad (serial). Files queries: create 3/20, delete 1/20 bad (serial).
    - A (parts + use-only): branch 9/20 bad (serial), create 0/30, delete 0/30.
    - B (use-only alone): branch 7/20, create 7/20, delete 0/20.
    - C (parts alone): branch 20/20 bad (`[branch, !delete]`), create 0/20, delete 0/20.
    - D ("An id is not a name, a title or a word of the request"): branch 0/20, create 5/20, delete 0/20.
    - F (HEAD preamble, `@Guide` adds "each id is one of the ids written on an id: line, never a new id"): branch 0/20, create 3/20, delete 2/20 (`[files.write, !files.delete, !files.move]`).

    Conclusion so far: each wording moves the made-up id from one query to another. The "parts" sentence makes the model give one id for each verb of the request, and it then makes up "delete" for the branch query.
  timestamp: 2026-10-01T16:07:06.301588+00:00
- actor: claude-code
  id: 01m3w4yzffmqmcj1fhz8je5yq3
  text: |-
    Correction that landed: variant G, a change to the prompt (the request part). The preamble, the entry format and the `@Guide` are the same as at HEAD 30b6d91.

    The last line of each prompt is now:
    `Answer with the exact ids of the chosen candidates. Choose only from these ids: <id>, <id>, ....`
    The list holds the ids that the prefix of that prompt shows, in prefix order: the summarized catalog ids under budget (`SelectionTier.assembledIDs`, precomputed at `init`), one run over budget.

    Why G: the made-up ids were always a request verb in the form of the catalog ids. A closed list beside the request, where the model reads last, removes the made-up ids. Prompt-only probe on the three failing queries, 20 searches each: 0 bad, 0 bad, 0 bad (`[branch, checkout]` 17x, `[branch, checkout, rm]` 3x; `[files.write, files.edit, files.patch]` 16x, `[files.write, files.edit]` 4x; the delete query gave five different valid id sets). The answers can hold one more valid id than before. The tests claim only valid, non-empty answers, and the card asks only for catalog ids.

    Measurements on the final code (full output kept in the shell history, command ids in brackets):
    - `swift test --package-path IntegrationTests --filter FunctionCatalogRealModelTests`, 5 runs in sequence:
      - Run 1 [98]: 10 of 10 passed, 0 issues (48.9 s).
      - Run 2 [99]: 10 of 10 passed, 0 issues (26.2 s).
      - Run 3 [100]: 10 of 10 passed, 0 issues (24.0 s).
      - Run 4 [101]: 10 of 10 passed, 0 issues (26.4 s).
      - Run 5 [102]: 10 of 10 passed, 0 issues (24.1 s).
      - Total 50 of 50.
    - `swift test --package-path IntegrationTests --filter UriCatalogQwenRealModelTests` [103]: 5 of 5 rounds passed.
    - `swift test --package-path IntegrationTests`, 2 full runs [104, 105]: 6 tests in 6 suites passed each time. Each run includes the function-catalog suite (10/10), the zero-config suite (4/4, with "how do I list or delete a branch") and the URI suite (5/5). Totals with the 5 runs above: 70 of 70 function-catalog searches.
    - `swift test` [106]: 303 tests in 24 suites passed.
    - The only warning in each build is the toolchain line "missing creator for mutated node" for `mlx-swift_Cmlx.bundle`. It comes from the build system for a dependency, not from this package.

    Unit tests (TDD): `ExpectedSelectionPrompt.request(for:ids:)` now takes the ids. Updated tests in SelectionTests, OverBudgetTests (per-run ids), SearcherTests, PooledConformanceTests went RED (6 issues) and then GREEN. New test `thePromptNamesOnlyTheIdsThatThePrefixShows` went RED with `catalog.ids` and GREEN with `assembledIDs`.

    Note for the orchestrator: the temporary probe file `ZZProbe.swift` is deleted. The scratch copies of variants are in the session scratchpad only.
  timestamp: 2026-10-01T16:32:34.287197+00:00
- actor: claude-code
  id: 01m3w4zmy1qb5v362y2pe0m4w6
  text: |-
    ### implement — changed
    - evidence: 7 files: Sources/FoundationModelsRanker/Selection/SelectionTier.swift, Sources/FoundationModelsRanker/Selection/SelectionConfig.swift (doc comment only), Tests/FoundationModelsRankerTests/Support/ExpectedSelectionPrompt.swift, Tests/FoundationModelsRankerTests/SelectionTests.swift, Tests/FoundationModelsRankerTests/OverBudgetTests.swift, Tests/FoundationModelsRankerTests/SearcherTests.swift, Tests/FoundationModelsRankerTests/PooledConformanceTests.swift. `swift test --package-path IntegrationTests --filter FunctionCatalogRealModelTests` x5 in sequence: 10/10, 10/10, 10/10, 10/10, 10/10 (50 of 50, 0 issues). `UriCatalogQwenRealModelTests`: 5/5. `swift test --package-path IntegrationTests` x2: 6 tests in 6 suites passed each run. `swift test`: 303 tests in 24 suites passed. Only warning: the toolchain line "missing creator for mutated node" for the mlx-swift_Cmlx.bundle dependency.
    - next: /review. The "CI is green on the pushed commit" item stays open until the orchestrator commits and pushes.
  timestamp: 2026-10-01T16:32:56.257667+00:00
position_column: doing
position_ordinal: '80'
title: System model makes up the id files.create for the query "write file, edit file, create file"
---
## What
CI run 36877840484 on commit 30b6d91 (the ^knyvhkf prompt change) failed in the job "ci / Integration (opt-in, real dependencies)". `FunctionCatalogRealModelTests` ("A function catalog on the live system model") recorded 1 issue:

- query: "write file, edit file, create file"
- location: `IntegrationTests/Tests/FoundationModelsRankerIntegrationTests/FunctionCatalogRealModelTests.swift:87`
- issue: `The selection tier reported .unknownSelectedId(id: "files.create").`

The catalog has no `files.create` id. The model made up a new id from the words of the query. The catalog has `files.write` and `files.edit`, which are the correct answers. The issue also occurred one time during ^knyvhkf on the local Mac. ^xrd68c1 then measured 30 of 30 locally, so the failure is intermittent. The local count is not sufficient evidence.

The Qwen3-4B URI suite passed 5 of 5 in the same CI run. The fix must keep that suite passing.

## Acceptance Criteria
- [x] Find why the system model makes up `files.create` with the new `SelectionConfig.selectionDefault`, the new `<candidate>` entry format, or the new prompt.
- [x] Correct the prompt text (preamble, entry format, prompt or `@Guide`) so that the system model selects only ids from the catalog for this query. Do not change the test query or the test catalog to hide the failure.
- [x] Run `swift test --package-path IntegrationTests --filter FunctionCatalogRealModelTests` at least 5 times in sequence and record each count on this card. Each run must pass 10 of 10. Keep the full output of each run.
- [x] The Qwen3-4B URI suite (`UriCatalogQwenRealModelTests`) still passes 5 of 5.
- [ ] CI is green on the pushed commit.

## Tests
- [x] Update the unit tests that pin the prompt text, if the text changes.
- [x] `swift test` and `swift test --package-path IntegrationTests` pass. #selection