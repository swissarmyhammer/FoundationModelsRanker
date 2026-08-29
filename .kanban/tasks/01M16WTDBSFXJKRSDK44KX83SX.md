---
assignees:
- claude-code
depends_on:
- 01M17004BEPEN2YVD6MG69HYYC
position_column: todo
position_ordinal: '80'
title: Remove the Grammar argument from the selection session seam
---
## What

`SelectionConfig.model` has the type `@Sendable (String, Grammar) -> any AgentSession`. `Grammar` is a `FoundationModelsRouter` type. Change the type to `@Sendable (String) -> any AgentSession`. This removes the Router type from the public selection API.

No caller loses behavior. `Searcher.swift:165` already ignores the grammar (`{ instructions, _ in session(instructions) }`). `Examples/FullMontyCore/LiveRouter.swift:106` builds one grammar for the whole catalog and reuses it for every call. The per-call grammar of the over-budget path is thus dead code today.

Files to change:

- `Sources/FoundationModelsRanker/Selection/SelectionConfig.swift` — change the `model` property (line 55) and the `init` parameter (line 82) to one argument. Delete `import FoundationModelsRouter` (line 23). Delete the file-header paragraph (lines 9-21) that explains the per-call grammar. Write a new paragraph. The new paragraph must say that a guided caller applies its own grammar when it makes the session, and that `SelectionTier.idEnumSchema(ids:)` supplies the id set.
- `Sources/FoundationModelsRanker/Selection/SelectionTier.swift` — in `cachedRootSession()` delete line 167 and call `config.model(assembledPrefix)`. In `overBudgetSearch(intent:limit:)` delete line 209 and call `config.model(prefix)`. Keep `idEnumGrammar(ids:)` as it is; a later task renames it.
- `Sources/FoundationModelsRanker/Searcher.swift` — line 165 becomes `model: session`.
- `Tests/FoundationModelsRankerTests/Support/ScriptedAgentSession.swift` — `RecordingSessionFactory.makeSession(instructions:grammar:)` becomes `makeSession(instructions:)`. Delete `receivedGrammarsBox` (line 171) and `receivedGrammars` (line 187).
- `Tests/FoundationModelsRankerTests/LanguageModelSessionSupportTests.swift:47` — call `config.model("selection guidance")`.
- `Tests/FoundationModelsRankerTests/SelectionTests.swift` — delete `cachedRootSessionIsConstrainedToTheWholeCatalogsIdEnumGrammar` (line 381).
- `Tests/FoundationModelsRankerTests/OverBudgetTests.swift` — delete `overBudgetSessionIsConstrainedToOnlyTheTopMCandidatesIDEnumGrammar...` (line 347).

## Acceptance Criteria

- [ ] `SelectionConfig.model` has the type `@Sendable (String) -> any AgentSession`.
- [ ] `Sources/FoundationModelsRanker/Selection/SelectionConfig.swift` has no `import FoundationModelsRouter`.
- [ ] `grep -rn "Grammar" Sources/FoundationModelsRanker/Selection/SelectionConfig.swift` finds nothing.
- [ ] `swift build` gives no error.

## Tests

- [ ] Update `Tests/FoundationModelsRankerTests/SelectionTests.swift`: the test that the cached root session gets the assembled prefix must call `factory.receivedInstructions` and must not mention a grammar.
- [ ] Update `Tests/FoundationModelsRankerTests/OverBudgetTests.swift`: the test that the one-off session gets only the top-M candidate blocks must assert on the instructions text alone.
- [ ] Add a test to `Tests/FoundationModelsRankerTests/SelectionTests.swift`: when the session returns an id that is not in the catalog, `search(intent:limit:)` drops that id and reports `.unknownSelectedId`. This test proves the backstop that replaces the grammar. A test of this shape may exist; extend it if it does.
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.