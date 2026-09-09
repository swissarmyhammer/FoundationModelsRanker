---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m242yc8qn6y84hbz6mren915
  text: |-
    ### implement — picked up

    Research results:

    - Baseline: `swift test` at the root passes 279 tests in 22 suites, with no warnings.
    - `SelectionTier.search(intent:limit:)` calls `retrievalRanking(intent)` after the model answer under budget, and before the prompt over budget. `matches(forIDs:limit:allowedIDs:retrievalMatches:)` copies the retrieval `score` and `signals` onto each pick.
    - `Searcher` gives the tier `RetrievalEngine.fullOrdering` as `retrievalRanking`. That function embeds the query and reports `.embeddingUnavailable` when no embedder is set. So a selection search reports a retrieval diagnostic today.
    - `SelectionConfig.candidateLimit` and `defaultCandidateLimit` size the retrieval cut only. With no cut, they have no function. `Searcher` passes `candidateLimit:` through three initializers.
    - `RankDiagnostic.retrievalCut` is emitted in `overBudgetSearch` only. `ExamplesSmokeTests.everyDiagnostic` lists it and `SelectionCoreTests` compares it.
    - External consumer `FoundationModelsMetadataRegistry` depends on this package on the remote `main` branch. Its `MetadataSearcher` calls `SelectionTier(catalog:config:onDiagnostic:retrievalRanking:)`, and its `Diagnostics.swift` switches over `.retrievalCut`. Its tests pass `candidateLimit:` to `SelectionConfig`. Its production code does not use `candidateLimit`. `FoundationModelsMultitool`, `FoundationModelsCodeContext`, and `CodeContextKit` do not name any of these symbols.
    - The nested `IntegrationTests` package builds `SelectionTier` with `retrievalRanking:` in `SelectionTierRealModelTests`, and `LiveToolCatalog.everyEntryRanked()` exists for that argument only.
    - `README.md` "Modes" says a selection pick carries the fused retrieval score and that the over-budget path seeds itself from the top retrieval candidates. `plan.md` phase 3 describes the over-budget retrieval top-M and the `candidateLimit:` knob.

    Design decisions:

    - Over budget: split the catalog ids, in catalog order, into runs whose assembled prefix each fits `capacityCharacterLimit`. Send one prompt for each run. Merge the answered ids in run order, then in the model's order inside each run. Every id reaches one prompt. A single entry larger than the budget gets a prompt of its own.
    - A selection pick gets `score = 1 / rank` (the first pick is 1.0, the n-th pick is 1/n) and `signals = nil`. The order of the result is the model's order.
    - Keep `RankDiagnostic.retrievalCut` and document it as never emitted, so the consumer's exhaustive switch still compiles. Keep a deprecated `SelectionTier` initializer that accepts `retrievalRanking:` and ignores it, so the consumer's `.selection` and `.auto` modes still compile. Remove `candidateLimit` from `SelectionConfig` and `Searcher`, because no production code uses it after this change.
  timestamp: 2026-09-09T21:59:49.271413+00:00
- actor: claude-code
  id: 01m243wsk97zdhkfbm52t6e2vc
  text: |-
    ### implement — changed

    What changed:

    - `Sources/FoundationModelsRanker/Selection/SelectionTier.swift`: `search` makes one prompt and no retrieval pass. Under budget the cached root is forked one time and the answer is the result. Over budget the catalog ids are split into runs whose prefix each fits `capacityCharacterLimit` (`candidateRuns(preamble:catalog:limit:)`), one prompt goes out for each run, and the answers merge in run order. A pick gets `score = 1 / rank` and `signals = nil`. The initializer is `init(catalog:config:onDiagnostic:)`. A deprecated `init(catalog:config:onDiagnostic:retrievalRanking:)` ignores the closure, so `FoundationModelsMetadataRegistry` still compiles.
    - `Selection/SelectionConfig.swift`: `candidateLimit` and `defaultCandidateLimit` are removed.
    - `Selection/RankDiagnostic.swift`: `.retrievalCut` stays declared and is documented as never emitted.
    - `Selection/SelectionMatch.swift`, `Selection/SelectionCatalog.swift`, `StreamingSearchCorpus.swift`: doc comments follow the new behavior.
    - `Searcher.swift`: no `candidateLimit:` parameter, the tier is built with the new initializer, `RetrievalEngine.fullOrdering` and `rankedMatches` are gone. A selection search embeds no query and reports no `.embeddingUnavailable`.
    - `README.md` "Modes" and `plan.md` (§3a knob list, §6 phase 3 amendment) describe the one-prompt design.
    - Tests: `OverBudgetTests.swift` is rewritten for the split design. `SelectionTests.swift`, `SearcherTests.swift`, `SelectionConfigTests.swift`, `ExamplesSmokeTests.swift`, `ReadmeExampleTests.swift`, `AgentSessionDispatchTests.swift` follow the new API and the order scores. New `Support/OrderScores.swift` names the expected scores. `IntegrationTests` drops `retrievalRanking:` and the `everyEntryRanked()` helper.

    TDD record: the test edits came first. `swift build --build-tests` failed with `missing argument for parameter 'retrievalRanking'` (RED). After the production edits one test failed because `## filler3` is a prefix of `## filler30`; the assertion now matches the heading line `## <id>\n`. One deprecation warning came from `AgentSessionDispatchTests.swift`, which an exclusion glob had hidden from my search; it now uses the new initializer.

    Design decision recorded in the doc comment of `search`: split the catalog into prompts, do not raise the budget. Every id reaches exactly one prompt. An entry larger than the budget gets a prompt of its own.

    Follow-up task: `^6kd63xc` records the downstream update `FoundationModelsMetadataRegistry` needs in its own repository (new initializer, `candidateLimit:` removed from its tests).

    - evidence: `swift test` at the root: 282 tests in 22 suites pass, 0 failures, 0 warnings, exit 0. `swift build --package-path IntegrationTests --build-tests`: build complete, exit 0. Files changed: Sources/FoundationModelsRanker/Selection/SelectionTier.swift, Sources/FoundationModelsRanker/Selection/SelectionConfig.swift, Sources/FoundationModelsRanker/Selection/RankDiagnostic.swift, Sources/FoundationModelsRanker/Selection/SelectionMatch.swift, Sources/FoundationModelsRanker/Selection/SelectionCatalog.swift, Sources/FoundationModelsRanker/Searcher.swift, Sources/FoundationModelsRanker/StreamingSearchCorpus.swift, Tests/FoundationModelsRankerTests/OverBudgetTests.swift, Tests/FoundationModelsRankerTests/SelectionTests.swift, Tests/FoundationModelsRankerTests/SearcherTests.swift, Tests/FoundationModelsRankerTests/SelectionConfigTests.swift, Tests/FoundationModelsRankerTests/ExamplesSmokeTests.swift, Tests/FoundationModelsRankerTests/ReadmeExampleTests.swift, Tests/FoundationModelsRankerTests/AgentSessionDispatchTests.swift, Tests/FoundationModelsRankerTests/Support/OrderScores.swift (new), IntegrationTests/Tests/FoundationModelsRankerIntegrationTests/SelectionTierRealModelTests.swift, IntegrationTests/Tests/FoundationModelsRankerIntegrationTests/Support/LiveToolCatalog.swift, README.md, plan.md.
    - next: `/review`.
  timestamp: 2026-09-09T22:16:25.961718+00:00
- actor: claude-code
  id: 01m2440qpy2aefsdq01k8gmfkn
  text: |-
    ### test — green
    - evidence: `swift package reset && swift test` at /Users/wballard/github/swissarmyhammer/FoundationModelsRanker — 282 tests passed, 0 failed, 0 skipped, 0 warnings. `swift build --package-path IntegrationTests --build-tests` — build complete, 0 warnings, 0 errors.
    - next: no action needed. The build is clean.
  timestamp: 2026-09-09T22:18:35.102284+00:00
position_column: doing
position_ordinal: '80'
title: 'SelectionTier: one prompt that picks. Remove the retrieval ranking after the answer and the retrieval cut before it'
---
## What

The path of `SelectionTier.search(intent:limit:)` today (`Sources/FoundationModelsRanker/Selection/SelectionTier.swift` lines 142-163 in the checkout of 2026-09-09):

1. Under budget (prefix <= `capacityCharacterLimit`, 32,000 chars): fork the cached root session, send `# Task\n\n<intent>`, decode the ids. Then `retrievalRanking(intent)` (line 157) runs BM25 + trigram + cosine over the whole catalog, only to attach `score` and `signals` to the selected ids. It never changes the ids.
2. Over budget: `retrievalRanking` first, cut to the top M, a one-off session over those candidates, prompt, decode, rank.

So the path is: retrieve (over budget), then prompt, then rank. The user of the consumer packages wants one prompt that picks, and nothing else.

## What the one-prompt design removes

- The `retrievalRanking` pass after the answer under budget. Without it the selection path needs no embedder and no BM25 index, and the `.embeddingUnavailable` diagnostic cannot come from a selection search.
- The retrieval cut over budget. With description-only summaries (see the consumer measurement) the prefix is 44% of its size today, so the budget is reached much later. Over budget, decide: split the candidates into several prompts and merge the ids, or raise the budget. Do not rank with retrieval to pick the candidates.
- The `score` and `signals` of a `SelectionMatch` from the under-budget path become the model's order (position), not a fused retrieval score. The card "Attach real fused score/signals to under-budget selection matches" put them there; this card reverses that for selection mode.

## Measurement in the consumer (FoundationModelsMultitool card ^zqz1zan)

- Catalog: 9 tool entries (files read/write/edit/patch/glob/grep, shell execute/getLines/grepHistory). Full prefix 17,263 chars with the consumer's preamble (356 chars). Description-only summaries: 7,232 chars in total, so a description-only prefix of about 7,600 chars.
- On `mlx-community/Qwen3-4B-4bit` the under-budget path answered all ten agent queries with the consumer's preamble. The retrieval pass after the answer changed nothing but the scores.

## Where to look

- `Selection/SelectionTier.swift`: `search(intent:limit:)`, `retrievalRanking`, `matches(forIDs:limit:allowedIDs:retrievalMatches:)`, the over-budget path.
- `Selection/SelectionConfig.swift`: `capacityCharacterLimit`.
- `SearchItem.swift` line 51: `summary` is the seam a consumer fills with a description-only text; the prefix already uses it (`candidateEntry(forID:catalog:)`).

## Acceptance Criteria

- [x] Under budget, `search` makes one model call and no retrieval pass. The order of the answer is the model's order.
- [x] Over budget, no retrieval cut picks the candidates. The design chosen (several prompts, or a larger budget) is written in the doc comment of `search`.
- [x] `RankDiagnostic.retrievalCut` is removed, or documented as unreachable from selection mode.
- [x] The consumers (`FoundationModelsMetadataRegistry` modes `.selection` and `.auto`) still compile, and `.auto` with a selection tier never runs retrieval.

## Tests

- [x] A unit test with a recording `AgentSession` and a catalog under budget asserts exactly one `respond` call and no embedder call.
- [x] A unit test over budget asserts the chosen design (every id reaches a prompt).
