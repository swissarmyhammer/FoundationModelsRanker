---
comments:
- actor: claude-code
  id: 01m3raqtshbn9c87xvd85bre0k
  text: |-
    Research done.
    - Extras origin/main and the local checkout are at 5e6fe7c. PooledSession has `respond(to:) -> String` and `respond(to:generating:) -> T` with the same signatures as the AgentSession requirements, so Swift uses them as the witnesses. A second declaration in the extension is an invalid redeclaration. Only `fork()` needs a forward, because PooledSession.fork() returns `PooledSession`, not `any AgentSession`.
    - PooledEmbedder has `embed(texts:)` and no `dimension`. The extension forwards `embed(_:)` to it.
    - The executor request of a stub LanguageModel carries `schema`, so a test can prove that guided output goes through the native schema path and not through the text-decode default.
    - Two old tests contradict the card: `PackageTests.theManifestDeclaresNoPackageDependency` (it fails when the manifest has `.package(`) and `ReadmeExampleTests.theReadmeNamesNoRemovedDependency` (its premise "depends on nothing now" becomes false). The user memory says: do not keep tests that keep a dependency absent. These two go. The prose that says "no package dependency" (Package.swift, IntegrationTests/Package.swift, README.md, AgentSession.swift, TextEmbedding.swift) is updated.
    - Package.resolved is in .gitignore, so the pin is a local check only.
    - No test loads a real MLX model (unit tests use `ModelPool(loader:)` with a stub; integration tests use SystemLanguageModel), so ci.yml gets no metallib input. There is no workflow test in this repo.
    - Other consumers (Router, CodeContext, AgentViewKit) use the same git@ URL in CI with no extra secret input.
  timestamp: 2026-09-30T04:56:33.841509+00:00
- actor: claude-code
  id: 01m3rbd32fnzz1ecpxwf6zcxjs
  text: |-
    Implementation landed (not committed, not pushed).
    - RED: `swift test --filter PooledConformanceTests` did not compile: "result value of type 'PooledSession' does not conform to closure result type 'AgentSession'" and "value of type 'PooledEmbedder' does not conform to specified type 'TextEmbedding'".
    - GREEN: the same filter, 2 tests in 1 suite passed.
    - Full `swift test`: 298 tests in 24 suites passed. `swift build --build-tests --package-path IntegrationTests` builds.
    - Package.resolved (root and IntegrationTests, both gitignored) pins FoundationModelsExtras at 5e6fe7c01633257068aae6cee04e252b383758c4.
    - `PooledSessionSupport.swift` forwards `fork()` only. `respond(to:)` and `respond(to:generating:)` of PooledSession are the witnesses already; a second declaration does not compile. The test proves the guided path: each stub-model call carries a schema (`isGuided: true`), and the default text-decode path sends no schema.
    - The fork proof: two queries on one tier; the factory runs one time; the transcript of each call holds only its own `# Task` prompt. With the default `fork()` (returns `self`), the second call would hold both prompts.
    - Deleted `PackageTests.theManifestDeclaresNoPackageDependency` and `ReadmeExampleTests.theReadmeNamesNoRemovedDependency`: both hold the package to no dependency, which the card reverses.
    - Build output has warnings that come only from dependency code: C++17-extension warnings in `.build/checkouts/mlx-swift` Metal kernels on a clean build, and the SwiftPM notice "missing creator for mutated node ... mlx-swift_Cmlx.bundle". No warning comes from a file of this repository.
    - Open: push to origin main and CI green (a separate user step).
  timestamp: 2026-09-30T05:08:10.447154+00:00
- actor: claude-code
  id: 01m3rbd6fcwc4s6rbchpdt1x4x
  text: |-
    ### implement — changed
    - evidence: 13 files — Package.swift, IntegrationTests/Package.swift, .github/workflows/ci.yml, README.md, docs/GUIDE.md, Sources/FoundationModelsRanker/PooledEmbedderSupport.swift (new), Sources/FoundationModelsRanker/Selection/PooledSessionSupport.swift (new), Sources/FoundationModelsRanker/Selection/AgentSession.swift, Sources/FoundationModelsRanker/TextEmbedding.swift, Tests/FoundationModelsRankerTests/PooledConformanceTests.swift (new), Tests/FoundationModelsRankerTests/Support/StubLanguageModel.swift (new), Tests/FoundationModelsRankerTests/PackageTests.swift, Tests/FoundationModelsRankerTests/ReadmeExampleTests.swift; `swift test` 298 passed; Extras pinned at 5e6fe7c
    - next: /review; then the user pushes to origin main and checks CI
  timestamp: 2026-09-30T05:08:13.932706+00:00
- actor: claude-code
  id: 01m3rbmf1mr30cxq2a8fm8ssgt
  text: |-
    ### test - green
    - evidence: `swift test`: 298 tests in 24 suites passed, 0 failed, 0 skipped. `swift test --package-path IntegrationTests`: 5 tests in 5 suites passed, 0 failed, 0 skipped.
    - warnings: No warning comes from a file in this repository. Each run shows one warning from SwiftPM: "missing creator for mutated node ... mlx-swift_Cmlx.bundle/Contents/MacOS". It comes from the mlx-swift dependency. No dependency code was changed.
    - next: review.
  timestamp: 2026-09-30T05:12:12.084488+00:00
- actor: claude-code
  id: 01m3rbvr0kxj1b2nr8ey3w2fqt
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (checkpoint 71adff3). 0 findings, 0 confirmed, 0 refuted. 7 validator runs, 0 failed. The engine did not review README.md and docs/GUIDE.md because no validator matches them.
    - next: The acceptance item "CI is green on the pushed commit" is open. The user must push to origin main, and then CI must be green.
  timestamp: 2026-09-30T05:16:10.643001+00:00
- actor: claude-code
  id: 01m3rbw1d8v9fh3tghs549egvd
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 13 files
    - test: green — swift test, 298 passed; IntegrationTests, 5 passed
    - commit: 71adff3
    - review: clean — 0 findings
  timestamp: 2026-09-30T05:16:20.264610+00:00
depends_on:
- 01M3QMD9KJ8T723R02085BEFYY
- 01M3QMD9X40XA640Z9CXCREQAM
position_column: done
position_ordinal: b080
title: Depend on Extras; PooledSession is an AgentSession and PooledEmbedder is a TextEmbedding
---
**Wait for:** FoundationModelsExtras tasks 01M3QMD8KBM42ZRNF447E06VVC ("PooledEmbedder from a Hugging Face name") and 01M3QMD98E12JEEZGKAVZB8CXN ("PooledModel and PooledSession for an LLM by Hugging Face name") on the Extras board: done and pushed.

## What
Each consumer gets the conformances without code of its own.

```swift
let qwen = PooledModel(ref: "mlx-community/Qwen3-4B-4bit")
SelectionConfig(model: { try await qwen.session(instructions: $0) })          // PooledSession: AgentSession
let e: any TextEmbedding = PooledEmbedder(ref: "mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ")
```

- `Package.swift`: depend on the core `FoundationModelsExtras` product (`git@github.com:swissarmyhammer/FoundationModelsExtras.git`, branch `main`).
- New `Sources/FoundationModelsRanker/Selection/PooledSessionSupport.swift`: `extension PooledSession: AgentSession` — forward `respond(to:)` and `fork()` (the two requirements of `AgentSession`).
- New `Sources/FoundationModelsRanker/PooledEmbedderSupport.swift`: `extension PooledEmbedder: TextEmbedding` — the protocol requirement `embed(_:)` forwards to `embed(texts:)`.
- `.github/workflows/ci.yml` (and its workflow test, if one exists): the build now compiles MLX through Extras; give the shared workflow the metallib input if a test loads a real model.
- `swift package update`, confirm the new Extras revision; push to `origin main` when green.

## Acceptance Criteria
- [x] `PooledSession` is an `AgentSession` and `PooledEmbedder` is a `TextEmbedding` with no consumer code.
- [x] The cached-root path forks the pooled session (it does not send the prefix again).
- [ ] CI is green on the pushed commit.

## Tests
- [x] `Tests/FoundationModelsRankerTests/PooledConformanceTests.swift`: with `ModelPool(loader:)` and a stub `LanguageModel`, a `SelectionTier` over a `PooledModel` factory selects ids, and a fork is used for each query; a `HybridRanker` with a `PooledEmbedder` on a test loader reports cosine.
- [x] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #model-pool