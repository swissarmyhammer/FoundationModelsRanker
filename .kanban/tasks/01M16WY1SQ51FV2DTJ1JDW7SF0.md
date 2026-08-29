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
- actor: claude-code
  id: 01m17dem6jybedtbxh0481ry3k
  text: |-
    ### commit — changed
    - evidence: 59c348b docs(readme): rewrite README for a package with no dependency (8 files changed, 333 insertions, 60 deletions)
    - next: push is not done. A human must push the commit.
  timestamp: 2026-08-29T18:45:28.914936+00:00
- actor: claude-code
  id: 01m17dr1mv6bw1thnd83kkhhe9
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (commit 59c348b). counts: 0 findings, 0 confirmed, 0 refuted, 7 attempted, 0 failed. The engine read the three Swift files of the change. It read no `README.md`, because no validator matches a Markdown file, and it read no `.kanban/` file, because an ignore rule holds them out.
    - The engine gives no cover to `README.md`, so each claim of the document was compared to the source by hand. Every claim is true:
      - No dependency: `Package.swift` has `dependencies: []` and holds no `.package(` text.
      - `Searcher(items, session: oneSession)`: `Searcher.swift` has a second public initializer that takes `session: any AgentSession`. `LanguageModelSessionSupport.swift` gives `extension LanguageModelSession: AgentSession`, so the block of the README compiles for a reader who has the package.
      - Shared transcript: `LanguageModelSession.fork()` gives back `self`. The prose of the README agrees with the header of `LanguageModelSessionSupport.swift` and with the header of `Searcher.swift`.
      - `TextEmbedding`: the protocol has `dimension` and `embed(_:)` and nothing more.
      - `SelectionTier.idEnumSchema(ids:)`: `public actor SelectionTier` holds `public static func idEnumSchema(ids: [String]) throws -> String`. Both the type and the method are public, so the block is correct for a reader outside the package, and the `@testable import` of the test hides no access problem.
      - Three `swift run FullMonty` paths: `Examples/FullMonty/main.swift` makes a branch on `--no-model`, then on `--embedder`, then goes to the default path on the on-device model.
    - Test cover of the Swift blocks: each block has a test that compiles it and runs it. The lead block, the one live session block, the factory block, the embedder block and the guided output block each have one test in `ReadmeExampleTests.swift`. The `MyEmbedder` type of the README is in the test file word for word.
    - The `## Install` exception is correct and sufficient. The block is a `PackageDescription` fragment, and SwiftPM gives that module to no target, so no test can compile it. The suite header and the test comment both give this reason, so the exception is not hidden. `theInstallSnippetNamesThisPackagesRepository` holds the URL of the README to the package name that `Package.swift` declares, which is the one part of the block that can become wrong in this repository.
    - The guard test still guards. `theManifestDeclaresNoPackageDependency` in `PackageTests.swift` is not changed: it reads `manifestURL` and makes the same assertion `#expect(!manifest.contains(".package("))`. The change moved only the private `repositoryRootURL` walk to `Support/RepositoryRoot.swift`. The new walk deletes four path components from `Tests/FoundationModelsRankerTests/Support/RepositoryRoot.swift`, which gives the repository root, so `manifestURL` points at the real `Package.swift` on disk.
    - Out of scope, as the card of `^3t4nhk7` says: `plan.md` keeps the old design as history.
    - next: none. Task moves to done.
  timestamp: 2026-08-29T18:50:37.595326+00:00
- actor: claude-code
  id: 01m17ds2174nkqgsgfn3sw4g98
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 4 files; README rewritten for a package with no dependencies, one test per code block, a drift guard, and a shared repository-root helper
    - test: green — swift build 0 warnings; swift test 273 tests, 272 passed, 1 documented gated skip; `grep -in "router\|mlx\|huggingface" README.md` finds nothing
    - commit: 59c348b — 8 files changed, 333 insertions, 60 deletions
    - review: clean — zero findings; the reviewer checked every README claim against the source by hand, since no validator reads Markdown
    - next: none — task is in done

    The reviewer confirmed the one untested code block (`## Install`, a PackageDescription fragment no target can compile) is honestly documented as such, and that the manifest guard test kept its assertion through the repository-root move.
  timestamp: 2026-08-29T18:51:10.759998+00:00
depends_on:
- 01M16WWNSAG4EN2JDCQ2Q0P8GR
- 01M16WXKX259CBHMWBENQ132HW
position_column: done
position_ordinal: 9d80
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