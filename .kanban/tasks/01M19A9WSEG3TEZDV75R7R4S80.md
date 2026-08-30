---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m19dz7am59vck6fvf0w2sdag
  text: |-
    Research done. Call ordering in `StreamingSearchCorpus` (it is NOT `Searcher`'s):

    - `add(items:)` makes exactly ONE batched `embedder.embed(_:)` call for each `add` call that adds one or more new ids, and NO call when the add adds nothing new (every id already live).
    - `search(_:limit:)` -> `cosineScores(forQuery:snapshot:)` checks (1) an embedder is configured and (2) every live row in the snapshot carries a stored embedding, both BEFORE it embeds the query. Only then does it make exactly one query-embed call.

    So a corpus streamed one item at a time with the three `runAItems` uses calls 1, 2, 3 for the item embeds, and the first search's query embed is call 4 -> `CountingEmbedder(dimension: 8, failingFromCall: runAItems.count + 1)`. `Searcher` differs: it embeds every item in one call at `init`, so its query embed is call 2.

    Constraint found: `CountingEmbedder` throws from `failingFromCall` onward (permanent for one instance), and `StreamingSearchCorpus` holds `private let embedder` for life. One corpus therefore cannot both fail a query embed and recover on a later search. The recovery test uses a second corpus over the same items, streamed the same way, with a working embedder; the per-search (not latched) claim is also asserted on the failing corpus itself, which reports one diagnostic for each search and keeps answering with keyword-ranked matches.

    Second gap on the card's file: `summaryBlock(forID:)` has no caller in any test.
  timestamp: 2026-08-30T13:33:01.652499+00:00
- actor: claude-code
  id: 01m19e6pr00bx42xcm5ehw76wn
  text: |-
    Implementation landed. One file changed, tests only: `Tests/FoundationModelsRankerTests/StreamingSearchCorpusTests.swift` (+154 lines). No production code changed.

    Four new tests, plus one fixture, one named constant and one helper:
    - `aFailedQueryEmbedDegradesTheStreamingSearchToKeywordOnlyAndReportsTheDiagnosticOncePerSearch` -- the card's target branch. Two searches, so the second one shows the corpus decides again for each search and does not latch.
    - `aLaterSearchWithAWorkingEmbedderRecoversTheCosineSignalTheFailedQueryEmbedDropped` -- the transient-against-permanent claim.
    - `theActorServesTheSummaryLookupForALiveRow` and `theActorAnswersTheSummaryLookupWithNilOnceTheRowIsEvicted` -- the second gap, `summaryBlock(forID:)`.
    - `streamedRunACorpus(embedder:onDiagnostic:)` adds `runAItems` one item for each `add(items:)` call, and `firstStreamedQueryEmbedCall` (= `runAItems.count + 1`) names the call number the query embed takes.

    RED evidence (the tests are written against existing code, so each assertion was proved load-bearing by a temporary mutation, then the mutation was reverted):
    - `firstStreamedQueryEmbedCall` set to `runAItems.count + 100` (the query embed then never throws): both query-embed tests failed, on exactly the cosine-is-zero and diagnostic-count assertions (4 issues).
    - The summary assertions swapped to the other field, and the `remove(ids:)` call deleted: both summary tests failed (3 issues).

    Coverage for `Sources/FoundationModelsRanker/StreamingSearchCorpus.swift`:
    - before: LH 72 of LF 78. Lines with 0 hits: 240, 241, 242 (`summaryBlock(forID:)`), 330, 331 (the query-embed guard).
    - after: LH 77 of LF 78, and every one of those five lines has hits (240-242: 2 hits each; 330-331: 3 hits each). No `DA:` row in the file's record is at 0 hits.
    - `lcov.info` was deleted after the measurement.

    `swift build` clean; `swift test` 278 tests in 22 suites passed, 0 failures, 0 warnings (274 before).

    Constraint worth keeping in mind for a later card: one `CountingEmbedder` throws from `failingFromCall` onward, and `StreamingSearchCorpus` holds `private let embedder` for life, so ONE corpus cannot both fail a query embed and later succeed. The recovery test therefore runs its recovering search on a second corpus over the same items, streamed the same way, with a working embedder; the same-corpus non-latching claim is carried by the two-search assertion in the first test. A same-corpus recovery would need an embedder double that can stop failing, which this card said not to add.
  timestamp: 2026-08-30T13:37:06.816017+00:00
- actor: claude-code
  id: 01m19e6xavngq9y73x5fcnjgkg
  text: |-
    ### implement — changed
    - evidence: 1 file — /Users/wballard/github/swissarmyhammer/FoundationModelsRanker/Tests/FoundationModelsRankerTests/StreamingSearchCorpusTests.swift (+154 lines, 4 new tests). `swift test`: 278 passed / 0 failed / 0 warnings (274 before). Coverage of StreamingSearchCorpus.swift: LH 72/78 -> 77/78; lines 240, 241, 242, 330, 331 went from 0 hits to 2, 2, 2, 3, 3. Call ordering found: `add(items:)` makes one batched embed call for each add that adds new ids, so three one-item adds take calls 1-3 and the first search's query embed is call 4 (`failingFromCall: runAItems.count + 1`); `Searcher` embeds all items in one call at `init`, so its query embed is call 2.
    - next: /review
  timestamp: 2026-08-30T13:37:13.563204+00:00
position_column: doing
position_ordinal: '8180'
title: Add tests for the query-embed failure path in StreamingSearchCorpus
---
## What

`Sources/FoundationModelsRanker/StreamingSearchCorpus.swift`, the query-embed guard in `cosineScores(forQuery:snapshot:)` (line numbers on this card are stale -- find the guard by reading the source).

Coverage: 92.9% (65/70 lines) for the file. Uncovered lines: the `onDiagnostic(.embeddingUnavailable)` and `return nil` pair in that guard.

```swift
guard let queryVector = try? await embedder.embed([query]).first else {
    onDiagnostic(.embeddingUnavailable)   // uncovered
    return nil                            // uncovered
}
```

The same degradation branch as the one in `Searcher.swift`, but on the streaming corpus path, which is the one a caller uses when items arrive over time. It has its own copy of the guard, so a test of the `Searcher` path does not cover it.

Worth testing on its own because the streaming corpus embeds items incrementally: a query-embed failure here happens while the item vectors are already built up, which is a different state from the `Searcher` case.

A second gap in the same file: `summaryBlock(forID:)` had no caller in any test.

## Acceptance Criteria

- [x] The query-embed guard's two lines are covered -- confirmed by re-running coverage, not by inspection.
- [x] The test drives the real streaming path: add items, then search with an embedder that throws only on the query call.
- [x] No production code changes. Tests only.

## Tests

- [x] Add to `Tests/FoundationModelsRankerTests/StreamingSearchCorpusTests.swift`: after adding items with a working embedder, a search whose query embed throws still returns keyword-ranked matches.
- [x] Assert `.embeddingUnavailable` is reported for that search.
- [x] Assert a later search with a working embedder recovers the cosine signal, so the degradation is per-search and not sticky.
- [x] `swift test` passes.

## Workflow
- Use `/tdd` -- write failing tests first, then implement to make them pass. #coverage-gap