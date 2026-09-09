---
assignees:
- claude-code
position_column: todo
position_ordinal: '8180'
title: 'FoundationModelsMetadataRegistry: move MetadataSearcher to SelectionTier.init(catalog:config:onDiagnostic:) and drop candidateLimit from its tests'
---
## What

Task `^kqp9e5e` changed this package. `SelectionTier` now makes one prompt that picks and runs no retrieval. The consumer `FoundationModelsMetadataRegistry` depends on this package on the remote `main` branch, and three of its uses need an update in that repository:

- `Sources/FoundationModelsMetadataRegistry/MetadataSearcher.swift` calls `SelectionTier(catalog:config:onDiagnostic:retrievalRanking:)`. That initializer still compiles, but it is deprecated and ignores `retrievalRanking`. Move the call to `SelectionTier(catalog:config:onDiagnostic:)` and delete the `rankEntireCatalog` ranking that fed it.
- `Tests/FoundationModelsMetadataRegistryTests/OverBudgetTests.swift` and `HotReloadTests.swift` pass `candidateLimit:` to `SelectionConfig`. That parameter no longer exists. Remove it, and rewrite the over-budget tests for the split design: every id reaches exactly one prompt, and no `.retrievalCut` is reported.
- `Sources/FoundationModelsMetadataRegistry/Catalog/Diagnostics.swift` maps `RankDiagnostic.retrievalCut`. The case still exists and is never emitted. Keep the mapping or remove it together with the consumer's own `.retrievalCut` case.

## Where

This work lives in the `FoundationModelsMetadataRegistry` repository, not in this one. This card records the follow-up so the change is not lost.

## Acceptance Criteria

- [ ] `swift build` and `swift test` pass in `FoundationModelsMetadataRegistry` against this package's `main` with no deprecation warning.
