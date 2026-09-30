---
assignees:
- claude-code
position_column: todo
position_ordinal: '8380'
title: Report a mismatched embedding vector length as a diagnostic
---
## What
`TextEmbedding` has no `dimension` now (^85befyy). Each vector tells its own length. When the query vector and an item vector differ in length, `CosineScoring.cosineSimilarity(_:_:)` gives 0.0. `Searcher.cosineScores(forQuery:)` and `StreamingSearchCorpus.cosineScores(forQuery:snapshot:)` then send no diagnostic. `docs/GUIDE.md` ("Graceful degradation") says "Every fallback is reported. No fallback is silent." This case is silent.

Decide the behavior and make the code and the guide agree. One option: when the query vector length differs from the stored item vector length, report `.embeddingUnavailable` and skip the cosine signal for that search.

## Acceptance Criteria
- [ ] A mismatched vector length is reported through `onDiagnostic`, or the guide states that it is not.
- [ ] `SearcherTests.aQueryVectorOfADifferentLengthScoresZeroCosineAndKeepsKeywordRetrieval` matches the chosen behavior.

## Tests
- [ ] A `Searcher` test and a `StreamingSearchCorpus` test with `MismatchedLengthEmbedder`.
- [ ] `swift test` passes.

## Workflow
- Use `/tdd`. #model-pool