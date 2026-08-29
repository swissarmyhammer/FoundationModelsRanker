---
assignees:
- claude-code
depends_on:
- 01M16WTVGW4GDJK9MD6CD4GEYS
- 01M16WW6WN0638CJKEJ3XEHKMV
position_column: todo
position_ordinal: '8580'
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

## Acceptance Criteria

- [ ] `grep -c "\.package(" Package.swift` returns 0.
- [ ] `swift package reset && swift build` succeeds with no network access to a private repository.
- [ ] `swift package show-dependencies` lists no dependency.
- [ ] `swift build` prints no `Cmlx.bundle` warning and no `steel_attention.h` warning.
- [ ] `swift build` prints no "dependency is unused by any target" warning.

## Tests

- [ ] `Tests/FoundationModelsRankerTests/PackageTests.swift` — add a test that reads `Package.swift` from `#filePath`'s repository root and asserts the text holds no `.package(` call. This keeps a dependency from coming back without notice.
- [ ] `swift test` passes and the whole suite runs without a GPU.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.