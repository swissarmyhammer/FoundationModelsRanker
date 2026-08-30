---
assignees:
- claude-code
depends_on:
- 01M19ACG799X8YF41B4BA0C6FV
position_column: todo
position_ordinal: '8380'
title: Cover LanguageModelSession's plain respond(to:) with a real model
---
## What

`Sources/FoundationModelsRanker/Selection/LanguageModelSessionSupport.swift:42-44`

Coverage: 66.7% (6/9 lines) measured with the real model running. Uncovered lines: 42-44.

```swift
public func respond(to prompt: String) async throws -> String {
    try await respond(to: prompt).content    // 42-44 — uncovered
}
```

This is the `LanguageModelSession: AgentSession` conformance's plain-text method. Running the real-model test covers the OTHER override, `respond(to:generating:)` at lines 67-69, because the existing real-model test drives guided generation. Nothing drives the plain path.

That matters because the two overrides do different things. `respond(to:generating:)` uses the session's native constrained decoding; `respond(to:)` returns free text and is what `AgentSession`'s DEFAULT `respond(to:generating:)` calls for any conformer that does not override it. A break in the plain path would go unnoticed today.

## Where the test goes

Task `^ba0c6fv` moves the real-model tests into a nested `IntegrationTests` package, and deletes the `FOUNDATIONMODELSRANKER_INTEGRATION_TESTS` env gate. Put this test in that package, at `IntegrationTests/Tests/FoundationModelsRankerIntegrationTests/`. Do NOT add an `.enabled(if:)` trait and do NOT reintroduce an env var — selection is structural, by package boundary.

The CI runner is a Mac mini that runs Apple Intelligence, and task `^qqzgp0d` turns the integration job on, so this test really runs in CI.

## Acceptance Criteria

- [ ] A test in the nested integration package drives `LanguageModelSession.respond(to:)` through the `AgentSession` seam — held as `any AgentSession`, so the protocol witness is what runs, not a direct call.
- [ ] `swift test --package-path IntegrationTests` covers `LanguageModelSessionSupport.swift:42-44`. Confirm by re-running coverage over that package, not by inspection.
- [ ] The root `swift test` is unchanged in count and still passes.
- [ ] No production code changes. Tests only.

## Tests

- [ ] In the nested package: hold a `LanguageModelSession` as `any AgentSession`, call `respond(to:)`, and assert the result is non-empty text.
- [ ] The prompt asks for plain prose with no `Generable` type involved, so the plain path is what ran rather than the guided override.
- [ ] Report the coverage figure for `LanguageModelSessionSupport.swift` before and after, in the step record.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.