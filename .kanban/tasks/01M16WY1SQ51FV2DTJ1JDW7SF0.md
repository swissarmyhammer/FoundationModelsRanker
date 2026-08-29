---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m17cvefkcqyw5xsjxc27ash9
  text: |-
    Picked up. Research done. Line numbers on the card are stale; located everything by content.

    State of `README.md` at pickup:
    - `grep -in "router\|mlx\|huggingface" README.md` gives 4 hits: the intro dependency sentence, the "full monty" paragraph, "resolve `profile` from a live `Router`", and `import FoundationModelsRouter`. No `mlx` or `huggingface` hit remains — an earlier card already removed the two `mlx-swift` bullets from `Development`.
    - The `Development` bullet no longer names a Router. It already says the gated test needs a real `SystemLanguageModel` and a Mac with Apple Intelligence, so that half is already correct. One sentence in it IS stale: "`Examples/FullMonty` uses the same environment variable to gate its live-model path." `Examples/FullMonty/main.swift` selects its path from `--no-model` / `--embedder` command-line arguments now, and nothing in `FullMontyCore` gates the default path on the environment variable. Only `AgentSessionDispatchTests.selectionTierWithABareLanguageModelSessionReachesGuidedGeneration` reads it.

    API facts the new text must match:
    - `Searcher` has two public initializers. One takes `session: (@Sendable (String) -> any AgentSession)?`, default `Searcher.defaultSessionFactory`. The other takes `session: any AgentSession`. `Searcher.swift`'s header records the tradeoff: `LanguageModelSession.fork()` gives back `self`, so the instance form shares one transcript across all calls; the factory form gives each call a fresh context.
    - `SelectionTier.idEnumSchema(ids: [String]) throws -> String` replaces `idEnumGrammar`. It gives the JSON Schema source text only.
    - `TextEmbedding` is `dimension` and `embed(_:)`, nothing else. `Examples/FullMontyCore/DemoEmbedder.swift` is the runnable GPU-free conformer.
    - `RoutedEmbedderAdapter` and `RoutedAgentSession` do not exist in the source tree.

    Test support already present, to reuse instead of rewriting:
    - `Support/SelectionSchemaTestSupport.enumIds(in:)` reads the `properties.ids.items.enum` set out of a schema source string.
    - `Support/ScriptedAgentSession.swift` gives `ScriptedAgentSession`, `RecordingSessionFactory`, `DiagnosticRecorder`.
    - `Support/FakeEmbedder.swift` gives `FakeEmbedder`.
    - `PackageTests.swift` holds a `private let repositoryRootURL` walk from `#filePath`. The README drift guard needs the same value, so the walk moves to `Support/RepositoryRoot.swift` and both files read it there. This is to obey the duplication rule, not a free refactor.
  timestamp: 2026-08-29T18:35:00.467188+00:00
- actor: claude-code
  id: 01m17d7s8ex3w7fbnx0dva5jtq
  text: |-
    Implementation landed. TDD order: the tests went in first, and the run at that point failed on exactly one test — "README.md names no removed dependency" — while every block test passed, because those blocks pin API that already exists. The README edits then turned that one red green.

    What changed in `README.md`:
    - Intro: "Targets macOS 27+ and has no external dependency: the package builds against the macOS SDK alone."
    - New one-live-session example above the factory example, with the tradeoff in prose: one live session shares one transcript, because `LanguageModelSession.fork()` gives back `self`; give a session factory when each call must get a fresh context.
    - The Router example is gone. "Bring your own embedder" and "Guided output" stand in its place.
    - `Development`: a new bullet for `swift run FullMonty`'s three paths, and the gated-test bullet now says the test needs a real `SystemLanguageModel` session and nothing else. The stale claim that `Examples/FullMonty` gates its live path on the same environment variable is deleted, because the example reads `--no-model` / `--embedder` arguments now.

    Two decisions a later reader should know about:

    1. `PackageTests.swift` held a `private let repositoryRootURL`. The README tests need the same path, so the walk moved to `Tests/FoundationModelsRankerTests/Support/RepositoryRoot.swift`, which now also owns `manifestURL` and `readmeURL`. `PackageTests` reads them from there. This is the duplication rule, not an unrelated refactor: writing a second `#filePath` walk was the alternative.

    2. The `## Install` block cannot be compiled by any test. It is a `.package(url:)` manifest fragment, and SwiftPM hands no target the `PackageDescription` module. Rather than leave the block with no test, `theInstallSnippetNamesThisPackagesRepository` reads the package name out of `Package.swift` and asserts the README's install URL names that same repository, so a rename cannot silently split the two. The suite header states the exception.

    Also considered and rejected: writing a third embedder implementation for the README block. `PackageTests.VowelCountEmbedder` and `Examples/FullMontyCore/DemoEmbedder` already exist, and a third would be near-duplicate logic. The README's `MyEmbedder` forwards to a `myBackend` the prose names as the reader's own service, so it carries no embedding logic at all; the test binds `myBackend` to `FakeEmbedder`, sized off `MyEmbedder().dimension` so the two cannot disagree.
  timestamp: 2026-08-29T18:41:44.718530+00:00
- actor: claude-code
  id: 01m17d7xydf0cx7qx65xv9k2sz
  text: |-
    ### implement — changed
    - evidence: 4 files — README.md, Tests/FoundationModelsRankerTests/ReadmeExampleTests.swift, Tests/FoundationModelsRankerTests/PackageTests.swift, Tests/FoundationModelsRankerTests/Support/RepositoryRoot.swift (new). `grep -in "router\|mlx\|huggingface" README.md` exits 1. `swift build` complete, no warning. `swift test`: 273 tests in 21 suites passed, 0 failed, 1 skipped (the pre-existing `FOUNDATIONMODELSRANKER_INTEGRATION_TESTS` gated live-model test).
    - next: /review
  timestamp: 2026-08-29T18:41:49.517434+00:00
- actor: claude-code
  id: 01m17dc2nbfza88exqxeg0vzsx
  text: |-
    ### test — green
    - evidence: `swift build` clean, zero warnings (fresh `.build`, 6.68s). `swift test` — 273 tests, 21 suites, 272 passed, 1 skipped (`selectionTierWithABareLanguageModelSessionReachesGuidedGeneration`, gated on `FOUNDATIONMODELSRANKER_INTEGRATION_TESTS`, the one documented exception), 0 failed, 0 warnings.
    - `grep -in "router|mlx|huggingface" README.md` finds nothing (exit 1, no match).
    - `theReadmeNamesNoRemovedDependency` (ReadmeExampleTests.swift) exists and passed.
    - `theManifestDeclaresNoPackageDependency` (PackageTests.swift) exists and passed. It still reads the real `Package.swift` through `manifestURL`, defined in `Tests/FoundationModelsRankerTests/Support/RepositoryRoot.swift` as `repositoryRootURL.appending(path: "Package.swift")`, where `repositoryRootURL` walks up four directories from `#filePath` (Support -> FoundationModelsRankerTests -> Tests -> repository root). The move did not lose the assertion.
    - `swift run FullMonty --no-model` exit 0. `swift run FullMonty --embedder` exit 0.
    - next: none. Build and test suite are clean.
  timestamp: 2026-08-29T18:44:05.419248+00:00
depends_on:
- 01M16WWNSAG4EN2JDCQ2Q0P8GR
- 01M16WXKX259CBHMWBENQ132HW
position_column: doing
position_ordinal: '80'
title: Rewrite the README for a package with no dependencies
---
## What

The README names `FoundationModelsRouter` five times and shows an example built on `RoutedEmbedderAdapter` and `RoutedAgentSession`. Both types are gone. Rewrite those parts.

Files to change:

- `README.md`:
  - Line 10-11 — delete "and depends on [FoundationModelsRouter](...)". Put a sentence in its place that says the package has no external dependencies and needs only macOS 27.
  - Lines 32-43 — keep the session factory example. Add a shorter example above it that passes one session: `let searcher = try await Searcher(items, session: LanguageModelSession(model: .default, instructions: "Pick the best tools."))`.
  - Lines 45-62 — delete the Router example. Put a "Bring your own embedder" section in its place. Show a `struct` that conforms to `TextEmbedding`, and say that any embedding backend plugs in the same way. Point at `Examples/FullMontyCore/DemoEmbedder.swift` for a runnable one.
  - Add a short "Guided output" section. Say that `SelectionTier.idEnumSchema(ids:)` returns a JSON Schema source string that constrains the answer to the given ids, and that a caller with a grammar-capable backend can pass it to that backend.
  - `Development` section — the `mlx-swift` bullets are deleted by an earlier task. Update the third bullet, which still says the gated test needs a live Router. It needs Apple Intelligence only.

Leave `plan.md` as it is. It records the original design and is history.

## Acceptance Criteria

- [x] `grep -in "router\|mlx\|huggingface" README.md` finds nothing.
- [x] The README states that the package has no external dependencies.
- [x] Every Swift code block in the README compiles. The one exception is the `## Install` block: it is a `PackageDescription` manifest fragment for a consumer's own `Package.swift`, and SwiftPM gives no target that module, so no test can compile it. `ReadmeExampleTests.theInstallSnippetNamesThisPackagesRepository` holds that block to the package name `Package.swift` declares instead.

## Tests

- [x] `Tests/FoundationModelsRankerTests/ReadmeExampleTests.swift` — add or update one test per README code block, so each block is compiled and run by the suite. This is the file's stated job.
- [x] Add a test that reads `README.md` and asserts the text holds no `Router`, `MLX`, or `HuggingFace` token. This keeps the document from drifting back.
- [x] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.