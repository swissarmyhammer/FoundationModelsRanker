---
assignees:
- claude-code
depends_on:
- 01M16WX5MP7ZGBX1GFYT6NJV14
position_column: todo
position_ordinal: '8780'
title: Add a Searcher initializer that takes one AgentSession
---
## What

`Searcher.init` takes `session: (@Sendable (String) -> any AgentSession)?`. Add an overload that takes `session: any AgentSession` so a caller who already holds a `LanguageModelSession` can pass it straight in. This is the stand-alone front door the change is for.

Files to change:

- `Sources/FoundationModelsRanker/Searcher.swift`:
  - Extract the shared body of the current `init` into a `private init(items:embedder:sessionSource:weights:preamble:candidateLimit:mode:onDiagnostic:)` that takes a `SelectionSessionSource?`. Both public initializers call it. Do not copy the body.
  - The current public `init` keeps its exact signature, including the `session:` default of `Searcher.defaultSessionFactory`. It passes `.factory(...)`.
  - Add `public init<Item: Searchable>(_ items: [Item], embedder: (any TextEmbedding)? = nil, session: any AgentSession, weights: SignalWeights = SignalWeights(), preamble: String = .selectionDefault, candidateLimit: Int = SelectionConfig.defaultCandidateLimit, mode: Mode = .auto, onDiagnostic: @escaping @Sendable (RankDiagnostic) -> Void = { _ in }) async throws`. It passes `.session(session)`.
  - Update the type doc comment at lines 36-44. Remove the mention of `RoutedAgentSession` at line 41 and at line 118.
  - Add a note that the instance form shares one transcript across calls, because `LanguageModelSession.fork()` returns `self`. Tell the caller to use the factory form when a fresh context per call matters.

Watch the overload resolution. `Searcher(items, session: someSession)` and `Searcher(items, session: someClosure)` must both compile without a type annotation at the call site. Write a test for each.

## Acceptance Criteria

- [ ] `try await Searcher(items, session: LanguageModelSession(model: .default, instructions: "..."))` compiles and runs.
- [ ] `try await Searcher(items)` still uses `Searcher.defaultSessionFactory` and behaves as before.
- [ ] `try await Searcher(items, session: nil)` still leaves selection unavailable and `mode: .selection` still throws `SelectionTierUnavailable`.
- [ ] No initializer body is duplicated.

## Tests

- [ ] Add to `Tests/FoundationModelsRankerTests/SearcherTests.swift`: the instance form ranks and selects against a `ScriptedAgentSession`, and the returned matches carry the real fused `score` and `signals`.
- [ ] Add a test that the closure form and the `nil` form still resolve to the right overload with no type annotation at the call site.
- [ ] Add a test that both forms give the same matches for the same scripted answer, so the two front doors agree.
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.