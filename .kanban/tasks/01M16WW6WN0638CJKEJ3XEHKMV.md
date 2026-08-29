---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m16zqsc1j2bqtf856stgzcqh
  text: |
    ### Research before writing

    Read `Examples/FullMontyCore/Demo.swift`, `Examples/FullMonty/main.swift`, `Sources/FoundationModelsRanker/Searcher.swift`, `Selection/SelectionTier.swift`, `Selection/SelectionConfig.swift`, `SearchCorpus.swift`, `SearchItem.swift`, and `Tests/FoundationModelsRankerTests/Support/FakeEmbedder.swift`.

    Discoveries:

    1. `Tests/FoundationModelsRankerTests/Support/FakeEmbedder.swift` already holds a stable FNV-1a hash of a text's UTF-8 bytes, with a comment that says why `Hasher` is unusable (it is seeded for each process). `DemoEmbedder` must use the same kind of stable hash. That file is a test-target double, so the example target cannot use it.

    2. `Sources/FoundationModelsRanker/Tokenizer.charTrigrams(text:)` is `public`, so `DemoEmbedder` can reuse it for the character trigrams instead of writing a new window function.

    3. The default on-device path gives no matches today. `swift run FullMonty` was measured on this machine: the model answers, but every answer is an item DESCRIPTION, not an id, so each query reports `unknownSelectedId` and prints `(no matches)`.

       The cause is two facts together:
       - `Searcher.init` builds `SelectionConfig(model: { instructions, _ in session(instructions) })`, which DISCARDS the `Grammar` the selection tier computes. The id-enum constraint therefore never reaches the model. Task ^4kx83sx ("Remove the Grammar argument from the selection session seam") owns that.
       - `SelectionTier.assemblePrefix` renders `summaryBlock(forID:)` only, and `Searchable.summary` defaults to `text`. `toolCatalog` supplies no explicit summary, so the assembled prefix carries the descriptions and NO ids at all. The model cannot name an id it never saw.

       Measured output of `swift run FullMonty` (4 queries, exit 0):
       `[diagnostic] unknownSelectedId(id: "Search file contents with regular expressions")` and `Query: ... (no matches)` for every query.
  timestamp: 2026-08-29T14:45:49.057354+00:00
- actor: claude-code
  id: 01m1702vb5cqmeme7d9z1gar44
  text: |
    ### Deviation from the What section, agreed with the coordinator

    The What section says `runEmbedderDemo` calls `runFullMontyDemo` with a `DemoEmbedder` **and the default session factory**. That cannot stand beside acceptance criterion 1, for the reason the research comment above measures: with a session configured, `mode: .auto` answers through the selection tier, the assembled prefix shows the model no ids, and every query prints `(no matches)`. Acceptance criterion 1 asks for ranked results with a non-zero cosine.

    Agreed answer: `runEmbedderDemo` passes `mode: .retrieval` and no session.

    Why:
    - `--embedder` exists to prove the cosine signal, and cosine is a retrieval-tier signal. Selection is not what the flag demonstrates.
    - `.retrieval` makes every acceptance criterion on the card reachable with no model.
    - The `ExamplesSmokeTests` test for `runEmbedderDemo` then needs no Apple Intelligence, so it stays in the unit target. The `test-partitioning` validator names a unit-target test that drives a real model an integration test in the wrong target.
    - `.retrieval` never consults a session, so passing one would be configuration the path can never reach. `session: nil` states the truth.

    The prefix-id defect the research found is card ^g69hyyc ("Render each candidate id in the assembled selection prefix"). It is not fixed here.
  timestamp: 2026-08-29T14:51:51.525874+00:00
- actor: claude-code
  id: 01m170bxd59cxehd6xej4778y7
  text: |
    ### implement — changed

    - evidence: 4 files.
      - `Examples/FullMontyCore/DemoEmbedder.swift` — new. `public struct DemoEmbedder: TextEmbedding`, `defaultDimension` 256, clamped `dimension`. `embed(_:)` reuses the public `Tokenizer.charTrigrams(text:)`, adds 1 for each trigram at `FNV-1a(trigram UTF-8) % dimension`, then normalizes to unit length. The hash is written out, never `String.hashValue` or `Hasher`, and the doc comment says why.
      - `Examples/FullMontyCore/Demo.swift` — added `runEmbedderDemo(onDiagnostic:)` with `mode: .retrieval` and `session: nil`; updated `runFullMontyDemo`'s doc comment from two paths to three.
      - `Examples/FullMonty/main.swift` — added the `--embedder` branch; rewrote the header comment for three paths; added the `--embedder` line to the default path's help text.
      - `Tests/FoundationModelsRankerTests/DemoEmbedderTests.swift` — new, 6 tests.
      - `Tests/FoundationModelsRankerTests/ExamplesSmokeTests.swift` — 3 `--embedder` tests, plus the doc comment now names the third path.

    - TDD: the tests were written first and the build failed with `cannot find 'DemoEmbedder' in scope` on 6 lines before any example code existed.

    - The checked-in expected vector was computed OUTSIDE this repository, by an independent reference of the documented algorithm written before the Swift code. The Swift implementation reproduced it to 1e-6 on the first run, so the two agree without either being fitted to the other.

    - Measured:
      - `swift test` — 252 tests in 21 suites passed, 0 failures. The only build warning is the pre-existing `mlx-swift_Cmlx.bundle` line, which card ^2q0p8gr removes with the MLX dependency.
      - `swift run FullMonty --embedder` — exit 0, ranked results, 0 `embeddingUnavailable` lines. Top match and cosine for each query: `grep` 0.722, `commit` 0.638, `branch` 0.439, `stash` 0.849.
      - Two separate `swift run FullMonty --embedder` processes wrote byte-identical output, which is the cross-process determinism the card asks for.
      - `swift run FullMonty --no-model` — exit 0, unchanged.

    - next: `/review`.
  timestamp: 2026-08-29T14:56:48.549276+00:00
depends_on:
- 01M16WVSKBESEYHA6H320D9ZDP
position_column: doing
position_ordinal: '80'
title: Add a GPU-free demo embedder so the example still shows the cosine signal
---
## What

The deleted `LiveRouter.swift` was the only code that gave the example an embedder. Without an embedder the example never shows the cosine signal, and `Searcher` reports `.embeddingUnavailable` on every query. The README claims cosine is a signal, so the example must still prove it.

Add a small deterministic embedder to the example target. It must need no GPU, no network, and no model. A hashed bag-of-trigrams vector is enough: build a fixed-length `[Float]`, add 1 for each character trigram at index `abs(trigram.hashValue) % dimension`, then normalize to unit length. Use a stable hash of your own, not `String.hashValue`, because `String.hashValue` is seeded per process and would give different vectors on each run.

Files to change:

- `Examples/FullMontyCore/DemoEmbedder.swift` — new file. A `public struct DemoEmbedder: TextEmbedding` with `dimension` (default 256) and `embed(_:)`.
- `Examples/FullMontyCore/Demo.swift` — add `runEmbedderDemo(onDiagnostic:)`. It calls `runFullMontyDemo(embedder:session:mode:limit:onDiagnostic:)` with a `DemoEmbedder` and the default session factory.
- `Examples/FullMonty/main.swift` — add an `--embedder` argument that runs `runEmbedderDemo`. Name the path in the header comment and in the help text.

**Deviation, agreed with the coordinator:** `runEmbedderDemo` passes `mode: .retrieval` and `session: nil`, NOT the default session factory. With a session the path answers through the selection tier, which cannot return a match today, so acceptance criterion 1 could never pass. See the comment "Deviation from the What section" for the measurement and the reasoning. The selection-prefix defect it names is card ^g69hyyc.

## Acceptance Criteria

- [x] `swift run FullMonty --embedder` prints ranked results with a non-zero cosine value in `.signals`, and exits with code 0.
- [x] `swift run FullMonty --embedder` prints no `.embeddingUnavailable` diagnostic.
- [x] `DemoEmbedder` needs no GPU and no network.

## Tests

- [x] Add `Tests/FoundationModelsRankerTests/DemoEmbedderTests.swift`: `embed(_:)` returns one vector per input, each of length `dimension`, in input order.
- [x] Add a test that two calls of `embed(["same text"])` in the same process give the same vector, and that a second process gives the same vector too. Prove the second part by asserting on a checked-in expected vector prefix, not by starting a process.
- [x] Add a test that each returned vector has a length of about 1.0, within 1e-5.
- [x] Add a test to `Tests/FoundationModelsRankerTests/ExamplesSmokeTests.swift` that `runEmbedderDemo` returns one result per demo query and reports no `.embeddingUnavailable`.
- [x] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.