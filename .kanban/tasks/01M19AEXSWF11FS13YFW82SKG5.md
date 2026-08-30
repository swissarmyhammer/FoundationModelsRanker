---
assignees:
- claude-code
depends_on:
- 01M19ACG799X8YF41B4BA0C6FV
position_column: todo
position_ordinal: '8480'
title: Cover the zero-config default on-device path end to end
---
## What

Two uncovered regions, one cause — nothing ever runs the package's own advertised default path.

`Sources/FoundationModelsRanker/Searcher.swift:101-103` — 96.0% (120/125). Uncovered: 101-103.

```swift
public static let defaultSessionFactory: @Sendable (String) -> any AgentSession = { instructions in
    LanguageModelSession(model: .default, instructions: instructions)   // uncovered
}
```

`Examples/FullMontyCore/Demo.swift` — 87.1% (54/62). Uncovered: 140, 166-169, 223-225, including `runDefaultDemo`.

`Searcher.defaultSessionFactory` is the default value of `Searcher.init`'s `session:` parameter. It is what `try await Searcher(items)` — the README's lead example, the package's front door — actually uses. Every existing test passes an explicit scripted session, so the real default has never executed in a test.

This is the path that was silently broken until commit `cbcee8c`: every query returned no matches because the assembled prefix showed the model no ids. That bug survived because nothing tested this path. A test here is the regression guard for it.

## Where each test goes

Task `^ba0c6fv` creates a nested `IntegrationTests` package and deletes the `FOUNDATIONMODELSRANKER_INTEGRATION_TESTS` env gate. Split this work by what each test needs:

- Needs the real model → `IntegrationTests/Tests/FoundationModelsRankerIntegrationTests/`. No `.enabled(if:)` trait, no env var; the package boundary selects.
  - the zero-config `Searcher(items)` test
  - the `runDefaultDemo` test
- Needs nothing → stays in the root unit target.
  - `Demo.swift:140`, the default `onDiagnostic` argument of `runEmbedderDemo`, uncovered because every caller passes one
  - `Demo.swift:223-225`, `printDiagnostic`, never called by a test

The CI runner is a Mac mini that runs Apple Intelligence, and task `^qqzgp0d` turns the integration job on, so the real-model half genuinely runs in CI.

## Acceptance Criteria

- [ ] A test in the nested package calls `try await Searcher(items)` with NO `session:` argument, so `defaultSessionFactory` constructs the session, and gets back at least one match.
- [ ] A test in the nested package calls `runDefaultDemo` and gets one result per demo query.
- [ ] `Searcher.swift:101-103` and `Demo.swift:166-169` are covered by the integration run; `Demo.swift:140` and `223-225` are covered by the root run. Confirm by re-running coverage over both, not by inspection.
- [ ] The root `swift test` still passes.
- [ ] No production code changes. Tests only.

## Tests

- [ ] Nested package: the zero-config `Searcher(items)` returns a match for a query whose answer is unambiguous in the fixture catalog, and reports NO `.unknownSelectedId` diagnostic. The absence of that diagnostic is the regression guard for the `cbcee8c` bug — state that in the test's comment.
- [ ] Nested package: `runDefaultDemo` returns one `FullMontyResult` per demo query.
- [ ] Root target: `runEmbedderDemo()` called with no argument, exercising its default `onDiagnostic`.
- [ ] Root target: `printDiagnostic` runs for every `RankDiagnostic` case without trapping.
- [ ] Report the counts of both runs in the step record.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.