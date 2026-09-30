---
comments:
- actor: claude-code
  id: 01m3r02hhfn3jg3bz2pefx8456
  text: |-
    Research:
    - The README has no factory example now (commit 95da5f4 made it a landing page). The factory examples are in docs/GUIDE.md "Sessions". I will update GUIDE.md, and the README sentence about `session:`.
    - SelectionTier is an actor. When cachedRootSession() awaits an async factory, the actor can re-enter. Two concurrent first searches would then call the factory two times. To keep "one await for the cached root", the tier will cache a Task for the root, and clear it when the factory throws, so that a later search tries again.
    - Callers outside the card's list that must change: Examples/FullMontyCore/Demo.swift (its `session:` parameter gets `Searcher.defaultSessionFactory`, which becomes async throws), and the tests that call a stored factory directly (SelectionConfigTests, LanguageModelSessionSupportTests) need `try await`.
    - A sync closure converts to an async throws function type, so existing sync factories (`{ _ in session }`, `factory.makeSession`) still compile.
  timestamp: 2026-09-30T01:50:10.479703+00:00
- actor: claude-code
  id: 01m3r0bavgfmv5ysrpahjq1ev3
  text: |-
    Implementation landed (not committed, not pushed).
    - RED 1: the new tests did not compile, because the factory type was synchronous and could not throw.
    - GREEN 1: `SelectionSessionSource.factory`, `SelectionConfig.init(model:)`, `Searcher.init(_:embedder:session:...)` and `Searcher.defaultSessionFactory` take `@Sendable (String) async throws -> any AgentSession`. The two tier call sites use `try await`.
    - RED 2 (found by test, not by the card): with only that change, two overlapping first searches awaited the factory 2 times (actor re-entry). Test `anAsyncFactoryIsAwaitedOneTimeForTheCachedRootWhenSearchesOverlap` failed with count 2.
    - GREEN 2: the tier caches `rootSessionTask: Task<any AgentSession, any Error>?`. Overlapping searches await the same task. A factory error clears the task, so the next search asks the factory again (test `aSearchAfterAFactoryErrorAwaitsTheFactoryAgain`). `deinit` cancels the task.
    - Callers outside the card's list: `Examples/FullMontyCore/Demo.swift` `runFullMontyDemo(session:)` takes the async throwing type (it receives `Searcher.defaultSessionFactory`). SelectionConfigTests and LanguageModelSessionSupportTests now `try await` the stored factory.
    - Docs: the factory examples live in `docs/GUIDE.md` (the README is a landing page now). GUIDE.md has a new pooled-model block; README.md names the async factory in one sentence. `ReadmeExampleTests.sessionClosureThatAwaitsAModelPoolAnswersSelection` pins the new guide block (it passed on its first run, because the feature was already in place; it is a doc-shape pin, and the behavior tests above failed first).
    - Open: "CI is green on the pushed commit" is a user step (push was not done by instruction).
  timestamp: 2026-09-30T01:54:58.544413+00:00
- actor: claude-code
  id: 01m3r0bdkrkzntknkzmqht217m
  text: |-
    ### implement — changed
    - evidence: `swift test` 292 tests in 22 suites passed, 0 failures, 0 warnings; `swift build --build-tests --package-path IntegrationTests` complete. 14 files — Sources/FoundationModelsRanker/Selection/SelectionConfig.swift, Sources/FoundationModelsRanker/Selection/SelectionTier.swift, Sources/FoundationModelsRanker/Searcher.swift, Examples/FullMontyCore/Demo.swift, README.md, docs/GUIDE.md, Tests/FoundationModelsRankerTests/{SelectionTests,OverBudgetTests,SearcherTests,ReadmeExampleTests,SelectionConfigTests,LanguageModelSessionSupportTests}.swift, Tests/FoundationModelsRankerTests/Support/ScriptedAgentSession.swift
    - next: /review. The push and the "CI is green" item stay open for the user.
  timestamp: 2026-09-30T01:55:01.368774+00:00
- actor: claude-code
  id: 01m3r0ennbgntv2f45r50ncg23
  text: |-
    ### test — green
    - evidence: `swift test` gave 292 tests in 22 suites, all passed. `swift test --package-path IntegrationTests` gave 5 tests in 5 suites, all passed.
    - The saved output has no warning, no error, no failure, and no skipped test.
    - No file was changed in this step.
    - next: review.
  timestamp: 2026-09-30T01:56:47.915118+00:00
position_column: doing
position_ordinal: '80'
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
- [x] A factory can `await` and `throw`; an error from the factory comes out of `search`.
- [x] The factory is awaited one time for the cached root and one time for each over-budget run.
- [x] A synchronous closure still compiles as a factory.
- [ ] CI is green on the pushed commit.

## Tests
- [x] `Tests/FoundationModelsRankerTests/` selection tests: an async factory with a delay is awaited for the root and for each run; a throwing factory makes `search` throw.
- [x] A `Searcher` facade test with an async `session:` closure.
- [x] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #model-pool