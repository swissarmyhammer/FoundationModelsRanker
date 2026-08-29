---
assignees:
- claude-code
depends_on:
- 01M16WTDBSFXJKRSDK44KX83SX
position_column: todo
position_ordinal: '8680'
title: Let a caller supply one AgentSession instead of a session factory
---
## What

`SelectionConfig.model` is a factory: it takes the assembled candidate prefix and returns a new session seeded with that prefix as its instructions. A caller who already holds one `LanguageModelSession` must wrap it in a closure, and that closure must throw the prefix away, because a live session cannot take new instructions. The model then never sees the catalog.

Add a second way to supply the session. The prefix must reach the model on either way.

Add to `Sources/FoundationModelsRanker/Selection/SelectionConfig.swift`:

```swift
public enum SelectionSessionSource: Sendable {
    /// Makes a new session per prefix. The prefix becomes the session's
    /// instructions.
    case factory(@Sendable (String) -> any AgentSession)
    /// Reuses one session. The prefix rides on each prompt.
    case session(any AgentSession)
}
```

Replace the `model` property with `sessionSource: SelectionSessionSource`. Keep the existing `init(model:preamble:capacityCharacterLimit:candidateLimit:)` as a convenience that wraps its argument in `.factory`, so callers of the factory form need no change. Add a second `init` that takes `session: any AgentSession`.

Change `Sources/FoundationModelsRanker/Selection/SelectionTier.swift` so both paths honour the source:

- `.factory(f)` — as today. Session is `f(prefix)`. The prompt is the intent alone.
- `.session(s)` — the session is `try await s.fork()`. The prompt is the prefix, then a blank line, then `# Task`, then a blank line, then the intent.

Both `cachedRootSession()` and `overBudgetSearch(intent:limit:)` must use the same rule. Put the prompt assembly in one `private func prompt(prefix:intent:)` so the two paths cannot drift apart.

## Acceptance Criteria

- [ ] `SelectionConfig` has `sessionSource` and both initializers.
- [ ] The existing factory-form initializer keeps its signature, so no current caller breaks.
- [ ] With `.session`, the model receives the preamble and every candidate summary block in the prompt.
- [ ] With `.factory`, the prompt is the intent alone, exactly as today.
- [ ] `swift build` gives no error.

## Tests

- [ ] Add to `Tests/FoundationModelsRankerTests/SelectionTests.swift`: with `.session`, a `ScriptedAgentSession` records a prompt that holds the preamble, a candidate id, and the intent.
- [ ] Add a test that with `.session`, `SelectionTier` calls `fork()` once per `search(intent:limit:)` call and never makes a new session.
- [ ] Add to `Tests/FoundationModelsRankerTests/OverBudgetTests.swift`: over budget with `.session`, the prompt holds only the top-M candidate blocks, not the whole catalog.
- [ ] Add a test that with `.factory` the prompt is still the intent alone, so the current path does not change.
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.