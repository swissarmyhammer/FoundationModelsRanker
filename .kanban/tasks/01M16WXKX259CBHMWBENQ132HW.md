---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m178xcwqzk93dqtkdwrpkkrd
  text: |-
    Research done. Findings:

    - `SelectionSessionSource` (in `Selection/SelectionConfig.swift`) has `.factory(@Sendable (String) -> any AgentSession)` and `.session(any AgentSession)`. `SelectionConfig` has two public inits (`model:` -> `.factory`, `session:` -> `.session`) that both delegate to one `private init(sessionSource:...)`. That private init is NOT visible to `Searcher`, so `Searcher` must map its `SelectionSessionSource` to a `SelectionConfig` with a switch over the two public inits.
    - `SelectionTier` already handles both sources: `cachedRootSession()` makes a session from the prefix for `.factory`, or takes the supplied session for `.session`; `prompt(prefix:intent:)` puts the prefix in the prompt only for `.session`; the over-budget path forks the supplied session.
    - Overload resolution: the new overload takes a NON-optional `any AgentSession`, so `nil` cannot bind to it (`any AgentSession` is not `ExpressibleByNilLiteral`) and stays unambiguous on the closure overload alone. A closure literal cannot bind to `any AgentSession` (function types conform to no protocol), and a class instance cannot bind to a function type, so all three call shapes resolve with no annotation.
    - `LanguageModelSession(model:instructions:)` construction needs no GPU (see `LanguageModelSessionSupportTests`), so an acceptance test can build a `Searcher` with a real `LanguageModelSession` in `.retrieval` mode with no live inference.
    - `ScriptedAgentSession.fork()` returns `self` and counts forks, so it can stand in for the instance form directly.
  timestamp: 2026-08-29T17:26:10.071717+00:00
- actor: claude-code
  id: 01m1798vy0aezw2k1c47ypxkx2
  text: |-
    Implementation landed (TDD).

    RED: added five tests to `Tests/FoundationModelsRankerTests/SearcherTests.swift` first and ran `swift build --build-tests`. Every new test failed with `cannot convert value of type 'ScriptedAgentSession'/'LanguageModelSession' to expected argument type '@Sendable (String) -> any AgentSession'` -- the right failure, because the instance overload did not exist.

    GREEN: `Sources/FoundationModelsRanker/Searcher.swift` now has
    - `private init(items:embedder:sessionSource:weights:preamble:candidateLimit:mode:onDiagnostic:)` that holds the whole body once. Both public initializers delegate to it with `try await self.init(...)`; no body is copied.
    - the unchanged public factory initializer, which maps `session.map { SelectionSessionSource.factory($0) }`.
    - the new public `init(_:embedder:session:weights:preamble:candidateLimit:mode:onDiagnostic:)` that takes `session: any AgentSession` and passes `.session(session)`.
    - `private static func selectionConfig(sessionSource:preamble:candidateLimit:)`, which picks the matching public `SelectionConfig` initializer, because `SelectionConfig`'s own source-taking initializer is private.

    Overload resolution needed no tie-break work. The new overload takes a NON-optional `any AgentSession`, so `nil` cannot bind to it and stays unambiguous on the closure overload alone. A closure literal cannot bind to `any AgentSession` (a function type conforms to no protocol) and a class instance cannot bind to a function type. All three shapes compile with no type annotation, which the new test `everySessionArgumentShapeResolvesWithNoTypeAnnotationAtTheCallSite` shows.

    Doc comments: the `Searcher` type doc now describes the two front doors and carries the shared-transcript note (`LanguageModelSession.fork()` gives back `self`, the SDK has no branch primitive, use the factory form for a fresh context each call). The wording matches `Selection/LanguageModelSessionSupport.swift`'s own tradeoff paragraph. Both `session:` parameter docs were rewritten. `RoutedAgentSession` was already gone from this file (an earlier card removed it); the only remaining mentions in the repository are in `README.md` and `plan.md`, which this card does not name.

    `swift build` clean, `swift test` 268 tests pass (263 before), zero failures and zero warnings.
  timestamp: 2026-08-29T17:32:25.920145+00:00
- actor: claude-code
  id: 01m179fnqf5zmnqc62q6p1y2r1
  text: |-
    Rule check before reporting. `dump validators` gave 7 validators / 55 rules for `.swift`. The two changed files were linted with the swift validator's own swiftlint configuration (`no_magic_numbers` with `allowed_numbers: [0, 1, -1, 100]`, `missing_docs` with `warning: [open, public]`, `function_body_length` and `closure_body_length` at 250): **0 violations, 0 serious in 2 files**. The repository has no `.swiftlint.yml`, so nothing is excluded and both files were really read.

    Notes on the rules that could touch this change:
    - `code-hygiene/data-driven`: the new `switch sessionSource` has arms that differ in behavior (each calls a different `SelectionConfig` initializer), and it is an exhaustive Swift switch over an enum with no `default:`. That is the rule's own carve-out.
    - `duplication/swift`: the two public initializer bodies are forwarding shims into the one extracted private initializer. They hold no logic that can drift, and two overloads cannot share one body in Swift.
    - `code-hygiene/dead-code-swift`: every symbol added is referenced -- the private initializer by both public initializers, `selectionConfig(sessionSource:preamble:candidateLimit:)` by the private initializer, and the new initializer is `public`, so periphery retains it.
    - `completeness/public-output-contract`: the change only ADDS a public declaration, which is the declaration this card asks for. No existing signature, default, message, or severity changed.
    - `test-integrity`: no test is skipped, empty, or without an assertion; every new test asserts real behavior through the public front doors. No environment variable selects anything.

    README work for the new front door is NOT missing here: card ^jdw7sf0 ("Rewrite the README for a package with no dependencies") already owns it and names the one-session example. This card's file list stops at `Searcher.swift` and its tests.

    ### implement — changed
    - evidence: 2 files -- `Sources/FoundationModelsRanker/Searcher.swift` (new public `session: any AgentSession` initializer, one shared private `sessionSource:` initializer both public initializers delegate to, `selectionConfig(sessionSource:preamble:candidateLimit:)` helper, type doc and both `session:` parameter docs rewritten with the shared-transcript note), `Tests/FoundationModelsRankerTests/SearcherTests.swift` (5 new tests). `swift build` clean; `swift test` 268 passed, 0 failed, 0 warnings (263 before). swiftlint with the validator configuration: 0 violations.
    - next: /review
  timestamp: 2026-08-29T17:36:08.943317+00:00
depends_on:
- 01M16WX5MP7ZGBX1GFYT6NJV14
position_column: doing
position_ordinal: '80'
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

- [x] `try await Searcher(items, session: LanguageModelSession(model: .default, instructions: "..."))` compiles and runs.
- [x] `try await Searcher(items)` still uses `Searcher.defaultSessionFactory` and behaves as before.
- [x] `try await Searcher(items, session: nil)` still leaves selection unavailable and `mode: .selection` still throws `SelectionTierUnavailable`.
- [x] No initializer body is duplicated.

## Tests

- [x] Add to `Tests/FoundationModelsRankerTests/SearcherTests.swift`: the instance form ranks and selects against a `ScriptedAgentSession`, and the returned matches carry the real fused `score` and `signals`.
- [x] Add a test that the closure form and the `nil` form still resolve to the right overload with no type annotation at the call site.
- [x] Add a test that both forms give the same matches for the same scripted answer, so the two front doors agree.
- [x] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.