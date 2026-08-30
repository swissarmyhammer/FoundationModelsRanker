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
- actor: claude-code
  id: 01m19cyf1mpqdzkvtsy7exr56f
  text: |-
    ### commit — changed
    - evidence: 2ddd6f4 test(searcher): cover the query-embed failure path in the cosine signal
    - next: /review
  timestamp: 2026-08-30T13:15:08.212610+00:00
- actor: claude-code
  id: 01m19dah537z2smgwk66zdjaxt
  text: |-
    ### review — findings
    - evidence: 1 finding (1 confirmed, 1 refuted, 7 attempted) — Tests/FoundationModelsRankerTests/SearcherTests.swift:451. Scope: `review sha HEAD~1..HEAD` (commit 2ddd6f4). The stale Periphery index was removed before the run: `rm -rf .build/out && swift build --build-tests` completed with exit code 0.
    - merit checks made by hand:
      - Call order is correct. `Searcher.swift:275` embeds all items in ONE batched `embedder.embed(_:)` call at `init` (call 1). `Searcher.swift:439` embeds the query in ONE call for each search (call 2). Therefore `failingFromCall: 2` lets `init` complete and fails only the query embed. The test lands on lines 440-441, not on the adjacent no-embedder guard at line 436.
      - The test holds the production branch. If line 440 (`onDiagnostic(.embeddingUnavailable)`) is removed, the assertion at line 455 (`count == 1`) fails. If line 441 (`return nil`) is removed, the cosine assertion at line 453 fails.
      - The cosine assertion reads a real value. `matches.first?.signals?.cosine == 0.0` compares an optional with `0.0`. A `nil` signals value gives `false` and fails the test. Line 451 asserts `bm25 > 0.0` on the same chain, which proves the signals value is present and holds true numbers. The `0.0` is therefore a read of a real signal, not a value that is true for any input.
      - The two other `CountingEmbedder` call sites are not affected. `StreamingSearchCorpusTests.swift:196` and `:266` both use `CountingEmbedder(dimension: 8)`. The new parameter defaults to `nil`, and `embed(_:)` then increments the counter and delegates to the wrapped fake, exactly as before. `callCount` keeps the same value.
      - No production source was changed. `git show --stat 2ddd6f4` lists only two test files and the two kanban files.
    - next: correct the parentheses on SearcherTests.swift lines 450 and 451, then /review again.
  timestamp: 2026-08-30T13:21:43.587906+00:00
- actor: claude-code
  id: 01m19dbfe2my9wmh638annc6p1
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 2 test files; CountingEmbedder gains `failingFromCall:`, one new test for the query-embed failure path
    - test: green — folded into the implement step's own run: swift build clean, swift test 274 passed / 0 failed / 0 warnings (was 273), and coverage re-measured with the card's own command sequence
    - commit: 2ddd6f4 — 4 files changed
    - review: findings — 1 open, SearcherTests.swift:451 with the same cause at :450
    - next: implement iteration 2 applies the parentheses to both lines

    Coverage moved as claimed: Searcher.swift 120/125 (96.0%) → 122/125 (97.6%), lines 440-441 from zero hits to one each. The reviewer confirmed the test holds the branch — removing either production line breaks an assertion.
  timestamp: 2026-08-30T13:22:14.594399+00:00
- actor: claude-code
  id: 01m19deatxsvr0dnmjc13xqhb2
  text: |-
    Iteration 2. The open finding is corrected, and the same cause is removed from the whole file.

    Scan result: 3 instances of the construct — a nil-coalescing expression used as one side of a comparison, with no parentheses. All 3 are in `Tests/FoundationModelsRankerTests/SearcherTests.swift`:

    - line 172 `#expect(matches.first?.score ?? 0.0 > 0.0)` — in `selectionModeOverBudgetSeedsAOneOffSessionFromRetrievalTopCandidates`. Not named in the finding, corrected because the cause is the same.
    - line 450 `#expect(matches.first?.score ?? 0.0 > 0.0)`
    - line 451 `#expect(matches.first?.signals?.bm25 ?? 0.0 > 0.0)`

    Each becomes `#expect((<expression> ?? 0.0) > 0.0)`. Only the grouping changes. `NilCoalescingPrecedence` is declared `higherThan: ComparisonPrecedence`, so each expression already parsed this way; the parentheses make the grouping visible to the reader and change no assertion.

    `Tests/FoundationModelsRankerTests/Support/CountingEmbedder.swift` was read whole: it holds no `??` operator at all, so it holds 0 instances.

    A second grep of the full test target for `??` followed by a comparison operator now finds nothing.

    Counts, before and after the edit, from the same command pair (`swift build` then `swift test`):
    - before: build complete, 274 tests in 22 suites passed, 0 failures, 0 warnings
    - after: build complete, 274 tests in 22 suites passed, 0 failures, 0 warnings

    The counts are identical, which shows the edit changed no behavior.
  timestamp: 2026-08-30T13:23:48.189509+00:00
- actor: claude-code
  id: 01m19dees7bswcn54s0h63pp5j
  text: |-
    ### implement — changed
    - evidence: 1 file — Tests/FoundationModelsRankerTests/SearcherTests.swift. 3 instances of the construct corrected (lines 172, 450, 451); Support/CountingEmbedder.swift holds 0 instances. swift build clean. swift test before: 274 tests, 22 suites, 0 failures, 0 warnings. swift test after: 274 tests, 22 suites, 0 failures, 0 warnings.
    - next: /review
  timestamp: 2026-08-30T13:23:52.231991+00:00
- actor: claude-code
  id: 01m19dm4tpya7e8ez3c58rj0n1
  text: |
    ### review — clean
    - evidence: zero new findings (0 findings, 0 confirmed, 0 refuted, 7 attempted, 0 failed). Scope: `review sha HEAD~1..HEAD` (commit 6a53f8a). The stale index was removed before the run: `rm -rf .build/out && swift build --build-tests` gave exit code 0.
    - prior finding: the item for `SearcherTests.swift:451` is checked and the correction is in the commit. The same cause is removed from the whole file, at lines 172, 450 and 451.
    - merit checks made by hand:
      - The change is grouping only. `git show HEAD -- Sources Tests` gives 3 changed line pairs, all in `Tests/FoundationModelsRankerTests/SearcherTests.swift`. Each pair moves `X ?? 0.0 > 0.0` to `(X ?? 0.0) > 0.0`. No assertion, no operand and no comparison operator changed.
      - No production source changed. `git show --stat HEAD` lists one test file and the two kanban files only.
      - The suite counts are the same. `swift test` reports 274 tests in 22 suites, 0 failures, exit code 0. This equals the count before the change, so no assertion changed its meaning.
      - The cause is gone from the whole test target. A grep of `Tests/` for a nil-coalescing operator next to a comparison operator finds nothing.
    - next: task is done
  timestamp: 2026-08-30T13:26:58.646661+00:00
- actor: claude-code
  id: 01m19dmphqwmfyn6vchfxn2wf6
  text: |-
    ### finish iteration 2 — clean
    - implement: changed — SearcherTests.swift; parentheses added at 3 sites (172, 450, 451), grouping only
    - test: green — swift test 274 passed / 0 failed / 0 warnings, identical to before the change, which is what proves no assertion changed meaning
    - commit: 6a53f8a4 — 3 files changed
    - review: clean — zero findings; the prior finding is resolved and the cause is gone from the whole test target
    - next: none — task is in done
  timestamp: 2026-08-30T13:27:16.791942+00:00
position_column: done
position_ordinal: a180
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

## Review Findings (2026-08-30 08:16)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 2 file(s) reviewed, 2 not reviewed.

> 2 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 2 file(s)

- [x] `Tests/FoundationModelsRankerTests/SearcherTests.swift:451` `swift/idioms` — Same operator precedence issue as line 450: `??` has lower precedence than `>`, so this expression parses as `matches.first?.signals?.bm25 ?? (0.0 > 0.0)`, attempting to use a `Bool` as the default for an optional `Double`. Wrap the nil-coalescing in parentheses: `#expect((matches.first?.signals?.bm25 ?? 0.0) > 0.0)`.

### Notes for the implementer

- The finding gives one example of a cause. The same construct is on line 450. Correct both lines, not only line 451.
- The reason text in the finding is not correct. In Swift, `NilCoalescingPrecedence` is declared `higherThan: ComparisonPrecedence`, so `a ?? 0.0 > 0.0` parses as `(a ?? 0.0) > 0.0`. A compiled check gives type `Bool` and value `true`, and the test target builds. The code is therefore correct today.
- The suggested correction is still safe and makes the code easier to read. Add the parentheses on both lines. Do not change what the test asserts.