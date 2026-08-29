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
- actor: claude-code
  id: 01m170jrfw9nkgvyv4fyr0pz7m
  text: |-
    ### commit — changed
    - evidence: `36406cd` feat(examples): add a GPU-free demo embedder to the FullMonty example — 13 files changed, 473 insertions, 21 deletions (local commit only, not pushed)
    - next: review
  timestamp: 2026-08-29T15:00:32.892626+00:00
- actor: claude-code
  id: 01m170v7km2tcn2mjs7kswray0
  text: |
    ### review — findings

    - scope: `review sha HEAD~1..HEAD` (commit `36406cd`). The engine read the changed lines only.
    - counts: 1 finding, 1 confirmed, 0 refuted, 7 validators attempted, 0 failed.
    - evidence: `Examples/FullMontyCore/Demo.swift:110` — `duplication/duplication`.

    Directed checks on `Examples/FullMontyCore/DemoEmbedder.swift`, both correct:

    1. The determinism statement is true. `fnv1aHash(ofText:)` is a written-out FNV-1a hash of the UTF-8 bytes of the text, with the standard offset basis `0xCBF29CE484222325` and the standard prime `0x100000001B3`. The words `String.hashValue` and `Hasher` are in the doc comments only, where they tell why the code does not use them. No code in the `Examples` directory calls either one.

    2. The expected vector in the test is a true independent check, not a record of the output of the code. An independent program that obeys the algorithm in the doc comment — lowercase the text, take each sliding 3-character window, add 1 at `FNV-1a(window) % dimension`, then make the length 1.0 — gives `[0.18257419, 0.0, 0.18257419, 0.18257419, 0.54772256, 0.54772256, 0.54772256, 0.0]` for `"commit changes"` at dimension 8. The checked-in values agree to the tolerance of the test (1e-6); the difference is only the precision of `Float` against `Double`.

    The agreed deviation is stated honestly. The doc comment of `runEmbedderDemo` gives `mode: .retrieval` and `session: nil`, and tells why: cosine is a signal of the retrieval tier, so the tier that shows it needs no selection session. The `What` section of this card records the deviation and points to card ^g69hyyc.

    - next: correct the finding, then run `/review` again.
  timestamp: 2026-08-29T15:05:10.516647+00:00
- actor: claude-code
  id: 01m170w20w12hs32dsyjg0833v
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 5 files; DemoEmbedder.swift added (FNV-1a over UTF-8, unit-normalized), runEmbedderDemo added, --embedder path added, 9 tests added
    - test: green — swift test, 252 passed, 0 failed, 1 documented gated skip; both FullMonty paths exit 0; two runs byte-identical
    - commit: 36406cd — 13 files changed, 473 insertions, 21 deletions
    - review: findings — Examples/FullMontyCore/Demo.swift:110, duplication between runEmbedderDemo and runNoModelDemo
    - next: implement iteration 2 works the duplication finding

    Both directed checks passed: the hash is a real FNV-1a with no `String.hashValue` or `Hasher` in code, and the reviewer reproduced the checked-in expected vector from an independent implementation.
  timestamp: 2026-08-29T15:05:37.564250+00:00
- actor: claude-code
  id: 01m171dzdg70w84pmxk1w65emr
  text: |
    ### implement iteration 2 — the duplication finding

    Finding: `Examples/FullMontyCore/Demo.swift:110` `duplication/duplication` — `runEmbedderDemo` and `runNoModelDemo` are nearly identical; they differ only in the embedder parameter (`nil` versus `DemoEmbedder()`).

    Correction: added the file-private helper `runRetrievalDemo(embedder:onDiagnostic:)` to `Examples/FullMontyCore/Demo.swift`. The helper holds the one shape both GPU-free retrieval paths use — `session: nil` and `mode: .retrieval` — and takes the embedder as a parameter. `runNoModelDemo` now calls it with `nil`; `runEmbedderDemo` calls it with `DemoEmbedder()`. Each public function keeps its name, its signature, and its doc comment.

    The whole file was examined for the same cause, not only the line in the finding:

    - `runDefaultDemo` does NOT route through the helper, and must not. It gives `session: Searcher.defaultSessionFactory` and `mode: .auto`, so two arguments are different, not one. A helper with a parameter for the session and a parameter for the mode would only be a second name for `runFullMontyDemo`. The doc comment of the helper records this reason, so a later reader does not repeat the question.
    - No third copy of the retrieval call shape is in the file.

    The two public functions are now one forwarding line each. The `duplication` validator gives a carve-out for this shape: "If the shared logic is already extracted and only the forwarding line repeats, the duplication is resolved — do not flag the shim." The `reuse` validator adds: "When the shared helper stands, the parameterization is done and the finding is answered."

    Rules read before the edit: `dump validators` on `Demo.swift` gave 7 validators and 55 rules (`code-hygiene`, `code-security`, `completeness`, `duplication`, `reuse`, `swift`, `test-integrity`). The rules that bear on this edit and how each is met:

    - `duplication/duplication` — the finding itself; the shared function is extracted and the difference is a parameter.
    - `swift/access-control` — the helper is `private` at file scope, which reaches both callers because they are in the same file. It exposes no lower-access type: its parameter and return types are the public `TextEmbedding`, `RankDiagnostic`, and `FullMontyResult`. No caller is `@inlinable`, so no `@usableFromInline` is needed.
    - `code-hygiene/missing-docs-swift` — reads `open` and `public` only, so the private helper needs no doc comment. One was written anyway, because it records why `runDefaultDemo` stays outside.
    - `code-hygiene/no-commented-code` and `dead-code` — no old body was left as a comment, and no path lost its caller.
    - `completeness/public-output-contract` — the public surface is unchanged. No name, signature, or doc comment moved, so `Examples/FullMonty/main.swift` and `Tests/FoundationModelsRankerTests/ExamplesSmokeTests.swift` needed no edit and got none.
    - `code-hygiene/magic-numbers-swift` — no literal moved to a call argument.

    No test was added: this is a behavior-preserving extraction, which is the REFACTOR step of the `/tdd` cycle. The 9 tests written in iteration 1 already drive both public paths, and they stayed green through the change.

    Measured after the change:

    - `swift build` — exit 0. The only warning is the pre-existing `mlx-swift_Cmlx.bundle` line, which card ^2q0p8gr removes with the MLX dependency.
    - `swift test` — 252 tests in 21 suites passed, 0 failures, 0 warnings, 0 errors.
    - `swift run FullMonty --embedder` — exit 0, 0 `embeddingUnavailable` lines. The top match and cosine for each query are the same numbers iteration 1 measured before the refactor: `grep` 0.722, `commit` 0.638, `branch` 0.439, `stash` 0.849. The extraction changed no output.
    - `swift run FullMonty --no-model` — exit 0, unchanged.
  timestamp: 2026-08-29T15:15:24.720950+00:00
- actor: claude-code
  id: 01m171e3s679ky67h3az1n56sf
  text: |-
    ### implement — changed
    - evidence: 1 file — `Examples/FullMontyCore/Demo.swift`. Added the file-private helper `runRetrievalDemo(embedder:onDiagnostic:)`; `runNoModelDemo` and `runEmbedderDemo` now forward to it. `swift build` exit 0; `swift test` 252 tests in 21 suites passed, 0 failures; both `FullMonty` GPU-free paths exit 0 with the same output as before.
    - next: `/review`
  timestamp: 2026-08-29T15:15:29.190772+00:00
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

## Review Findings (2026-08-29 10:01)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 5 file(s) reviewed, 8 not reviewed.

> 8 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 8 file(s)

- [x] `Examples/FullMontyCore/Demo.swift:110` `duplication/duplication` — runEmbedderDemo and runNoModelDemo are nearly identical — they differ only in the embedder parameter (nil versus DemoEmbedder()). Extract one shared function with an embedder argument, to avoid keeping two implementations in sync. Extract a private helper function (for example, runRetrieval(embedder:onDiagnostic:)) that takes the embedder as a parameter and calls runFullMontyDemo. Call this helper from both runNoModelDemo (passing nil) and runEmbedderDemo (passing DemoEmbedder()).
