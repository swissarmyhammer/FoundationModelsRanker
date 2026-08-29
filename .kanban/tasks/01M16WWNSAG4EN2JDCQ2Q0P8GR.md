---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m1755nv0g0fveew2df861pzx
  text: |-
    ### Extra work this card must do (found 2026-08-29 by ^cd4geys)

    The card's "Files to change" list is incomplete. Add this:

    - `Tests/FoundationModelsRankerTests/Support/ScriptedAgentSession.swift` still has `import FoundationModelsRouter`. That import became unused when `^4kx83sx` deleted `receivedGrammars` and the `Grammar` parameter. Delete the import. The test target cannot compile once `Package.swift` drops the dependency, so this is not optional.

    Before you touch `Package.swift`, run `grep -rn "FoundationModelsRouter\|MLX\|HuggingFace\|Tokenizers\|Jinja" Sources Tests Examples` and delete every import the scan finds. `Sources/` is already clean as of `^cd4geys`.
  timestamp: 2026-08-29T16:20:47.072698+00:00
- actor: claude-code
  id: 01m17bjam7q3k4mgvnzwbehvwd
  text: |-
    ### Research

    Ran the scan the earlier comment asked for:

    `grep -rn "FoundationModelsRouter\|MLXHuggingFace\|MLXLMCommon\|HuggingFace\|Tokenizers\|Jinja\|MLX" Sources Tests Examples`

    It found exactly one hit — `Tests/FoundationModelsRankerTests/Support/ScriptedAgentSession.swift:2: import FoundationModelsRouter`. `Sources/` and `Examples/` are clean. `Examples/FullMontyCore` keeps no live-Router path, so the `FullMontyCore` target needs no product dependency at all.

    `.github/workflows/ci.yml` names no SSH key and no MLX or Hugging Face step, so CI needs no change for this card.

    ### Extra comment edits, and why

    The card names two comments to rewrite. Two more comments in `Package.swift` also named the deleted packages, and this change made one of them false:

    - The `platforms:` comment said the macOS 27 floor was "inherited from FoundationModelsRouter". With the dependency gone the floor is inherited from nothing, so the sentence was wrong. It now reads "the floor both consumer repos use (plan.md §3)".
    - The `packageName` doc comment named "the sibling FoundationModelsRouter and FoundationModelsMetadataRegistry packages" as the source of the named-constant style. It now names FoundationModelsMetadataRegistry only.

    No other prose changed. `Tests/.../Support/ScriptedAgentSession.swift` keeps its "no Router dependency" header comment: it is still true and the card asked only for the import.

    ### TDD record

    RED, then GREEN, then RED again after a refactor of the path code:

    1. Added `theManifestDeclaresNoPackageDependency()` to `PackageTests.swift` and ran it against the old manifest — it failed, and the failure output printed the real manifest text, which proves it read the correct file.
    2. Deleted the dependencies; the test passed.
    3. Rewrote the repository-root derivation for clarity, then appended a sentinel `.package(` line to `Package.swift` and re-ran — the test failed again. Restored the manifest and confirmed it is byte-identical to the version before the sentinel.

    ### Discovery — `swift package reset` can fail on `.build`

    The first `swift package reset` ran for 14 minutes and then failed:

    `error: Error removing scratch directory at '.../.build': ... Code=513 ... "Operation not permitted"`

    A plain `rm -rf .build` removed the directory in 3 seconds. After that, `swift package reset` returned 0 at once. If the next agent meets the same error, remove `.build` with `rm -rf` first; do not read it as a defect in the manifest.

    ### Package.resolved

    `swift package reset` left a stale `Package.resolved` behind. It was deleted, not edited. With no dependency to resolve, SwiftPM writes no new one, so the file is now absent. It is gitignored in this repository.
  timestamp: 2026-08-29T18:12:33.031713+00:00
- actor: claude-code
  id: 01m17bjzyzgqfjrymes8pc0vwa
  text: |-
    ### implement — changed
    - evidence: 4 files — `Package.swift` (deleted the `dependencies:` array contents, the five constants `routerDependencyName` / `mlxPackage` / `huggingFacePackage` / `transformersPackage` / `liveRouterProductDependencies` with their doc comments, the `Jinja` product on the test target, and the `liveRouterProductDependencies` on `FullMontyCore`; rewrote the header, `platforms:`, `packageName` and `FullMontyCore` comments); `README.md` (deleted the two `mlx-swift` warning bullets in `Development`, nothing else); `Tests/FoundationModelsRankerTests/Support/ScriptedAgentSession.swift` (deleted `import FoundationModelsRouter`); `Tests/FoundationModelsRankerTests/PackageTests.swift` (added `theManifestDeclaresNoPackageDependency()`).
    - verification: `grep -c "\.package(" Package.swift` = 0. `rm -rf .build && swift package reset && swift build` = exit 0, "Build complete! (185.68 sec)", 0 warnings — no `Cmlx.bundle`, no `steel_attention.h`, no "dependency is unused by any target". `swift package show-dependencies` = "No external dependencies found". `swift test` = exit 0, 269 tests in 21 suites passed, 0 warnings. `swift run FullMonty --no-model` = exit 0; `swift run FullMonty --embedder` = exit 0, both with 0 warnings. The scan for `FoundationModelsRouter|MLXHuggingFace|MLXLMCommon|HuggingFace|Tokenizers|Jinja|MLX` over `Sources Tests Examples Package.swift` now returns nothing.
    - open: one test still reports "skipped" under a plain `swift test` — `selectionTierWithABareLanguageModelSessionReachesGuidedGeneration`, gated on `FOUNDATIONMODELSRANKER_INTEGRATION_TESTS` because it needs a real `SystemLanguageModel`. It is unchanged by this card and pre-dates it.
    - next: `/review`
  timestamp: 2026-08-29T18:12:54.879366+00:00
depends_on:
- 01M16WTVGW4GDJK9MD6CD4GEYS
- 01M16WW6WN0638CJKEJ3XEHKMV
position_column: doing
position_ordinal: '80'
title: Delete every external package dependency from Package.swift
---
## What

`Package.swift` declares four package dependencies: `FoundationModelsRouter`, `mlx-swift-lm`, `swift-huggingface`, and `swift-transformers`, plus a `swift-jinja` version pin. After the earlier tasks no target imports any of them. Delete all of them. The package then depends only on the macOS 27 SDK, which is the whole point of the change.

Two of the four use `git@github.com:` SSH URLs. Deleting them also removes the need for an SSH key in CI, and lets anyone outside the `swissarmyhammer` organization build the package.

Files to change:

- `Package.swift`:
  - Delete the `dependencies:` array contents (lines 119-133), leaving `dependencies: []`.
  - Delete the constants `routerDependencyName`, `mlxPackage`, `huggingFacePackage`, `transformersPackage`, and `liveRouterProductDependencies` (lines 36-94), and their doc comments.
  - The `FoundationModelsRanker` target becomes `dependencies: []`.
  - The `FoundationModelsRankerTests` target drops the `Jinja` product and keeps `.target(name: packageName)` and `.target(name: "FullMontyCore")`.
  - The `FullMontyCore` target becomes `dependencies: [.target(name: packageName)]`.
  - Rewrite the manifest header comment (lines 96-105) and the `FullMontyCore` comment (lines 158-167) to drop every mention of Router, MLX, and Hugging Face.
- `README.md` — delete the two `mlx-swift` warning bullets in the `Development` section, because the package no longer builds MLX. A later task rewrites the rest of the README.
- `Tests/FoundationModelsRankerTests/Support/ScriptedAgentSession.swift` — delete the unused `import FoundationModelsRouter` (added by the comment on this card).

## Acceptance Criteria

- [x] `grep -c "\.package(" Package.swift` returns 0.
- [x] `swift package reset && swift build` succeeds with no network access to a private repository.
- [x] `swift package show-dependencies` lists no dependency.
- [x] `swift build` prints no `Cmlx.bundle` warning and no `steel_attention.h` warning.
- [x] `swift build` prints no "dependency is unused by any target" warning.

## Tests

- [x] `Tests/FoundationModelsRankerTests/PackageTests.swift` — add a test that reads `Package.swift` from `#filePath`'s repository root and asserts the text holds no `.package(` call. This keeps a dependency from coming back without notice.
- [x] `swift test` passes and the whole suite runs without a GPU.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.