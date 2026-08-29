---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m171xymaka1ygnb461813fa3
  text: |
    Picked up. Research notes:

    - Bug confirmed by reading the code. `SelectionTier.assemblePrefix(preamble:ids:catalog:)` builds `"\(preamble)\n\n# Candidates\n\(summaryBlocks.joined(separator: "\n\n"))"` from `ids.compactMap { catalog.summaryBlock(forID: $0) }`. No id ever reaches the prompt. `SearchCorpus.summaryBlock(forID:)` returns `rows[id]?.summary` — the bare summary text, no id.
    - The preamble `String.selectionDefault` says "Do not invent ids; return an empty list if nothing fits." The model never sees an id, so it answers with a summary. That matches the measured `unknownSelectedId(id: "Search file contents with regular expressions")`.
    - `assemblePrefix(preamble:catalog:)` already delegates to the `ids:` overload, so one helper covers both the cached-root path and the over-budget path.
    - Boundary fixtures found: `OverBudgetTests.prefixExactlyAtTheCapacityLimitUsesTheCachedRootPath` and `prefixOneCharacterOverTheCapacityLimitUsesTheOneOffPath` both compute the expected prefix with `SelectionTier.assemblePrefix(...)`, so they follow the format automatically.
    - `SearcherTests.bulkItems` forces the over-budget path with bulk `summary` filler. A longer prefix keeps it over budget, so no adjustment is needed there.
    - Baseline `swift build` is clean.
  timestamp: 2026-08-29T15:24:08.202972+00:00
- actor: claude-code
  id: 01m17246sy2c5h7gfre9c0mhwd
  text: |
    TDD cycle complete.

    RED (before the fix), `swift test --filter 'SelectionTests|OverBudgetTests'` reported 7 issues. The failure output printed the whole assembled prefix and proved the bug:

    ```
    Given a task, return ONLY the items needed ...
    Do not invent ids; return an empty list if nothing fits.

    # Candidates
    ships containers to a kubernetes cluster

    reverts the last release
    ```

    No id anywhere. Failing tests: `assemblePrefixRendersEveryCandidateIdWithItsSummary` (3 issues), `theSeededSessionInstructionsCarryEveryCatalogId` (2), `overBudgetInstructionsCarryOnlyTheTopMCandidateIds` (2). The regression test `anItemSummaryAnsweredInPlaceOfItsIdIsFilteredAndReportedAsUnknown` passed before the fix, as intended -- it pins the backstop, it does not test the new format.

    GREEN: new `private static func candidateEntry(forID:catalog:)` renders `## <id>\n<summary>`. `assemblePrefix(preamble:ids:catalog:)` maps every id through it; `assemblePrefix(preamble:catalog:)` delegates to that overload, so both paths use the one helper.

    No test fixture needed a budget adjustment. The two boundary tests compute the limit from `SelectionTier.assemblePrefix(...)` itself, so they follow the longer format. `SearcherTests.bulkItems` forces over budget with filler, and a longer prefix stays over budget.

    End-to-end proof: `swift run FullMonty` on the on-device model path now returns a real match for every query -- grep, commit, branch, stash -- instead of `(no matches)`. No `unknownSelectedId` diagnostic is reported any more. Only `embeddingUnavailable` remains, which is expected on the default path with no embedder.
  timestamp: 2026-08-29T15:27:33.182642+00:00
- actor: claude-code
  id: 01m1727kwgvry8z8nre9gmbgkx
  text: |
    ### implement — changed

    - evidence: 3 files.
      - `Sources/FoundationModelsRanker/Selection/SelectionTier.swift` — new `private static func candidateEntry(forID:catalog:)` renders `## <id>` above the id's `summaryBlock(forID:)`. `assemblePrefix(preamble:ids:catalog:)` now maps every id through that one helper. `assemblePrefix(preamble:catalog:)` keeps forwarding to it, so both the cached-root path and the over-budget path get the id and cannot drift. Doc comments on the type, on `overBudgetSearch`, and on both overloads now state the format. `SelectionCatalog.summaryBlock(forID:)` and `SearchCorpus` are untouched, as the card requires.
      - `Tests/FoundationModelsRankerTests/SelectionTests.swift` — added the `threeItemCatalog` fixture and 3 tests: `assemblePrefixRendersEveryCandidateIdWithItsSummary`, `theSeededSessionInstructionsCarryEveryCatalogId`, `anItemSummaryAnsweredInPlaceOfItsIdIsFilteredAndReportedAsUnknown`.
      - `Tests/FoundationModelsRankerTests/OverBudgetTests.swift` — added `overBudgetInstructionsCarryOnlyTheTopMCandidateIds`.
    - fixtures: none needed a budget adjustment. Both boundary tests derive the limit from `SelectionTier.assemblePrefix(...)`, so the longer prefix moves the boundary with them. `SearcherTests.bulkItems` stays over budget because the prefix only grew.
    - measured: `swift build` exit 0, no warning except the pre-existing `mlx-swift_Cmlx.bundle` line. `swift test` — 256 tests in 21 suites passed, 0 failures, 0 warnings. `swift run FullMonty` on the on-device path returns a real match for all 4 queries (grep, commit, branch, stash), with no `unknownSelectedId`.
    - note: `.kanban/tasks/01M16WW6WN0638CJKEJ3XEHKMV.*` was already modified in the working tree before this task started. It belongs to card ^kejxehkmv, and this task did not touch it.
    - next: `/review`
  timestamp: 2026-08-29T15:29:24.880125+00:00
- actor: claude-code
  id: 01m172c2x76z4phb0hv1q6cswg
  text: |
    Validator rules checked against the diff. The `dump validators` call on `SelectionTier.swift` returned 7 validators and 55 rules across `code-hygiene`, `code-security`, `completeness`, `duplication`, `reuse`, `swift`, and `test-integrity`. The rules that bear on this change, and how each is met:

    - `completeness/invariant-propagation` — the reason both overloads had to change. Met by the carve-out it states word for word: "A shared helper already centralizes the handling and the change went there, so all callers inherit it." `candidateEntry(forID:catalog:)` is that helper.
    - `duplication/duplication` and `duplication/swift` — the remaining repetition is one forwarding line in `assemblePrefix(preamble:catalog:)`. Carved out: "If the shared logic is already extracted and only the forwarding line repeats, the duplication is resolved — do not flag the shim. Copies that contain no logic cannot drift."
    - `reuse/reuse` — protects the new helper: "Single-call-site helpers are not a reuse concern ... never flag toward inlining it." It has two callers.
    - `code-hygiene/dead-code-swift` — `--retain-public` retains only `open`/`public`, so a private declaration must be referenced. `candidateEntry` is called from `assemblePrefix(preamble:ids:catalog:)`. Not dead, and no `// periphery:ignore` marker is needed.
    - `swift/access-control` — `private` is correct here because the only caller is a static method on the same type. No test calls the helper directly; the tests drive it through the public overloads. "`@testable import` reaches `internal`, never `private`" therefore does not bite. `swift build` proves it compiles.
    - `code-hygiene/missing-docs-swift` — the shipped config is `warning: [open, public]`, so the private helper needs no doc comment. It has one anyway. Both public overloads keep theirs, updated to state the new format.
    - `swift/doc-parameter-naming` — "`- Parameter` entries name the internal (local) parameter, never the external argument label." The helper is `candidateEntry(forID id:catalog:)`, so the doc key is `- id:`, not `- forID:`. The `assemblePrefix` keys stay `preamble`, `ids`, `catalog`, which are the internal names.
    - `swift/idioms` — "Don't repeat the enclosing type's name in a static member." `candidateEntry` does not repeat `SelectionTier`. No static constant was added, so no naming question arises there.
    - `swift/naming-clarity` — "Compensate for weak type information. Precede a weakly typed parameter (`Any`, `AnyObject`, `NSObject`, `Int`, `String`) with a noun describing its role." The `String` parameter carries the label `forID`.
    - `code-hygiene/magic-numbers-swift` — supersedes `magic-numbers` and reads numeric literals only (`no_magic_numbers`). The `"## "` heading marker is a string literal, outside the rule. Under the superseded prompt rule it would also be carved out as a one-off used exactly once.
    - `completeness/public-output-contract` check 1 — "The diff rewrites the text or structure of an existing user-facing message/output that the change did not require." Released by its own carve-out, "The task explicitly asked to change the message/output/format": this card asks for exactly this format change. Check 3 (output shape on an edge path) holds too — an empty candidate list still yields `preamble + "\n\n# Candidates\n"`, the same shape as before.
    - `completeness/inverse-operation-coverage` — checked, and the "Genuinely one-way operations with no inverse" carve-out applies. `assembledPrefix` is consumed at exactly two sites: `.count` for the budget guard, and `config.model(prefix, grammar)` as session instructions. Nothing parses the prefix back.
    - `test-integrity/no-test-cheating` item 4, "A weakened assertion" — no existing assertion was loosened. Four tests were added and none removed. No test was skipped, emptied, or commented out.
    - `test-integrity/no-hard-code` — `assemblePrefix` branches on no test id and no test value. The expected strings sit in assertion comparison position, which the rule carves out.
    - `test-integrity/test-partitioning` — the new tests are unit tests over scripted `AgentSession` fakes. No real model, no network.
    - `code-hygiene/function-length-swift` — the gate is 250 code lines per declaration. Every declaration here is far under it.
    - `code-hygiene/no-commented-code` — the old summary-only assembly was deleted, not commented out.
    - `code-hygiene/data-driven` — no match or if-chain was added.
    - `code-security/injection` — the six sinks are SQL, shell, path, HTML/XML, XXE, and deserialization. A markdown prompt prefix is none of them.

    One item found outside this card's file list: `plan.md` phase 3 still describes the prefix as "preamble + `# Candidates` + each candidate's summary block", which the new format contradicts, and `SelectionTier`'s doc comments cite "plan.md §6" as the authority. This card lists only `SelectionTier.swift` and the test files as files to change, so `plan.md` was not edited. Recorded as task ^3t4nhk7.
  timestamp: 2026-08-29T15:31:51.335209+00:00
- actor: claude-code
  id: 01m172cd1v0jd1re5qenm16ksg
  text: |
    ### implement — changed

    - evidence: 3 files — `Sources/FoundationModelsRanker/Selection/SelectionTier.swift`, `Tests/FoundationModelsRankerTests/SelectionTests.swift`, `Tests/FoundationModelsRankerTests/OverBudgetTests.swift`. New `private static func candidateEntry(forID:catalog:)` renders `## <id>` above the id's summary; both `assemblePrefix` overloads route through it. 4 tests added, 1 fixture added, 0 fixtures adjusted for budget. `swift build` exit 0, no new warning. `swift test` — 256 tests in 21 suites passed, 0 failures. `swift run FullMonty` returns a real match for all 4 queries with no `unknownSelectedId`.
    - rules: 55 rules across 7 validators checked against the diff. No correction was needed, so the rules pass changed no code.
    - follow-up: ^3t4nhk7 — `plan.md`'s prefix description is stale, and that file is outside this card's stated file list.
    - next: `/review`
  timestamp: 2026-08-29T15:32:01.723432+00:00
- actor: claude-code
  id: 01m172nfsyfyptvc18rfykv7d8
  text: |
    ### review — clean

    - evidence: `review sha HEAD~1..HEAD` (commit `cbcee8c`). 3 files reviewed, 7 validators attempted, 0 failed. counts: findings 0, confirmed 0, refuted 0. The 6 `.kanban/` files are excluded by `.reviewignore`.
    - format coherence: the prefix is a one-way format. `assembledPrefix` goes to only two places -- `.count` for the budget guard in `search(intent:limit:)`, and `config.model(prefix, grammar)` as session instructions. The over-budget `prefix` goes to the one-off session only. No code parses the prefix back into ids, so there is no round trip to break. The `## <id>` heading separates the id from the summary text below it.
    - overload coverage: `assemblePrefix(preamble:ids:catalog:)` maps every id through `candidateEntry(forID:catalog:)`. `assemblePrefix(preamble:catalog:)` forwards to that overload with `ids: catalog.ids`. No path renders the old format.
    - fixture quality: `threeItemCatalog` gives each item an explicit `summary`, so `FixtureSelectionCatalog.summaryBlock(forID:)` returns the summary, not the `block`. The three ids -- `deploy`, `rollback`, `status` -- appear in no summary (`ships containers to a cluster`, `reverts the last release`, `reports the current release state`) and in no part of the `.selectionDefault` preamble. Therefore `prefix.contains(id)` can pass only because the heading renders the id.
    - boundary tests: `prefixExactlyAtTheCapacityLimitUsesTheCachedRootPath` and `prefixOneCharacterOverTheCapacityLimitUsesTheOneOffPath` build `expectedPrefix` from `SelectionTier.assemblePrefix` with the same preamble and catalog the tier uses, then set the limit to `expectedPrefix.count` and `expectedPrefix.count - 1`. The limit follows the prefix length, so each test still measures the boundary in its name.
    - out of scope, not reported: `Package.swift` (^2q0p8gr), `README.md` (^jdw7sf0), `plan.md` (^3t4nhk7).
    - next: task moved to `done`.
  timestamp: 2026-08-29T15:36:59.454070+00:00
- actor: claude-code
  id: 01m172pcjhh9k37b9jrsgz4sca
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 3 files; private candidateEntry(forID:catalog:) added, both assemblePrefix overloads route through it, 3 new tests
    - test: green — swift test, 256 passed, 0 failed, 0 skipped; the over-budget boundary tests still derive their limit from assemblePrefix, so they still measure the boundary
    - commit: cbcee8c — 9 files changed, 310 insertions, 23 deletions
    - review: clean — zero findings; all four directed checks passed, including that the threeItemCatalog fixture cannot pass by substring luck
    - next: none — task is in done

    End-to-end proof of the bug fix: `swift run FullMonty` on the default on-device path now returns a real match for every query. Before the fix every query printed `(no matches)` and reported `unknownSelectedId`.
  timestamp: 2026-08-29T15:37:28.913026+00:00
position_column: done
position_ordinal: '9780'
title: Render each candidate id in the assembled selection prefix
---
## What

The selection prompt never shows the model an id. `SelectionTier.assemblePrefix(preamble:ids:catalog:)` joins `catalog.summaryBlock(forID:)` values and nothing else. `SearchCorpus.summaryBlock(forID:)` (`Sources/FoundationModelsRanker/SearchCorpus.swift:211`) returns `rows[id]?.summary`, which is the bare summary text. The preamble then tells the model "Do not invent ids", but the model has seen no ids at all.

Measured on 2026-08-29 with `swift run FullMonty` on the default on-device path: every query printed `(no matches)`, and every query reported a diagnostic of the form `unknownSelectedId(id: "Search file contents with regular expressions")`. The model answered with a description, because a description is all it saw.

Until now a Router caller did not see this. Its id-enum `Grammar` made the decoder emit a member of the id set, whatever the prompt showed. Task `^4kx83sx` removes the grammar from the seam. After that task lands, nothing corrects the prompt. This task must land first.

Files to change:

- `Sources/FoundationModelsRanker/Selection/SelectionTier.swift` — change `assemblePrefix(preamble:ids:catalog:)` so each candidate renders its id together with its summary. Use a heading that a model reads as a label, for example:

  ```
  ## <id>
  <summary>
  ```

  The whole-catalog overload `assemblePrefix(preamble:catalog:)` calls the same helper, so one change covers both the cached-root path and the over-budget path.
- Check every test that asserts on prefix text or on `capacityCharacterLimit` boundaries. The prefix grows by the length of each id plus the heading, so a fixture that sits on a budget edge may cross it. Adjust the fixture, not the budget.

Do not change `SelectionCatalog.summaryBlock(forID:)` or `SearchCorpus`. The id belongs to the prefix format, not to the stored summary.

## Acceptance Criteria

- [x] `SelectionTier.assemblePrefix(preamble:ids:catalog:)` output holds every id it was given.
- [x] The output still holds every candidate summary.
- [x] The over-budget path's prefix holds only the top-M ids, not every catalog id.
- [x] `swift build` gives no error and `swift test` passes.

## Tests

- [x] Add to `Tests/FoundationModelsRankerTests/SelectionTests.swift`: `assemblePrefix` over a three-item catalog returns text that holds all three ids and all three summaries.
- [x] Add a test that drives `SelectionTier.search(intent:limit:)` with a `ScriptedAgentSession` and asserts the instructions text the session received holds each catalog id.
- [x] Add to `Tests/FoundationModelsRankerTests/OverBudgetTests.swift`: over budget, the one-off session's instructions hold the top-M ids and do not hold an id that was cut.
- [x] Add a regression test for the measured failure: when the scripted session answers with an item's summary text rather than its id, `search(intent:limit:)` returns no match for it and reports `.unknownSelectedId`. This pins the backstop that the deleted grammar used to provide.
- [x] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.