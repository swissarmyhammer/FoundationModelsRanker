---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m16xdr20crw5q3ahy32sx6sq
  text: |-
    Research done. What the code shows:

    - `Sources/FoundationModelsRanker/Selection/AgentSession.swift` holds `import FoundationModelsRouter` (line 11), the protocol doc comment (lines 13-32) and `struct RoutedAgentSession` (lines 118-167). The `AgentSession` extension doc comments also name `RoutedAgentSession`, `RoutedSession` and `RoutedLLM` (lines 45, 80-81, 89-99), so the whole file needs the Router names removed, not only the two blocks the card lists.
    - Two more files in `Sources/` name `RoutedAgentSession` in doc comments, and the acceptance grep covers them:
      - `Sources/FoundationModelsRanker/Searcher.swift` lines 41 and 118.
      - `Sources/FoundationModelsRanker/Selection/LanguageModelSessionSupport.swift` lines 96 and 103 (plus `RoutedSession` at lines 80 and 102, and the header at lines 4-5 and 7 the card names).
      These are doc references to the type this card deletes, so they go with it.
    - `Tests/FoundationModelsRankerTests/ReadmeExampleTests.swift` line 82 also names `RoutedEmbedderAdapter` in a doc comment. Same reason.

    Dependency-order finding: the acceptance criterion `grep -rn "FoundationModelsRouter\|RoutedAgentSession\|RoutedEmbedder" Sources/` also covers two `import FoundationModelsRouter` lines this card does NOT own:
    - `Sources/FoundationModelsRanker/Selection/SelectionConfig.swift:23` — owned by ^4kx83sx ("Delete `import FoundationModelsRouter` (line 23)").
    - `Sources/FoundationModelsRanker/Selection/SelectionTier.swift:10` — owned by ^cd4geys ("Delete `import FoundationModelsRouter` (line 10)").
    Both imports are load-bearing today: `SelectionConfig` and `SelectionTier` still use the Router `Grammar` type, so deleting either import stops the build. ^cd4geys states the expected order itself: its own criterion reads "`grep -rn "FoundationModelsRouter" Sources/` finds only `AgentSession.swift` and `RoutedEmbedderAdapter.swift`. Other tasks delete those." So this card was planned to run AFTER ^4kx83sx and ^cd4geys, and the board ordinals agree (80, 8180, then 8280). Neither of those cards is done yet.

    Test support already present: `Tests/.../Support/FakeEmbedder.swift` and `DiagnosticRecorder` (in `Support/ScriptedAgentSession.swift`). `Tests/.../PackageTests.swift` imports `FoundationModelsRanker` WITHOUT `@testable`, so a conformer written there reaches the public surface only — exactly the proof this card asks for.
  timestamp: 2026-08-29T14:05:22.880604+00:00
- actor: claude-code
  id: 01m16xxm1vv9cbxtje8radd9mn
  text: |-
    Implementation landed. What changed, and two things a reviewer must know.

    Done, per the card:
    - Deleted `Sources/FoundationModelsRanker/RoutedEmbedderAdapter.swift`.
    - `Sources/FoundationModelsRanker/Selection/AgentSession.swift`: deleted `struct RoutedAgentSession` and `import FoundationModelsRouter`; rewrote the `AgentSession` doc comment on its own terms (send a prompt, get text, `fork()`), and kept the description of what `fork()` must do. Also removed the `RoutedSession`/`RoutedLLM`/`RoutedAgentSession` names from the two extension doc comments, which the card's file list did not name but which the same deletion makes stale.
    - `Sources/FoundationModelsRanker/TextEmbedding.swift`: the sentence now says the caller supplies the conformer, and that `dimension` and `embed(_:)` are the whole contract.
    - `Sources/FoundationModelsRanker/Selection/LanguageModelSessionSupport.swift`: header text updated, plus the three `RoutedSession`/`RoutedAgentSession` doc mentions in `fork()`.
    - `Sources/FoundationModelsRanker/Searcher.swift` lines 41 and 118: both named `RoutedAgentSession`, a type this card deletes.
    - `Tests/FoundationModelsRankerTests/ReadmeExampleTests.swift` line 82: same reason.
    - Tests added: `PackageTests.swift` gets `aCallerSuppliedTextEmbeddingConformerDrivesTheCosineSignal` with a local `VowelCountEmbedder` (that file imports the module WITHOUT `@testable`, so the conformer reaches the public surface only). `AgentSessionDispatchTests.swift` gets `aConformerWithOnlyRespondToInheritsTheDefaultFork` and `aConformerWithOnlyRespondToInheritsTheDefaultTypedRespond`, driven by a new `PlainTextOnlyAgentSession` that implements `respond(to:)` and nothing else. Every other double in the target overrides `fork()`, so none of them could answer that question.

    TDD note: the three new tests pass before the deletion as well, because the seams already existed. Their value is as regression guards. To prove the embedder test can fail, I temporarily set `embedder: nil` and re-ran it: it failed with `signals.cosine → 0.0`. Then I restored the embedder. The two `AgentSession` tests fail by compilation if either default goes away.

    DEVIATION, and why it was forced. `Examples/FullMontyCore/LiveRouter.swift` used both deleted types (lines 105 and 108), so `swift build` failed after the deletion with "cannot find 'RoutedEmbedderAdapter' in scope" and "cannot find 'RoutedAgentSession' in scope". The card that deletes `LiveRouter.swift` is ^20d9zdp, which is blocked BY this card, so it cannot run first. The card's own What section names the answer: "A Router user writes the same 15 lines in their own package against the `AgentSession` and `TextEmbedding` protocols, which stay public." `FullMontyCore` is that Router user, so the two adapters now live in `LiveRouter.swift` as `private struct RoutedSessionAgentSession` and `private struct RoutedEmbedderTextEmbedding`. Each member is a pure forward, as before. ^20d9zdp deletes that whole file, so this code is short-lived on purpose.

    BLOCKER — one acceptance criterion is NOT met. `grep -rn "FoundationModelsRouter\|RoutedAgentSession\|RoutedEmbedder" Sources/` still finds two lines:
    - `Sources/FoundationModelsRanker/Selection/SelectionConfig.swift:23: import FoundationModelsRouter`
    - `Sources/FoundationModelsRanker/Selection/SelectionTier.swift:10: import FoundationModelsRouter`
    Both are load-bearing today: each file uses the Router `Grammar` type, so deleting either import stops the build. Both lines are assigned to other cards, word for word: ^4kx83sx says "Delete `import FoundationModelsRouter` (line 23)" for `SelectionConfig.swift`, and ^cd4geys says "Delete `import FoundationModelsRouter` (line 10)" for `SelectionTier.swift`. ^cd4geys also states the intended order in its own criterion: "grep -rn \"FoundationModelsRouter\" Sources/ finds only `AgentSession.swift` and `RoutedEmbedderAdapter.swift`. Other tasks delete those." The board ordinals agree: ^4kx83sx (80), ^cd4geys (8180), then this card (8280). Run ^4kx83sx and ^cd4geys first, then this criterion passes with no further edit to this card's files.

    Environment note for the next agent: `swift build` failed on a clean tree BEFORE any of my edits, with "mlx-swift-lm is required using two different revision-based requirements (stable and foundationmodels-fixes), which is not supported". The cause was a stale `Package.resolved` (now gitignored) that pinned an old `FoundationModelsRouter` revision which wanted the `foundationmodels-fixes` branch; Router `main` now names `stable`, matching this package. `swift package update` fixed it. Do not change the `mlx-swift-lm` branch pin in `Package.swift`.

    One `Router` mention stays in `LanguageModelSessionSupport.swift:63` ("Router-guided sessions get the external id-enum grammar"). It is about grammar handling, it is outside the lines this card names, and the acceptance grep does not cover it. The grammar cards own that sentence.
  timestamp: 2026-08-29T14:14:03.067303+00:00
- actor: claude-code
  id: 01m16xxwhr1rgtz4jh2h8cf4nr
  text: |-
    ### implement — stuck
    - evidence: 9 files — Sources/FoundationModelsRanker/RoutedEmbedderAdapter.swift (deleted), Sources/FoundationModelsRanker/Selection/AgentSession.swift, Sources/FoundationModelsRanker/TextEmbedding.swift, Sources/FoundationModelsRanker/Selection/LanguageModelSessionSupport.swift, Sources/FoundationModelsRanker/Searcher.swift, Examples/FullMontyCore/LiveRouter.swift, Tests/FoundationModelsRankerTests/PackageTests.swift, Tests/FoundationModelsRankerTests/AgentSessionDispatchTests.swift, Tests/FoundationModelsRankerTests/ReadmeExampleTests.swift. `swift build` — Build complete, no error. `swift test` — 241 tests in 20 suites passed, 0 failures. The one build warning ("missing creator for mutated node: ... mlx-swift_Cmlx.bundle") is pre-existing and comes from SwiftPM, not from this code; ^2q0p8gr owns it.
    - gap: acceptance criterion `grep -rn "FoundationModelsRouter\|RoutedAgentSession\|RoutedEmbedder" Sources/` still finds `Selection/SelectionConfig.swift:23` and `Selection/SelectionTier.swift:10`. Both are `import FoundationModelsRouter`, both are load-bearing (the Router `Grammar` type), and both belong to ^4kx83sx and ^cd4geys word for word.
    - next: run ^4kx83sx, then ^cd4geys, then re-check this criterion. It then passes with no further edit to this card's files.
  timestamp: 2026-08-29T14:14:11.768889+00:00
- actor: claude-code
  id: 01m16y06zde1f2tfm74pjr16tq
  text: |-
    ### orchestrator — card correction

    The `implement` step reported `stuck` against this criterion:

    `grep -rn "FoundationModelsRouter\|RoutedAgentSession\|RoutedEmbedder" Sources/` finds nothing.

    That criterion was a planning defect, not a code defect. Two other files import Router for the `Grammar` type, and cards `^4kx83sx` and `^cd4geys` own them word for word. This card can never satisfy a repo-wide grep on its own.

    Action: the criterion is now scoped to `RoutedAgentSession` and `RoutedEmbedderAdapter`, plus a per-file check on `Selection/AgentSession.swift`. The card is not stuck. The loop continues to test.

    Also recorded: the `implement` step added two `private` adapter structs to `Examples/FullMontyCore/LiveRouter.swift` to keep the example target compiling. Card `^20d9zdp` deletes that whole file. The structs must stay `private` until then.
  timestamp: 2026-08-29T14:15:27.981287+00:00
- actor: claude-code
  id: 01m16y5f9npa1de3s81scbnww3
  text: |-
    ### commit — changed
    - evidence: 4b5c8bb — 27 files changed, 701 insertions(+), 176 deletions(-)
    - next: push is a separate step, not done here.
  timestamp: 2026-08-29T14:18:20.341528+00:00
- actor: claude-code
  id: 01m16ye7kjnk93nd2natxqez0e
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (commit 4b5c8bb). 9 files reviewed. counts: findings 1, confirmed 1, refuted 0, attempted 7, failed 0. Zero findings in the scope of this card.
    - dropped finding: `Examples/FullMontyCore/LiveRouter.swift:162` `code-hygiene/dead-code-swift` — "var.instance `dimension` is unused." The written scope note on this card, and the orchestrator comment of 2026-08-29, put the two `private` adapter structs in `LiveRouter.swift` out of the review scope. Line 162 is `var dimension: Int { routedEmbedder.dimension }` in `private struct RoutedEmbedderTextEmbedding`. It is a necessary member of the `TextEmbedding` protocol. Card `^20d9zdp` deletes the full file. A written rule releases this finding, thus it is not recorded as work.
    - also noted: three tool rules could not read `Sources/FoundationModelsRanker/RoutedEmbedderAdapter.swift`, because this commit deletes that file. This is the correct result.
    - next: no work is open from the review. The card moves to done.
  timestamp: 2026-08-29T14:23:07.378055+00:00
- actor: claude-code
  id: 01m16yf0p7e7y6cydqwg2cawmt
  text: |-
    ### finish iteration 1 — clean
    - implement: stuck → resolved by orchestrator card correction (the repo-wide grep criterion was a planning defect; it is now scoped to what this card owns)
    - test: green — swift test, 241 passed, 0 failed, 1 documented gated skip
    - commit: 4b5c8bb — 27 files changed, 701 insertions, 176 deletions
    - review: clean — zero findings in scope; the one dead-code hit was on the temporary private struct that card ^20d9zdp deletes
    - next: none — task is in done
  timestamp: 2026-08-29T14:23:33.063294+00:00
position_column: done
position_ordinal: '9480'
title: Delete RoutedAgentSession and RoutedEmbedderAdapter
---
## What

Two adapters in the library target exist only for `FoundationModelsRouter`. Each one is a thin pass-through. Delete both. A Router user writes the same 15 lines in their own package against the `AgentSession` and `TextEmbedding` protocols, which stay public.

Files to change:

- `Sources/FoundationModelsRanker/Selection/AgentSession.swift` — delete `struct RoutedAgentSession` (lines 118-167) and `import FoundationModelsRouter` (line 11). Rewrite the `AgentSession` protocol doc comment (lines 13-32). The new text must describe the seam on its own terms: send a prompt, get text, and `fork()`. It must not name `RoutedSession` or `RoutedLLM`. Keep the description of what `fork()` must do, because a conformer must still honor it.
- `Sources/FoundationModelsRanker/RoutedEmbedderAdapter.swift` — delete the file.
- `Sources/FoundationModelsRanker/TextEmbedding.swift` — lines 12-13 name `RoutedEmbedderAdapter`. Replace that sentence. The new sentence must say that the caller supplies a conformer.
- `Sources/FoundationModelsRanker/Selection/LanguageModelSessionSupport.swift` — the file header names Router in lines 4-5 and line 7. Update the text.

## Scope note (correction, 2026-08-29)

The first version of this card told you to grep all of `Sources/` for `FoundationModelsRouter`. That criterion was wrong. Two other files import Router for the `Grammar` type: `Selection/SelectionConfig.swift` and `Selection/SelectionTier.swift`. Card `^4kx83sx` and card `^cd4geys` own those two imports. This card does not. The criterion below is now scoped to what this card owns.

`Examples/FullMontyCore/LiveRouter.swift` uses both deleted types, so this card must keep the example target compiling. Write the two adapter shapes as `private` structs in that file. Card `^20d9zdp` deletes the whole file later, so this code is temporary and must stay `private`.

## Acceptance Criteria

- [ ] `Sources/FoundationModelsRanker/RoutedEmbedderAdapter.swift` does not exist.
- [ ] `grep -rn "RoutedAgentSession\|RoutedEmbedderAdapter" Sources/` finds nothing.
- [ ] `grep -n "FoundationModelsRouter" Sources/FoundationModelsRanker/Selection/AgentSession.swift` finds nothing.
- [ ] `AgentSession` and `TextEmbedding` keep their public members without a change, so an outside adapter still compiles against them.
- [ ] `swift build` gives no error.

## Tests

- [ ] Add a test to `Tests/FoundationModelsRankerTests/PackageTests.swift`: a local `struct` that conforms to `TextEmbedding` with `dimension` and `embed(_:)` works as a `Searcher` embedder. This proves the seam is complete without the deleted adapter.
- [ ] Add a test to `Tests/FoundationModelsRankerTests/AgentSessionDispatchTests.swift`: a local type that conforms to `AgentSession` with only `respond(to:)` gets the default `fork()` and the default `respond(to:generating:)`.
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.