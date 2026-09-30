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
- actor: claude-code
  id: 01m3r1n7kfpjjt7jd4d43jx0bt
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (checkpoint 5ef0bca). 1 finding, 1 confirmed, 0 refuted. Sources/FoundationModelsRanker/StreamingSearchCorpus.swift:330 (duplication/duplication).
    - next: Move the guard, embed, and similarity-check steps into one shared helper. Give the item embeddings array to the helper as a parameter. Call the helper from Searcher.RetrievalEngine and from StreamingSearchCorpus. Then run the review again.
  timestamp: 2026-09-30T02:17:51.471349+00:00
- actor: claude-code
  id: 01m3r1npgse43ctrrt1918v23w
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 8 files
    - test: green — swift test, 293 passed; IntegrationTests, 5 passed
    - commit: 5ef0bca
    - review: findings — Sources/FoundationModelsRanker/StreamingSearchCorpus.swift:330
  timestamp: 2026-09-30T02:18:06.745062+00:00
- actor: claude-code
  id: 01m3r208ynd9a3t12hbhw8qyzj
  text: |-
    Review finding fix (duplication/duplication, StreamingSearchCorpus.swift cosineScores).

    - New internal namespace `CosineSignal` in `Sources/FoundationModelsRanker/CosineSignal.swift`. Its one function, `scores(forQuery:embedder:itemEmbeddings:onDiagnostic:)`, holds the full guard/embed/similarity-check/report sequence. It gives `nil` and reports `.embeddingUnavailable` one time when the embedder is `nil`, the item vectors are `nil`, the query embed fails, or the lengths differ.
    - `RetrievalEngine.cosineScores(forQuery:)` (Searcher.swift) keeps only its `weights.cosine > 0.0` opt-out guard, then calls the helper.
    - `StreamingSearchCorpus.cosineScores(forQuery:snapshot:)` now builds the row vectors with `compactMap` (the `var` accumulator loop is gone, per the swift immutability rule). When a row has no vector, it gives `nil` to the helper. Thus all three copies of the `onDiagnostic(.embeddingUnavailable); return nil` block in that file are gone, not only the one at the named line.
    - Order is kept: the helper checks the embedder and the item vectors before it embeds the query, so no wasted embed call.
    - `CosineScoring.similarities(of:to:)` is not changed. `CosineSignal` is now its only caller.
    - New tests: `Tests/FoundationModelsRankerTests/CosineSignalTests.swift` (5 tests). RED: build failed with "cannot find 'CosineSignal' in scope". GREEN: 5 passed.
    - Full `swift test`: 298 tests in 23 suites passed. `swift build --build-tests -Xswiftc -warnings-as-errors`: build complete, 0 warnings.
  timestamp: 2026-09-30T02:23:53.301808+00:00
- actor: claude-code
  id: 01m3r20q5twdw3x1ggk7w46ysq
  text: |-
    ### implement — changed
    - evidence: 4 files — Sources/FoundationModelsRanker/CosineSignal.swift (new), Sources/FoundationModelsRanker/Searcher.swift, Sources/FoundationModelsRanker/StreamingSearchCorpus.swift, Tests/FoundationModelsRankerTests/CosineSignalTests.swift (new). `swift test`: 298 tests in 23 suites passed, 0 failed. `swift build --build-tests -Xswiftc -warnings-as-errors`: 0 warnings. Finding flipped to [x].
    - next: /review (task stays in doing; not committed, not pushed)
  timestamp: 2026-09-30T02:24:07.866764+00:00
- actor: claude-code
  id: 01m3r24azeq3jc5r37p6fn24sd
  text: |-
    ### test — green
    - evidence: `swift test` — 298 tests in 23 suites passed, 0 failed, 0 skipped, 0 warnings. `swift test --package-path IntegrationTests` — 5 tests in 5 suites passed, 0 failed, 0 skipped, 0 warnings.
    - next: review.
  timestamp: 2026-09-30T02:26:06.446150+00:00
- actor: claude-code
  id: 01m3r28bje1jxnd727zgbmkmgp
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (c9fcda9). 0 findings, 0 confirmed, 0 refuted. 7 pairs attempted, 0 failed. 4 files reviewed. 2 .kanban files not reviewed (ignore rule). All prior findings are checked.
    - next: none. The task is in done.
  timestamp: 2026-09-30T02:28:18.126934+00:00
- actor: claude-code
  id: 01m3r28mnzzm2h1bvd23rcrag8
  text: |-
    ### finish iteration 2 — clean
    - implement: changed — 4 files
    - test: green — swift test, 298 passed; IntegrationTests, 5 passed
    - commit: c9fcda9
    - review: clean — 0 findings
  timestamp: 2026-09-30T02:28:27.455623+00:00
position_column: done
position_ordinal: af80
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

## Review Findings (2026-09-29 20:15)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 7 file(s) reviewed, 5 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

> 1 file(s) not reviewed — no validator matched:
> - `docs/GUIDE.md` — no validator matches this file

- [x] `Sources/FoundationModelsRanker/StreamingSearchCorpus.swift:330` `duplication/duplication` — This cosineScores implementation duplicates the identical logic in Searcher's cosineScores method (line 414), differing only by variable name (itemVectors vs itemEmbeddings). The duplicated guard/embed/similarity-check pattern will drift out of sync if either implementation is modified. Extract the guard/embed/similarity-check pattern into a shared helper function parameterized by the item embeddings array, then call it from both Searcher.RetrievalEngine and StreamingSearchCorpus.