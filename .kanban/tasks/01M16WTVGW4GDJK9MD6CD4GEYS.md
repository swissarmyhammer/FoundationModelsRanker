---
assignees:
- claude-code
depends_on:
- 01M16WTDBSFXJKRSDK44KX83SX
position_column: todo
position_ordinal: '8180'
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

- [ ] `SelectionTier.idEnumSchema(ids:)` returns `String` and `idEnumGrammar` no longer exists.
- [ ] `grep -rn "FoundationModelsRouter" Sources/` finds only `AgentSession.swift` and `RoutedEmbedderAdapter.swift`. Other tasks delete those.
- [ ] `swift build` gives no error.

## Tests

- [ ] The four renamed tests in `Tests/FoundationModelsRankerTests/SelectionTests.swift` keep their assertions: the schema holds exactly the catalog ids, it marks `uniqueItems`, it bounds `maxItems` at the candidate count, and an empty catalog gives an empty `enum`.
- [ ] Add a test that `idEnumSchema(ids:)` returns text that `JSONSerialization.jsonObject(with:)` reads without an error.
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.