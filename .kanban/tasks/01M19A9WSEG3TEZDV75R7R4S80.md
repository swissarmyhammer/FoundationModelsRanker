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
- actor: claude-code
  id: 01m19e92qqcak9y08t6ty3azpt
  text: |-
    ### commit — changed
    - evidence: 4785d16 test(streaming-search-corpus): add tests for the query-embed failure path — 5 files changed (2 test/kanban files for this task, plus a related task's kanban files, and the test file)
    - next: /review
  timestamp: 2026-08-30T13:38:24.631631+00:00
- actor: claude-code
  id: 01m19ejayapvx6na8g3cw39sa0
  text: |-
    ### review — findings
    - evidence: `review sha HEAD~1..HEAD` gave 0 findings, 0 confirmed, 0 refuted, from 7 validators. The 4 kanban files are not in the review scope. 1 finding from the review pass: /Users/wballard/github/swissarmyhammer/FoundationModelsRanker/Tests/FoundationModelsRankerTests/StreamingSearchCorpusTests.swift:532 -- the recovery test uses a second corpus, thus it does not show that the degradation applies to one search only. Verified with no finding: the call order (3 `runAItems`, thus the query embed is call 4, and the tests hit the query-embed guard and not the row-completeness guard); one load-bearing assertion (the removal of `onDiagnostic(.embeddingUnavailable)` from the query-embed guard made the test fail with 2 issues, and the source was put back); test code only (commit 4785d16 changes no file in `Sources/`). `rm -rf .build/out && swift build --build-tests`: Build complete.
    - next: correct the finding, then /review again
  timestamp: 2026-08-30T13:43:27.946506+00:00
- actor: claude-code
  id: 01m19ekfa7xcjjm2mjzdmxz5pk
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — StreamingSearchCorpusTests.swift, +154 lines, 4 new tests; CountingEmbedder reused, no new double
    - test: green — folded into the implement step's own run: swift build clean, swift test 278 passed / 0 failed / 0 warnings (274 before), coverage re-measured
    - commit: 4785d16 — 5 files changed
    - review: findings — 1 open, StreamingSearchCorpusTests.swift:532, the recovery test does not establish non-stickiness
    - next: implement iteration 2 gives CountingEmbedder a bounded failure window so one corpus can fail and then recover

    Coverage moved as claimed: StreamingSearchCorpus.swift 72/78 → 77/78, lines 240-242 and 330-331 from zero hits. The reviewer independently ran a mutation — deleting only `onDiagnostic(.embeddingUnavailable)` from the query-embed guard — and the target test failed with the count at 0, which proves the test reaches that specific guard and not an earlier one.

    Orchestrator note on the finding: my card said "do not add another embedder double", and the implementer read that as forbidding a bounded failure window. The reviewer is right that this reading is too broad. The rule was about not creating a fourth near-copy, and about not touching production code. Extending `CountingEmbedder` with a failure window is test-only and is exactly the shape the earlier card `^he0e2re` already used when it added `failingFromCall:`.
  timestamp: 2026-08-30T13:44:05.191158+00:00
- actor: claude-code
  id: 01m19ex8y043k8fz8ncbrdzd4a
  text: |-
    Iteration 2. The open review finding is corrected. Two test files changed, no file in `Sources/`.

    `CountingEmbedder` (`Tests/FoundationModelsRankerTests/Support/CountingEmbedder.swift`) now takes a bounded failure window:
    - New `recoveringAtCall: Int? = nil`, beside the existing `failingFromCall: Int? = nil`. The two numbers make the half-open window `failingFromCall ..< recoveringAtCall` of the calls that throw.
    - A new private `fails(callNumber:)` holds the window logic, thus `embed(_:)` stays flat.
    - `recoveringAtCall: nil` gives exactly the old behavior: the failure has no end. Each existing caller keeps `failingFromCall:` alone -- `SearcherTests` (from card ^he0e2re) and the other `StreamingSearchCorpusTests` sites -- and none of them changed.

    `aLaterSearchWithAWorkingEmbedderRecoversTheCosineSignalTheFailedQueryEmbedDropped` is now `aLaterSearchOnTheSameCorpusRecoversTheCosineSignalTheFailedQueryEmbedDropped`. It builds ONE corpus with ONE embedder whose failure window is exactly one call:
    - `failingFromCall: firstStreamedQueryEmbedCall` (call 4, the query embed of search 1)
    - `recoveringAtCall: secondStreamedQueryEmbedCall` (call 5, the query embed of search 2)

    Search 1 degrades: no cosine, one diagnostic. Search 2, on the same actor, with the same items, the same stored vectors and the same query, gets the real cosine of each match and adds NO diagnostic. Nothing but the health of the embedder changes between the two searches.

    New fixture `secondStreamedQueryEmbedCall = firstStreamedQueryEmbedCall + 1`, so no bare `+ 1` sits in the test body.

    MUTATION EVIDENCE -- the test can fail. A temporary latch was put in `StreamingSearchCorpus.swift`: a `private var cosineIsBroken` set to `true` in the query-embed guard, plus an early `if cosineIsBroken { onDiagnostic(.embeddingUnavailable); return nil }` at the top of `cosineScores(forQuery:snapshot:)` -- the "cosine is broken, skip it" cache the reviewer named. With that latch:

    - `aLaterSearchOnTheSameCorpusRecoversTheCosineSignalTheFailedQueryEmbedDropped` FAILED with 5 issues: three at the per-match cosine equality, one at `recoveredMatches.contains { cosine != 0.0 }`, and one at the closing diagnostic count (1 expected, 2 seen).
    - `aFailedQueryEmbedDegradesTheStreamingSearchToKeywordOnlyAndReportsTheDiagnosticOncePerSearch` PASSED under the same latch. This confirms the finding word for word: the two-search assertion of that test does not close the hole, and only the new same-corpus test does.

    The latch was then removed with `git checkout -- Sources/FoundationModelsRanker/StreamingSearchCorpus.swift`. `git status` shows nothing under `Sources/`.

    Coverage of `Sources/FoundationModelsRanker/StreamingSearchCorpus.swift` holds at 77 of 78 lines (98.72%). The query-embed guard keeps its hits (3 each on the `onDiagnostic` line and the `return nil` line), and `summaryBlock(forID:)` keeps 2 hits on each of its three lines.

    `swift build` clean. `swift test`: 278 tests in 22 suites passed, 0 failures, 0 warnings. The count stays at 278 because the recovery test was rewritten, not added.
  timestamp: 2026-08-30T13:49:26.336460+00:00
- actor: claude-code
  id: 01m19ez69vfbwd51dkp48dr7sf
  text: |-
    One more correction in the same file, from the same cause. The doc comment on `aFailedQueryEmbedDegradesTheStreamingSearchToKeywordOnlyAndReportsTheDiagnosticOncePerSearch` claimed its second search "shows the corpus takes the decision again for each search rather than latching". The mutation run disproves that claim: that test passed with the latch in place. The comment now says what the second search really shows -- the corpus keeps ranking and reports one diagnostic for each failed search -- and points to the new recovery test for the proof of no latch.

    ### implement — changed
    - evidence: 2 files, tests only. /Users/wballard/github/swissarmyhammer/FoundationModelsRanker/Tests/FoundationModelsRankerTests/Support/CountingEmbedder.swift (`recoveringAtCall:` window plus a private `fails(callNumber:)`), /Users/wballard/github/swissarmyhammer/FoundationModelsRanker/Tests/FoundationModelsRankerTests/StreamingSearchCorpusTests.swift (`secondStreamedQueryEmbedCall` fixture, the same-corpus recovery test, one corrected doc comment). MUTATION: a `cosineIsBroken` latch put in `StreamingSearchCorpus.swift` made `aLaterSearchOnTheSameCorpusRecoversTheCosineSignalTheFailedQueryEmbedDropped` fail with 5 issues (3 cosine equalities, 1 non-zero cosine, 1 diagnostic count 1 against 2), while `aFailedQueryEmbedDegrades...OncePerSearch` passed. The latch was reverted; `git status` shows nothing under `Sources/`. `swift build` clean. `swift test`: 278 tests in 22 suites passed, 0 failures, 0 warnings. Coverage of StreamingSearchCorpus.swift 77/78 (98.72%), query-embed guard 3 hits on each line.
    - next: /review
  timestamp: 2026-08-30T13:50:29.179314+00:00
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

## Review Findings (2026-08-30 08:45)

> Scope: `review sha HEAD~1..HEAD` -- the added and changed lines only. The engine gave 0 findings from 7 validators. The item below comes from the review pass, which examined the three claims of the implementer.

- [x] `Tests/FoundationModelsRankerTests/StreamingSearchCorpusTests.swift:532` `review/tests` -- The recovery test makes a second corpus. Thus the test does not show that the degradation applies to one search only. The second corpus never had a failed query embed. Thus the test also gives a pass if `StreamingSearchCorpus` keeps the failure for all later searches. The two searches in `aFailedQueryEmbedDegradesTheStreamingSearchToKeywordOnlyAndReportsTheDiagnosticOncePerSearch` do not close this hole, because the query embed of each of these two searches fails. To correct this, give `CountingEmbedder` a limited failure window, for example a set of call numbers that fail. This is a change to test code only, and the card permits it. Then let one corpus fail the query embed of its first search and complete the query embed of its second search. Assert the cosine signal on the second search of that same corpus.

Verified in this pass, with no finding:

- The call order is correct. `add(items:)` makes one batched embed call for each add that adds new ids (`StreamingSearchCorpus.swift`, the `guard let embedder, !addedIDs.isEmpty` line and the `embedder.embed` line after it). `cosineScores(forQuery:snapshot:)` tests the embedder and the row completeness before it embeds the query. `runAItems` holds 3 items, thus `firstStreamedQueryEmbedCall` is 4, and the tests hit the query-embed guard and not the row-completeness guard.
- One assertion is load-bearing. The review pass removed `onDiagnostic(.embeddingUnavailable)` from the query-embed guard only. `aFailedQueryEmbedDegradesTheStreamingSearchToKeywordOnlyAndReportsTheDiagnosticOncePerSearch` then failed with 2 issues, at the two diagnostic-count assertions. The count went to 0. This also proves that the test reaches the query-embed guard. The source was put back to its committed state after the test.
- The change is test code only. Commit `4785d16` changes `Tests/FoundationModelsRankerTests/StreamingSearchCorpusTests.swift` and the kanban records only. No file in `Sources/` is changed.