---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m173e1avyh3v7j78avwhj6nz
  text: |-
    Research and discoveries.

    - The card's file list was incomplete. Four more test files call `SelectionConfig(model:)` with a two-argument closure and had to change, or the test target cannot compile: `SelectionConfigTests.swift` (5 sites), `AgentSessionDispatchTests.swift` (2 sites), `OverBudgetTests.swift` (5 sites beyond the deleted test), `SelectionTests.swift` (2 sites beyond the deleted test).
    - `Examples/FullMontyCore/LiveRouter.swift` no longer builds a grammar. A grep of `Examples/` for "grammar" or "Grammar" finds one doc line in `DemoEmbedder.swift` and nothing else. The example already drives `Searcher`'s one-argument `session:` seam, so it needed no change.
    - `README.md` already shows the one-argument `session:` seam. No change needed.
    - `Sources/FoundationModelsRanker/Selection/LanguageModelSessionSupport.swift` carried a file-header paragraph that named the two-argument seam. The change makes that text wrong, so the paragraph was rewritten. The card did not list this file; the edit is a direct result of the type change.
    - `import FoundationModelsRouter` became unused in `OverBudgetTests.swift` and `LanguageModelSessionSupportTests.swift` after the grammar assertions went away. Both imports were removed. `SelectionTests.swift` keeps its import, because the `idEnumGrammar(ids:)` tests still read `Grammar.jsonSchema`.
    - `cachedRootSession()` no longer throws and no longer needs `async`, so its signature is now `private func cachedRootSession() -> any AgentSession`. The `- Throws:` lines of `search(intent:limit:)` and `overBudgetSearch(intent:limit:)` that named `idEnumGrammar(ids:)` were corrected.

    TDD record. The tests were changed first. `swift build --build-tests` then failed with `contextual closure type '@Sendable (String, Grammar) -> any AgentSession' expects 2 arguments, but 1 was used in closure body` — the RED step. The production change made it GREEN.
  timestamp: 2026-08-29T15:50:23.835788+00:00
- actor: claude-code
  id: 01m173edapjr6ab5jkq02yzk3s
  text: |-
    Two points the reviewer must know.

    1. Forward reference to `idEnumSchema(ids:)`, and why. The card holds two requirements that point the same way but cannot both be true until `^cd4geys` lands: the new `SelectionConfig.swift` paragraph "must say ... that `SelectionTier.idEnumSchema(ids:)` supplies the id set", and `grep -rn "Grammar" Sources/FoundationModelsRanker/Selection/SelectionConfig.swift` must find nothing. The function is still named `idEnumGrammar(ids:)` today, and that name holds the word "Grammar". Naming the current symbol makes the grep criterion fail. The card was obeyed word for word: both places in `SelectionConfig.swift` name `SelectionTier.idEnumSchema(ids:)`. The reference resolves when `^cd4geys` renames the function. Do not report this as a defect and do not change it back; changing it back breaks a stated acceptance criterion.

    2. `Tests/FoundationModelsRankerTests/Support/GrammarTestSupport.swift` now has no caller. Its only two call sites were the two tests the card ordered deleted. It was left in place: the `dead-code` rule carves out "test functions and test-only helpers", and `dead-code-swift` writes one `--report-exclude` per test target, so periphery never reports a declaration in a test target. The card does not list the file, and deleting it is not in scope here. `^cd4geys` changes the return type of the function this helper reads, so that task is the place to decide its future.

    Also recorded: the unknown-id backstop test was extended, not added new. `unknownIdFromAMisbehavingFakeIsFilteredAndReportedAsADiagnostic` now drives four ids — two real ones with two unknown ones between them — and asserts both real ids survive and each unknown id is reported in order. Before the change, the id-enum grammar made that path structurally unreachable; now the filter is the only backstop, so the test carries a comment saying so.
  timestamp: 2026-08-29T15:50:36.118705+00:00
- actor: claude-code
  id: 01m173ekjacm8cw9jskkahzp2x
  text: |-
    ### implement — changed
    - evidence: 10 files — Sources/FoundationModelsRanker/Selection/SelectionConfig.swift, Sources/FoundationModelsRanker/Selection/SelectionTier.swift, Sources/FoundationModelsRanker/Selection/LanguageModelSessionSupport.swift, Sources/FoundationModelsRanker/Searcher.swift, Tests/FoundationModelsRankerTests/Support/ScriptedAgentSession.swift, Tests/FoundationModelsRankerTests/SelectionTests.swift, Tests/FoundationModelsRankerTests/OverBudgetTests.swift, Tests/FoundationModelsRankerTests/SelectionConfigTests.swift, Tests/FoundationModelsRankerTests/AgentSessionDispatchTests.swift, Tests/FoundationModelsRankerTests/LanguageModelSessionSupportTests.swift. `swift build` 0 errors. `swift test` 254 tests in 21 suites passed, 0 failures. `grep -rn "Grammar" Sources/FoundationModelsRanker/Selection/SelectionConfig.swift` finds nothing.
    - next: /review
  timestamp: 2026-08-29T15:50:42.506739+00:00
depends_on:
- 01M17004BEPEN2YVD6MG69HYYC
position_column: doing
position_ordinal: '80'
title: Remove the Grammar argument from the selection session seam
---
## What

`SelectionConfig.model` has the type `@Sendable (String, Grammar) -> any AgentSession`. `Grammar` is a `FoundationModelsRouter` type. Change the type to `@Sendable (String) -> any AgentSession`. This removes the Router type from the public selection API.

No caller loses behavior. `Searcher.swift` already ignores the grammar (`{ instructions, _ in session(instructions) }`). `Examples/FullMontyCore/LiveRouter.swift` builds one grammar for the whole catalog and reuses it for every call. The per-call grammar of the over-budget path is thus dead code today.

Files to change:

- `Sources/FoundationModelsRanker/Selection/SelectionConfig.swift` — change the `model` property and the `init` parameter to one argument. Delete `import FoundationModelsRouter`. Delete the file-header paragraph that explains the per-call grammar. Write a new paragraph. The new paragraph must say that a guided caller applies its own grammar when it makes the session, and that `SelectionTier.idEnumSchema(ids:)` supplies the id set.
- `Sources/FoundationModelsRanker/Selection/SelectionTier.swift` — in `cachedRootSession()` delete the grammar line and call `config.model(assembledPrefix)`. In `overBudgetSearch(intent:limit:)` delete the grammar line and call `config.model(prefix)`. Keep `idEnumGrammar(ids:)` as it is; a later task renames it.
- `Sources/FoundationModelsRanker/Searcher.swift` — becomes `model: session`.
- `Tests/FoundationModelsRankerTests/Support/ScriptedAgentSession.swift` — `RecordingSessionFactory.makeSession(instructions:grammar:)` becomes `makeSession(instructions:)`. Delete `receivedGrammarsBox` and `receivedGrammars`.
- `Tests/FoundationModelsRankerTests/LanguageModelSessionSupportTests.swift` — call `config.model("selection guidance")`.
- `Tests/FoundationModelsRankerTests/SelectionTests.swift` — delete `cachedRootSessionIsConstrainedToTheWholeCatalogsIdEnumGrammar`.
- `Tests/FoundationModelsRankerTests/OverBudgetTests.swift` — delete `overBudgetSessionIsConstrainedToOnlyTheTopMCandidatesIDEnumGrammar...`.

## Acceptance Criteria

- [x] `SelectionConfig.model` has the type `@Sendable (String) -> any AgentSession`.
- [x] `Sources/FoundationModelsRanker/Selection/SelectionConfig.swift` has no `import FoundationModelsRouter`.
- [x] `grep -rn "Grammar" Sources/FoundationModelsRanker/Selection/SelectionConfig.swift` finds nothing.
- [x] `swift build` gives no error.

## Tests

- [x] Update `Tests/FoundationModelsRankerTests/SelectionTests.swift`: the test that the cached root session gets the assembled prefix must call `factory.receivedInstructions` and must not mention a grammar.
- [x] Update `Tests/FoundationModelsRankerTests/OverBudgetTests.swift`: the test that the one-off session gets only the top-M candidate blocks must assert on the instructions text alone.
- [x] Add a test to `Tests/FoundationModelsRankerTests/SelectionTests.swift`: when the session returns an id that is not in the catalog, `search(intent:limit:)` drops that id and reports `.unknownSelectedId`. This test proves the backstop that replaces the grammar. A test of this shape may exist; extend it if it does.
- [x] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.