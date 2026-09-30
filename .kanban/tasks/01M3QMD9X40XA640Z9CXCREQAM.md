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
- actor: claude-code
  id: 01m3r0v1xexpyzp0npc62gkkmg
  text: |-
    ### review — findings
    - evidence: `review sha HEAD~1..HEAD` (checkpoint cef362b). 2 findings, 2 confirmed, 0 refuted. Tests/FoundationModelsRankerTests/SelectionTests.swift:118 (swift/initialization), Tests/FoundationModelsRankerTests/Support/ScriptedAgentSession.swift:193 (code-hygiene/magic-numbers-swift).
    - next: Correct the 2 open findings in the "Review Findings (2026-09-29 19:57)" section. Then do the review again. The CI item needs a push. The push is a step for the user. The review does not record the push as a finding.
  timestamp: 2026-09-30T02:03:33.678191+00:00
- actor: claude-code
  id: 01m3r0vfq1v21epkwyf6f8e8f0
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 13 files
    - test: green — swift test, 292 passed; IntegrationTests, 5 passed
    - commit: cef362b
    - review: findings — Tests/FoundationModelsRankerTests/SelectionTests.swift:118, Tests/FoundationModelsRankerTests/Support/ScriptedAgentSession.swift:193
  timestamp: 2026-09-30T02:03:47.809051+00:00
- actor: claude-code
  id: 01m3r0y8mn2akxd9471emvnd3r
  text: |-
    Review findings corrected (not committed, not pushed).
    - SelectionTests.swift: the factory closure of `aSearchAfterAFactoryErrorAwaitsTheFactoryAgain` now calls the new `private static func sessionAfterAFirstFailure(callCount:session:)`. The `if` is in that method. A scan of the whole file found no other callback closure that branches.
    - ScriptedAgentSession.swift: `RecordingSessionFactory.delay` is now `.milliseconds(delayMilliseconds)`, with the new `static let delayMilliseconds = 20`. `swiftlint lint` with `only_rules: [no_magic_numbers]` and `allowed_numbers: [0, 1, -1, 100]` found 1 violation in the file before the change and 0 after. It also found 0 in SelectionTests.swift.
    - The project has no `.swiftlint.yml`. To do the magic-number check again, use a temporary config with the rule settings above.
  timestamp: 2026-09-30T02:05:18.869570+00:00
- actor: claude-code
  id: 01m3r0yakpdqqy4hcmxy9413r0
  text: |-
    ### implement — changed
    - evidence: 2 files — Tests/FoundationModelsRankerTests/SelectionTests.swift, Tests/FoundationModelsRankerTests/Support/ScriptedAgentSession.swift. `swift test`: 292 tests in 22 suites passed, 0 failures, 0 warnings. swiftlint no_magic_numbers: 0 violations. Both findings are checked.
    - next: /review. The push and the "CI is green" item stay open for the user.
  timestamp: 2026-09-30T02:05:20.886532+00:00
- actor: claude-code
  id: 01m3r118p1nke235ef0fc7w5tz
  text: |-
    ### test — green
    - evidence: `swift test` — 292 tests in 22 suites passed, 0 failed, 0 skipped, 0 warnings. `swift test --package-path IntegrationTests` — 5 tests in 5 suites passed, 0 failed, 0 skipped, 0 warnings.
    - next: review
  timestamp: 2026-09-30T02:06:57.217751+00:00
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

## Review Findings (2026-09-29 19:57)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 11 file(s) reviewed, 6 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

> 2 file(s) not reviewed — no validator matched:
> - `README.md` — no validator matches this file
> - `docs/GUIDE.md` — no validator matches this file

- [x] `Tests/FoundationModelsRankerTests/SelectionTests.swift:118` `swift/initialization` — A callback closure that branches (contains an `if` statement) should extract its logic to a named method. The factory closure accepts branching logic inline, which makes it harder to test and understand the factory behavior separately. Extract the branching logic into a named test helper method and have the factory closure simply call that method. For example: `private func makeSessionOrThrow() throws -> any AgentSession { if factoryCallCount.increment() == 1 { throw SessionFactoryError() } return session }` and then `model: { _ in try self.makeSessionOrThrow() }`.
- [x] `Tests/FoundationModelsRankerTests/Support/ScriptedAgentSession.swift:193` `code-hygiene/magic-numbers-swift` — Magic numbers should be replaced by named constants.
