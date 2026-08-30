---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m19cq5k8bteqe32bcs4b3zvr
  text: |-
    Picked up. Research done.

    Location: the branch is `RetrievalEngine.cosineScores(forQuery:)` in `Sources/FoundationModelsRanker/Searcher.swift` (a private struct at the foot of the file). The guard reads `guard let queryVector = try? await embedder.embed([query]).first`. `Searcher`'s private designated init embeds every item in ONE batched `embed(_:)` call, and each retrieval search then makes ONE more `embed([query])` call. So call 1 is the item embed at `init` and call 2 is the query embed at search time.

    Existing doubles in `Tests/FoundationModelsRankerTests/Support/`:
    - `FakeEmbedder` — a struct with a `failure:` knob, but it throws on EVERY call, so `init` would throw and no searcher could be built.
    - `GatedEmbedder` — gates on call order but never throws.
    - `MismatchedCountEmbedder` — returns a short vector list, no throw.
    - `CountingEmbedder` — a final class that already lock-boxes a call counter.

    Decision: extend `CountingEmbedder` rather than add a fourth wrapper. The state the new behavior needs (which call number this is) is the state `CountingEmbedder` already holds, so the extension is one optional knob and no new type — the `reuse` rule's "near-match not extended" case. One knob only (`failingFromCall: Int?`), not a `failure:` + `fromCall:` pair, because two fields where only some combinations are valid is the shape `swift/state-modeling` warns about.
  timestamp: 2026-08-30T13:11:09.160883+00:00
- actor: claude-code
  id: 01m19cvjs2d6agt7n8x8ht32v9
  text: |-
    TDD cycle, and the numbers behind it.

    RED: the new test was written first and named `CountingEmbedder(dimension:failingFromCall:)`, which did not exist. `swift test --filter aFailedQueryEmbedDegrades` failed to build with `error: extra argument 'failingFromCall' in call` at `SearcherTests.swift:439` — a failure for the expected reason, the missing capability.

    GREEN: `CountingEmbedder` gained one optional knob, `failingFromCall: Int?` (default `nil`, never fails), plus `CountingEmbedderFailure` as the error it throws. `embed(_:)` now reads the call number out of the lock box it already keeps and throws for each call at or after that number. The two existing call sites in `StreamingSearchCorpusTests` take the default and are unchanged. The filtered run passed, then `swift build` was clean and `swift test` reported 274 tests in 22 suites, zero failures and zero warnings (273 before).

    COVERAGE, measured with the card's own command sequence:
    - before: `Searcher.swift covered: 120 of 125`, uncovered lines 101 102 103 440 441
    - after: `Searcher.swift covered: 122 of 125`, uncovered lines 101 102 103
    - line 439 hits 16, line 440 hits 1, line 441 hits 1

    96.0% -> 97.6% for the file. `lcov.info` was deleted after the read; `git status` shows only the two test files and this card.

    Note for whoever takes the remaining gap: lines 101-103 are still uncovered and belong to a different branch of the file, not to this card.
  timestamp: 2026-08-30T13:13:33.730661+00:00
- actor: claude-code
  id: 01m19cvq2fjfzrcfyyjtynxrse
  text: |-
    ### implement — changed
    - evidence: 2 files — Tests/FoundationModelsRankerTests/SearcherTests.swift (+1 test), Tests/FoundationModelsRankerTests/Support/CountingEmbedder.swift (failingFromCall knob + CountingEmbedderFailure). swift test: 274 tests, 22 suites, 0 failures, 0 warnings. Searcher.swift coverage 120/125 (96.0%) -> 122/125 (97.6%); lines 440 and 441 each hit 1 time. No production code changed.
    - next: /review
  timestamp: 2026-08-30T13:13:38.127210+00:00
position_column: doing
position_ordinal: '8180'
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

- [x] A `TextEmbedding` double exists that succeeds for the item-embedding call at `init` and then throws for the query-embedding call at search time.
- [x] `Searcher.swift:440-441` is covered — confirm by re-running coverage, not by inspection.
- [x] No production code changes. Tests only.

## Tests

- [x] Add to `Tests/FoundationModelsRankerTests/SearcherTests.swift`: with an embedder that throws only on the query call, `search(_:limit:)` still returns keyword-ranked matches rather than throwing or returning empty.
- [x] Assert `.embeddingUnavailable` is reported exactly once for that search, via a `DiagnosticRecorder`.
- [x] Assert the returned matches carry a cosine signal of `0.0`, so the caller can tell the signal did not contribute.
- [x] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #coverage-gap