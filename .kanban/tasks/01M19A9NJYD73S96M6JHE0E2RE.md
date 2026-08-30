---
assignees:
- claude-code
position_column: todo
position_ordinal: '80'
title: Add tests for the query-embed failure path in Searcher's cosine signal
---
## What

`Sources/FoundationModelsRanker/Searcher.swift:439-441`

Coverage: 96.0% (120/125 lines) for the file. Uncovered lines: 440-441.

```swift
guard let queryVector = try? await embedder.embed([query]).first else {
    onDiagnostic(.embeddingUnavailable)   // 440 — uncovered
    return nil                            // 441 — uncovered
}
```

This is `RetrievalEngine.cosineScores(forQuery:)`. The branch runs when an embedder is configured and item embeddings exist, but embedding the QUERY fails at search time. The tier then drops to keyword-only retrieval and reports `.embeddingUnavailable`.

This is a documented behavior of the package — the README's "Graceful degradation" section promises "a failed query embed drops to keyword-only retrieval and reports `.embeddingUnavailable`". Nothing proves it today. The sibling branch at 435-437 (no embedder at all) IS covered; only the throwing-embedder branch is not.

The test target already has embedder doubles in `Tests/FoundationModelsRankerTests/Support/`: `FakeEmbedder`, `GatedEmbedder`, `MismatchedCountEmbedder`, `CountingEmbedder`. None of them throws on demand. Add a throwing double, or extend an existing one, rather than writing a fourth near-copy — check `GatedEmbedder` first, it may already have the shape needed.

## Acceptance Criteria

- [ ] A `TextEmbedding` double exists that succeeds for the item-embedding call at `init` and then throws for the query-embedding call at search time.
- [ ] `Searcher.swift:440-441` is covered — confirm by re-running coverage, not by inspection.
- [ ] No production code changes. Tests only.

## Tests

- [ ] Add to `Tests/FoundationModelsRankerTests/SearcherTests.swift`: with an embedder that throws only on the query call, `search(_:limit:)` still returns keyword-ranked matches rather than throwing or returning empty.
- [ ] Assert `.embeddingUnavailable` is reported exactly once for that search, via a `DiagnosticRecorder`.
- [ ] Assert the returned matches carry a cosine signal of `0.0`, so the caller can tell the signal did not contribute.
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #coverage-gap