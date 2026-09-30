---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3r1ant622pd3jc02wydt7br
  text: |-
    Research and implementation notes.

    - Decision: the option the card names. When the query vector length is different from the length of a stored item vector, the search reports `.embeddingUnavailable` through `onDiagnostic` and skips the cosine signal (keyword-only for that search). This applies to `Searcher` and to `StreamingSearchCorpus`.
    - Shared helper: `CosineScoring.similarities(of:to:)` (internal, in `Sources/FoundationModelsRanker/CosineScoring.swift`). It gives `nil` when one or more target lengths differ from the query length, else one `cosineSimilarity` score for each target. Both `RetrievalEngine.cosineScores(forQuery:)` and `StreamingSearchCorpus.cosineScores(forQuery:snapshot:)` call it inside the same `guard` as the query embed, so there is one diagnostic path and no copied block.
    - `cosineSimilarity(_:_:)` itself is not changed. It still gives `0.0` for a length mismatch (public API, and existing tests use it).
    - Test rename: `SearcherTests.aQueryVectorOfADifferentLengthScoresZeroCosineAndKeepsKeywordRetrieval` is now `aQueryVectorOfADifferentLengthDegradesToKeywordOnlyRetrievalAndReportsTheDiagnosticOncePerSearch`. It now expects `recorder.diagnostics == [.embeddingUnavailable]` (it expected `isEmpty` before). The old name described the silent behavior, so the name had to change with the behavior. No other file refers to the old name.
    - New test: `StreamingSearchCorpusTests.aQueryVectorOfADifferentLengthDegradesTheStreamingSearchToKeywordOnlyAndReportsTheDiagnosticOncePerSearch`. It must add `runAItems` in ONE `add(items:)` call. `streamedRunACorpus` adds one item for each call, and `MismatchedLengthEmbedder` gives a one-text call the query length, so that helper would store item vectors with the query length and no mismatch would occur.
    - Docs: `docs/GUIDE.md` "Graceful degradation" has a new bullet. Doc comments on `Searcher`, `RetrievalEngine.cosineScores`, `StreamingSearchCorpus.cosineScores`, `RankDiagnostic.embeddingUnavailable`, and `MismatchedLengthEmbedder` name the new case.
    - TDD: RED showed both tests fail with `recorder.diagnostics -> []`. GREEN showed both pass. Full `swift test`: 293 tests in 22 suites passed, no warnings.
  timestamp: 2026-09-30T02:12:05.574529+00:00
- actor: claude-code
  id: 01m3r1azqgs53t84vdx1van3p0
  text: |-
    ### implement — changed
    - evidence: 8 files — Sources/FoundationModelsRanker/CosineScoring.swift, Sources/FoundationModelsRanker/Searcher.swift, Sources/FoundationModelsRanker/StreamingSearchCorpus.swift, Sources/FoundationModelsRanker/Selection/RankDiagnostic.swift, docs/GUIDE.md, Tests/FoundationModelsRankerTests/SearcherTests.swift, Tests/FoundationModelsRankerTests/StreamingSearchCorpusTests.swift, Tests/FoundationModelsRankerTests/Support/MismatchedLengthEmbedder.swift. `swift test`: 293 tests in 22 suites passed, 0 warnings.
    - next: /review (task stays in doing; not committed, not pushed)
  timestamp: 2026-09-30T02:12:15.728496+00:00
- actor: claude-code
  id: 01m3r1f1zam0wjt5pzf3pd1qcr
  text: |-
    ### test - green
    - evidence: `swift test` - 293 tests in 22 suites passed, 0 failed, 0 skipped, 0 warnings. `swift test --package-path IntegrationTests` - 5 tests in 5 suites passed, 0 failed, 0 skipped. `swift build --build-tests -Xswiftc -warnings-as-errors` - build complete, 0 warnings.
    - next: review.
  timestamp: 2026-09-30T02:14:29.098825+00:00
position_column: doing
position_ordinal: '80'
title: Report a mismatched embedding vector length as a diagnostic
---
## What
`TextEmbedding` has no `dimension` now (^85befyy). Each vector tells its own length. When the query vector and an item vector differ in length, `CosineScoring.cosineSimilarity(_:_:)` gives 0.0. `Searcher.cosineScores(forQuery:)` and `StreamingSearchCorpus.cosineScores(forQuery:snapshot:)` then send no diagnostic. `docs/GUIDE.md` ("Graceful degradation") says "Every fallback is reported. No fallback is silent." This case is silent.

Decide the behavior and make the code and the guide agree. One option: when the query vector length differs from the stored item vector length, report `.embeddingUnavailable` and skip the cosine signal for that search.

## Acceptance Criteria
- [x] A mismatched vector length is reported through `onDiagnostic`, or the guide states that it is not.
- [x] `SearcherTests.aQueryVectorOfADifferentLengthScoresZeroCosineAndKeepsKeywordRetrieval` matches the chosen behavior.

## Tests
- [x] A `Searcher` test and a `StreamingSearchCorpus` test with `MismatchedLengthEmbedder`.
- [x] `swift test` passes.

## Workflow
- Use `/tdd`. #model-pool