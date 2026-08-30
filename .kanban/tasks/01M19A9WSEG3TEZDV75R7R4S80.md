---
assignees:
- claude-code
position_column: todo
position_ordinal: '8180'
title: Add tests for the query-embed failure path in StreamingSearchCorpus
---
## What

`Sources/FoundationModelsRanker/StreamingSearchCorpus.swift:329-331`

Coverage: 92.9% (65/70 lines) for the file. Uncovered lines: 330-331.

```swift
guard let queryVector = try? await embedder.embed([query]).first else {
    onDiagnostic(.embeddingUnavailable)   // 330 — uncovered
    return nil                            // 331 — uncovered
}
```

The same degradation branch as the one in `Searcher.swift`, but on the streaming corpus path, which is the one a caller uses when items arrive over time. It has its own copy of the guard, so a test of the `Searcher` path does not cover it.

Worth testing on its own because the streaming corpus embeds items incrementally: a query-embed failure here happens while the item vectors are already built up, which is a different state from the `Searcher` case.

## Acceptance Criteria

- [ ] `StreamingSearchCorpus.swift:330-331` is covered — confirm by re-running coverage, not by inspection.
- [ ] The test drives the real streaming path: add items, then search with an embedder that throws only on the query call.
- [ ] No production code changes. Tests only.

## Tests

- [ ] Add to `Tests/FoundationModelsRankerTests/StreamingSearchCorpusTests.swift`: after adding items with a working embedder, a search whose query embed throws still returns keyword-ranked matches.
- [ ] Assert `.embeddingUnavailable` is reported for that search.
- [ ] Assert a later search with a working embedder recovers the cosine signal, so the degradation is per-search and not sticky.
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #coverage-gap