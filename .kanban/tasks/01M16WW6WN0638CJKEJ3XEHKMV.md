---
assignees:
- claude-code
depends_on:
- 01M16WVSKBESEYHA6H320D9ZDP
position_column: todo
position_ordinal: '8480'
title: Add a GPU-free demo embedder so the example still shows the cosine signal
---
## What

The deleted `LiveRouter.swift` was the only code that gave the example an embedder. Without an embedder the example never shows the cosine signal, and `Searcher` reports `.embeddingUnavailable` on every query. The README claims cosine is a signal, so the example must still prove it.

Add a small deterministic embedder to the example target. It must need no GPU, no network, and no model. A hashed bag-of-trigrams vector is enough: build a fixed-length `[Float]`, add 1 for each character trigram at index `abs(trigram.hashValue) % dimension`, then normalize to unit length. Use a stable hash of your own, not `String.hashValue`, because `String.hashValue` is seeded per process and would give different vectors on each run.

Files to change:

- `Examples/FullMontyCore/DemoEmbedder.swift` — new file. A `public struct DemoEmbedder: TextEmbedding` with `dimension` (default 256) and `embed(_:)`.
- `Examples/FullMontyCore/Demo.swift` — add `runEmbedderDemo(onDiagnostic:)`. It calls `runFullMontyDemo(embedder:session:mode:limit:onDiagnostic:)` with a `DemoEmbedder` and the default session factory.
- `Examples/FullMonty/main.swift` — add an `--embedder` argument that runs `runEmbedderDemo`. Name the path in the header comment and in the help text.

## Acceptance Criteria

- [ ] `swift run FullMonty --embedder` prints ranked results with a non-zero cosine value in `.signals`, and exits with code 0.
- [ ] `swift run FullMonty --embedder` prints no `.embeddingUnavailable` diagnostic.
- [ ] `DemoEmbedder` needs no GPU and no network.

## Tests

- [ ] Add `Tests/FoundationModelsRankerTests/DemoEmbedderTests.swift`: `embed(_:)` returns one vector per input, each of length `dimension`, in input order.
- [ ] Add a test that two calls of `embed(["same text"])` in the same process give the same vector, and that a second process gives the same vector too. Prove the second part by asserting on a checked-in expected vector prefix, not by starting a process.
- [ ] Add a test that each returned vector has a length of about 1.0, within 1e-5.
- [ ] Add a test to `Tests/FoundationModelsRankerTests/ExamplesSmokeTests.swift` that `runEmbedderDemo` returns one result per demo query and reports no `.embeddingUnavailable`.
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.