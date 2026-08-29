---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m174h15e6a93gxg9ntccrsgy
  text: |
    Picked up. Research notes (line numbers on the card are stale after six commits; every symbol found by name):

    - `idEnumGrammar(ids:)` is in `Sources/FoundationModelsRanker/Selection/SelectionTier.swift`, under the `MARK: - Guided-generation grammar` section. `import FoundationModelsRouter` is the only Router reference left in `Sources/`. `AgentSession.swift` and `RoutedEmbedderAdapter.swift` no longer import Router, so this card makes `Sources/` fully Router-free.
    - The header doc of `SelectionTier` names `idEnumGrammar(ids:)`; it must become `idEnumSchema(ids:)`.
    - `SelectionConfig.swift` already names `SelectionTier.idEnumSchema(ids:)` twice (the file header and the `model` doc comment). That is a forward reference the previous card left on purpose. Keep it.
    - The four schema tests are in `SelectionTests.swift` under `MARK: - Grammar id-set contents`. Each one repeats the same seven-line JSON walk (data -> root -> properties -> ids -> items -> enum).
    - `Tests/.../Support/GrammarTestSupport.swift` has no caller. Its `enumIds(in:)` gives only the enum id set; two of the four tests need `uniqueItems` and `maxItems`, which live on the `ids` subschema, one level up.
    - `OverBudgetTests.swift` already has no `import FoundationModelsRouter`; only `SelectionTests.swift`, `SearcherTests.swift`, and `Support/ScriptedAgentSession.swift` still have it. The card lists the first two. `ScriptedAgentSession.swift` is out of this card's scope; task ^2q0p8gr (delete every external package dependency) covers it.
    - `README.md` still shows `SelectionTier.idEnumGrammar`; task ^jdw7sf0 (rewrite the README) covers it. `plan.md` also names `idEnumGrammar`; out of scope here.
    - Baseline `swift build` is green.
  timestamp: 2026-08-29T16:09:30.542812+00:00
- actor: claude-code
  id: 01m1754fknsym7k0xbabw3ydf1
  text: |
    Implementation landed. TDD order was kept: the tests went in first and the build failed with five `type 'SelectionTier' has no member 'idEnumSchema'` errors, which is the expected reason. Then the source change made them pass.

    Decisions a later agent should know:

    1. **The unused test helper was renamed and put back to work, not deleted.** `GrammarTestSupport.swift` had no caller after the previous card. It is now `Support/SelectionSchemaTestSupport.swift`, enum `SelectionSchemaTestSupport`. Deleting it was the other option, but keeping it is better: each of the four schema tests repeated the same JSON walk from the schema source down to `properties.ids`, and that repeat is what the duplication rule reports. The helper now has two functions, so it serves all four tests, not only two:
       - `idsSchema(in:)` returns the `properties.ids` subschema. The `uniqueItems` test and the `maxItems` test read their values from it.
       - `enumIds(in:)` builds on `idsSchema(in:)` and returns the `properties.ids.items.enum` id set. The "exactly the catalog ids" test and the "empty catalog" test use it.
       Both take a `String` schema source. The `guard case .jsonSchema` block and the Router import are gone. The file no longer needs `@testable import FoundationModelsRanker` either, because it now names no Ranker symbol; that import was removed as dead code. Parsing the schema and asserting on extracted values also keeps the tests free of `JSONSerialization`'s unstable key order.

    2. **`SelectionConfig.swift` was left as it is.** Its file header and its `model` doc comment both name `SelectionTier.idEnumSchema(ids:)`. That was a forward reference. The symbol now exists, so both lines read correctly. Verified, not deleted.

    3. **One wording choice.** The card asks the doc comment to tell a Router caller how to wrap the result. The instruction for this card also requires that `grep -rn "FoundationModelsRouter" Sources/` finds nothing. The doc comment says "A Router caller makes a grammar from the text: `Grammar.jsonSchema(SelectionTier.idEnumSchema(ids: ids))`". "Router" is the shorthand this repository already uses in doc comments. This satisfies both requirements.

    4. **Every schema rule is unchanged.** The `enum` on `properties.ids.items`, `uniqueItems`, and the `maxItems` cap all stay. The comment about the ~6150-token runaway stays word for word. Only the `.jsonSchema(...)` wrap was removed from the return.

    Out of scope, and left for the cards that own them:
    - `Tests/.../Support/ScriptedAgentSession.swift` still has `import FoundationModelsRouter`. The card does not list it. Task ^2q0p8gr (delete every external package dependency) covers it.
    - `README.md` still shows `SelectionTier.idEnumGrammar`. Task ^jdw7sf0 (rewrite the README) covers it.
    - `plan.md` still names `idEnumGrammar` in two places.

    Results: `swift build` complete, no error. `swift test` gives 255 tests in 21 suites, all passed (baseline was 254; the new JSON parse test is the one added). The only warning in the output is the pre-existing SwiftPM build-system line about the `mlx-swift_Cmlx.bundle` node, which the baseline run gives too.
  timestamp: 2026-08-29T16:20:07.925571+00:00
- actor: claude-code
  id: 01m1754mkbfz4fc9gyezep6tyw
  text: |
    ### implement — changed
    - evidence: 5 files — Sources/FoundationModelsRanker/Selection/SelectionTier.swift, Tests/FoundationModelsRankerTests/SelectionTests.swift, Tests/FoundationModelsRankerTests/SearcherTests.swift, Tests/FoundationModelsRankerTests/Support/GrammarTestSupport.swift -> Support/SelectionSchemaTestSupport.swift (git mv + rewrite). `swift build` complete, no error. `swift test`: 255 tests in 21 suites passed, 0 failed. `grep -rn "FoundationModelsRouter" Sources/` finds nothing.
    - next: /review
  timestamp: 2026-08-29T16:20:13.035096+00:00
- actor: claude-code
  id: 01m175hm452bfnmn3t905155km
  text: |
    ### test — green
    - evidence: `swift test` — 255 tests, 21 suites, all passed, 0 failures, 0 warnings, 0 unexpected skips (the one integration test gated by `FOUNDATIONMODELSRANKER_INTEGRATION_TESTS` stays off, as intended)
    - verified: `grep -rn "FoundationModelsRouter" Sources/` finds nothing; `swift run FullMonty --no-model` exit 0; `swift run FullMonty --embedder` exit 0 (only warning seen: the documented `mlx-swift` `Cmlx.bundle` "missing creator for mutated node" warning)
    - verified: `SelectionTier.idEnumSchema(ids:)` returns `String`; `idEnumGrammar` is gone from `Sources/`; `Tests/FoundationModelsRankerTests/Support/SelectionSchemaTestSupport.swift` exists with `idsSchema(in:)` and `enumIds(in:)`
    - noted, not fixed (out of scope, belongs to card `^2q0p8gr`): `Tests/FoundationModelsRankerTests/Support/ScriptedAgentSession.swift` still has an unused `import FoundationModelsRouter`
    - next: proceed to review
  timestamp: 2026-08-29T16:27:18.533885+00:00
- actor: claude-code
  id: 01m175zz6a6ry9wjw8xghcnagr
  text: |
    ### review — clean
    - scope: `review sha HEAD~1..HEAD` (commit `00da13c`), task-mode
    - evidence: zero new findings. counts: findings 0, confirmed 0, refuted 0, attempted 7, failed 0. 5 files reviewed; 6 `.kanban/` files excluded by `.reviewignore`.
    - verified: all three schema rules survive the return-type change. `itemsSchema["enum"] = ids`, `idsSchema["uniqueItems"] = true`, and `idsSchema["maxItems"] = ids.count` are all still emitted in `Sources/FoundationModelsRanker/Selection/SelectionTier.swift`. The comment that explains the ~6150-token runaway is intact word for word. The diff removes only the `.jsonSchema(...)` wrap from the return.
    - verified: the public doc tells a caller with a grammar-capable backend how to wrap the result -- "A Router caller makes a grammar from the text: `Grammar.jsonSchema(SelectionTier.idEnumSchema(ids: ids))`".
    - verified: all four schema tests in `Tests/FoundationModelsRankerTests/SelectionTests.swift` use `SelectionSchemaTestSupport`. `idEnumSchemaContainsExactlyTheCatalogsCurrentIds` and `idEnumSchemaReflectsAnEmptyCatalogAsAnEmptyEnum` use `enumIds(in:)`. `idEnumSchemaMarksIdsAsUniqueItems` and `idEnumSchemaBoundsIdsWithMaxItemsAtTheCandidateCount` use `idsSchema(in:)`. No test stopped asserting what it asserted before the rename: the id-set test keeps `== Set(Self.catalog.ids)`, the empty-catalog test keeps the empty check, the `uniqueItems` test keeps `== true`, and the `maxItems` test keeps `== Self.catalog.ids.count` with its explanatory comment. The fifth test, `idEnumSchemaIsWellFormedJson`, parses the text itself, which is correct, because the helper would pass through the parse step it must assert on.
    - noted, not a finding: three tool rules declined `Tests/FoundationModelsRankerTests/Support/GrammarTestSupport.swift`, because the rename deleted that path. This is the expected result of a `git mv` in a diff scope. The new file `Support/SelectionSchemaTestSupport.swift` was reviewed.
    - next: task moved to `done`
  timestamp: 2026-08-29T16:35:08.618396+00:00
- actor: claude-code
  id: 01m1760z71xt846rhe3fqdx5jc
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 5 files; idEnumSchema(ids:) returns String, GrammarTestSupport renamed to SelectionSchemaTestSupport with a split walk, 1 new JSON parse test
    - test: green — swift test, 255 passed, 0 failed, 0 warnings; both FullMonty paths exit 0
    - commit: 00da13c — 11 files changed, 230 insertions, 122 deletions
    - review: clean — zero findings; every schema rule survives, including the load-bearing maxItems cap and its comment
    - next: none — task is in done

    Milestone: `grep -rn "FoundationModelsRouter" Sources/` now finds nothing. The library target no longer references FoundationModelsRouter at all.
  timestamp: 2026-08-29T16:35:41.409532+00:00
depends_on:
- 01M16WTDBSFXJKRSDK44KX83SX
position_column: done
position_ordinal: '9980'
title: Change idEnumGrammar to idEnumSchema and return a JSON Schema String
---
## What

`SelectionTier.idEnumGrammar(ids:)` returns `Grammar`, a `FoundationModelsRouter` type. It is the last Router reference in `SelectionTier.swift`. Change the function to return the JSON Schema source string, and rename it.

The body already builds the schema as a string and then wraps it in `.jsonSchema(...)` at line 61 of the `idEnumGrammar` block. Delete only the wrap. Keep every schema rule: the `enum` on `properties.ids.items`, `uniqueItems`, and the `maxItems` cap. Keep `SelectionSchemaShapeError`.

The function stays `public`. A `FoundationModelsRouter` caller wraps the result: `Grammar.jsonSchema(SelectionTier.idEnumSchema(ids: ids))`. Say this in the doc comment.

Files to change:

- `Sources/FoundationModelsRanker/Selection/SelectionTier.swift` — rename `idEnumGrammar(ids:)` to `idEnumSchema(ids:)`. Change the return type to `String`. Return `String(decoding: constrained, as: UTF8.self)`. Delete `import FoundationModelsRouter` (line 10). Update the doc comments of the function, of `SelectionSchemaShapeError`, and the type header at line 46.
- `Tests/FoundationModelsRankerTests/Support/GrammarTestSupport.swift` — `enumIds(in:)` takes a `String` schema source, not a `Grammar`. Delete the `guard case .jsonSchema` block and `import FoundationModelsRouter`. Rename the file to `SelectionSchemaTestSupport.swift` and the enum to `SelectionSchemaTestSupport`.
- `Tests/FoundationModelsRankerTests/SelectionTests.swift` — the four schema tests at lines 303, 321, 337, and 361 call `idEnumSchema(ids:)`. Delete `import FoundationModelsRouter` (line 2).
- `Tests/FoundationModelsRankerTests/SearcherTests.swift:2` and `Tests/FoundationModelsRankerTests/OverBudgetTests.swift:2` — delete `import FoundationModelsRouter`.

## Acceptance Criteria

- [x] `SelectionTier.idEnumSchema(ids:)` returns `String` and `idEnumGrammar` no longer exists.
- [x] `grep -rn "FoundationModelsRouter" Sources/` finds only `AgentSession.swift` and `RoutedEmbedderAdapter.swift`. Other tasks delete those. — Those two files lost their imports in earlier cards, so the grep now finds nothing at all in `Sources/`.
- [x] `swift build` gives no error.

## Tests

- [x] The four renamed tests in `Tests/FoundationModelsRankerTests/SelectionTests.swift` keep their assertions: the schema holds exactly the catalog ids, it marks `uniqueItems`, it bounds `maxItems` at the candidate count, and an empty catalog gives an empty `enum`.
- [x] Add a test that `idEnumSchema(ids:)` returns text that `JSONSerialization.jsonObject(with:)` reads without an error.
- [x] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.
