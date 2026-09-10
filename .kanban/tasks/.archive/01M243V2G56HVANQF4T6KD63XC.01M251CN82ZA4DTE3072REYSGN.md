---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m24zeak68v5tne9nzq38nvvy
  text: |-
    ### finish — skipped
    - reason: the work is in the FoundationModelsMetadataRegistry repository. The finish loop for this package works only in the current tree.
    - next: run /finish on this card from a checkout of FoundationModelsMetadataRegistry, or move the card to that repository's board.
  timestamp: 2026-09-10T06:17:51.974901+00:00
- actor: claude-code
  id: 01m251bdjhh810zgrg9awwmg67
  text: |-
    ### moved
    - A copy of this card is on the FoundationModelsMetadataRegistry board as ^5z7hmrz.
    - Do the work there. This card stays only as a record for the ranker side.
  timestamp: 2026-09-10T06:51:13.873901+00:00
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
