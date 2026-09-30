---
position_column: todo
position_ordinal: '8180'
title: Async session factory for the selection tier and the Searcher facade
---
## What
A session can come from a pooled model that loads at the first request, so the factory must be able to `await` and `throw`.

```swift
SelectionConfig(model: { instructions in try await qwen.session(instructions: instructions) })
Searcher(catalog, embedder: e, session: { instructions in try await qwen.session(instructions: instructions) })
```

- `Sources/FoundationModelsRanker/Selection/SelectionConfig.swift`: `init(model: @escaping @Sendable (String) async throws -> any AgentSession, …)`; `SelectionSessionSource.factory` stores that type.
- `Sources/FoundationModelsRanker/Selection/SelectionTier.swift`: the two call sites (around lines 213 and 304) become `try await makeSession(…)`.
- `Sources/FoundationModelsRanker/Searcher.swift`: the public `init(_:embedder:session:…)` parameter `session` and `Searcher.defaultSessionFactory` take the async throwing type; line ~300 passes it on (it does not call it).
- `README.md`: the factory examples.
- Push to `origin main` when green.

## Acceptance Criteria
- [ ] A factory can `await` and `throw`; an error from the factory comes out of `search`.
- [ ] The factory is awaited one time for the cached root and one time for each over-budget run.
- [ ] A synchronous closure still compiles as a factory.
- [ ] CI is green on the pushed commit.

## Tests
- [ ] `Tests/FoundationModelsRankerTests/` selection tests: an async factory with a delay is awaited for the root and for each run; a throwing factory makes `search` throw.
- [ ] A `Searcher` facade test with an async `session:` closure.
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #model-pool