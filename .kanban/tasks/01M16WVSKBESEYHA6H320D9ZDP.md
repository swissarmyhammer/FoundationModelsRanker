---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m16yp7a3xkr6q0skqfhjgfsn
  text: |-
    Picked up. Research notes before the edits.

    **Line numbers on the card are stale.** The files moved after the card was written (task `^y2znsqb`, commit `4b5c8bb`). Current positions:
    - `Examples/FullMonty/main.swift` — the gated branch is lines 23-26, not 39-42. The mention in the `else` message is lines 35-36. The header comment is lines 3-21.
    - `Examples/FullMontyCore/LiveRouter.swift` — the two symbols to keep are still at lines 36 and 39-41.
    - `Tests/.../ExamplesSmokeTests.swift` — the doc comment to correct is lines 15-18.

    **No test calls `runLiveFullMontyDemo`.** `grep` over the whole repository finds the symbol in `LiveRouter.swift` alone. So the card's "Delete any test that calls `runLiveFullMontyDemo`" has nothing to delete.

    **`LiveRouter.swift` also holds two `private` adapters** — `RoutedSessionAgentSession` and `RoutedEmbedderTextEmbedding` — that task `^y2znsqb` added to keep the target compiling after it deleted `RoutedAgentSession` and `RoutedEmbedderAdapter` from the library. Deleting the file removes them too. That is correct: nothing else uses them.

    **`Package.swift` stays as it is.** It still declares `liveRouterProductDependencies` on `FullMontyCore`. Task `^2q0p8gr` ("Delete every external package dependency from Package.swift") owns that removal, and this card does not list `Package.swift`. An unused target dependency makes no build warning, so the tree stays clean.

    **The gate the tests read.** `Tests/.../AgentSessionDispatchTests.swift` uses `isFoundationModelsRankerIntegrationEnabled` in an `@Test(.enabled(if:))` trait. It imports `FullMontyCore`, so the symbol keeps working after the move to `Demo.swift`.
  timestamp: 2026-08-29T14:27:29.219061+00:00
- actor: claude-code
  id: 01m16ywjm79k9754ez28g79vhg
  text: |-
    Implementation landed. The TDD cycle, and one deviation the reviewer must judge.

    **The TDD cycle, with the red state recorded.**
    1. Added the two new tests to `ExamplesSmokeTests.swift` and ran `swift test --filter ExamplesSmokeTests`: 10 tests passed. This proved the tests read the correct symbol while it was still in `LiveRouter.swift`.
    2. `git rm Examples/FullMontyCore/LiveRouter.swift`, then `swift build`. RED, for the correct reason — three errors, all in `Examples/FullMonty/main.swift`: `cannot find 'foundationModelsRankerIntegrationEnvVar' in scope` (twice, at the `if` and in the `else` message) and `cannot find 'runLiveFullMontyDemo' in scope`.
    3. Moved the two symbols to `Demo.swift`, rewrote `main.swift`, corrected the two doc comments. GREEN — `swift test`: 243 tests in 20 suites passed, 0 failures.

    **One deviation from the card, declared.** The card says to copy the two symbols "without a change". I copied each DECLARATION without a change — the same name, the same type, the same value, the same body, the same `public`. I did NOT copy the doc PROSE without a change, and the reason is that the prose describes the path this same card deletes:

    - `foundationModelsRankerIntegrationEnvVar` said "The opt-in environment variable gating `FullMonty`'s real-model path (plan.md §3a) ... `FullMonty` never touches the network or GPU."
    - `isFoundationModelsRankerIntegrationEnabled` said "Whether `FullMonty`'s gated real-model path is enabled for this run."

    After this card there is no gated real-model path. Copying that prose would ship documentation that names a path no reader can find. The new prose states what the variable now does: it enables the tests that need a live Apple Intelligence model. The card gives the same instruction for the surrounding headers ("Update the header comment ... to describe two paths, not three"), so this is the same correction applied to the same stale claim.

    **One edit the card does not list, for the same reason.** `runDefaultDemo`'s doc comment in `Demo.swift` said "a live embedder needs the gated Router path". That sentence became false when the file went. It now reads "no embedder, so retrieval stays keyword-only".

    **What the card asked for and did not exist.** "Delete any test that calls `runLiveFullMontyDemo`" — no test called it, so nothing was deleted.

    **The two new tests.**
    - `theOptInEnvironmentVariableKeepsItsName` pins `foundationModelsRankerIntegrationEnvVar` to `FOUNDATIONMODELSRANKER_INTEGRATION_TESTS`. The card's fourth acceptance criterion is that the gate "still reads the same environment variable", and this test is what holds that.
    - `theGateIsOffWhenTheOptInEnvironmentVariableIsAbsent` opens with a `#require` that the variable is absent, then expects the gate to read `false`. The `#require` carries a message, so a developer who runs the suite with the variable set reads why the test failed. The test always runs — it selects nothing, so it does not conflict with the `test-partitioning` rule against environment-variable test switching.

    **`Package.swift` is untouched, deliberately.** It still names `liveRouterProductDependencies` on `FullMontyCore` though no file imports them. Task `^2q0p8gr` owns that removal and this card does not list the file. An unused TARGET dependency raises no warning, so the tree stays clean.

    **One pre-existing build warning stands.** `swift build` prints `warning: missing creator for mutated node: (.../mlx-swift_Cmlx.bundle/Contents/MacOS)`. It comes from building the MLX dependency, which this change does not touch, and task `^2q0p8gr` names its removal as one of its own acceptance criteria.
  timestamp: 2026-08-29T14:30:57.415310+00:00
- actor: claude-code
  id: 01m16ywrhx0ggnvktqzvt3n7yq
  text: |-
    ### implement — changed
    - evidence: 4 files — Examples/FullMontyCore/LiveRouter.swift (deleted, 173 lines), Examples/FullMontyCore/Demo.swift (the two gate symbols added, two stale doc comments corrected), Examples/FullMonty/main.swift (the gated branch and its message deleted, header now names two paths), Tests/FoundationModelsRankerTests/ExamplesSmokeTests.swift (suite doc corrected, two tests added for the moved gate). `swift build`: complete. `swift test`: 243 tests in 20 suites passed, 0 failures. `swift run FullMonty --no-model`: ranked results, exit 0. `grep -rn "FoundationModelsRouter\|MLX\|HuggingFace\|Tokenizers" Examples/`: no match.
    - next: `/review`. Read the deviation declared in the comment above — the doc PROSE of the two moved symbols was rewritten, not copied word for word.
  timestamp: 2026-08-29T14:31:03.485537+00:00
- actor: claude-code
  id: 01m16zaxpa8hztfwm2t8m1fvvs
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (commit `9cb5dbf`) — 0 findings, 0 confirmed, 0 refuted, 7 checks made, 0 failed. The engine read 4 files. It did not read the 4 `.kanban/` files, because an ignore rule holds them out.
    - declined checks: 3 tool rules (`function-length-swift`, `magic-numbers-swift`, `missing-docs-swift`) declined one item each. All 3 name `Examples/FullMontyCore/LiveRouter.swift`, which this change deletes. A deleted file has no code to read, thus these are not findings.
    - deviation judged — the new doc text is correct. The card told the implementer to move `foundationModelsRankerIntegrationEnvVar` and `isFoundationModelsRankerIntegrationEnabled` "without a change". The implementer copied the two declarations word for word, but wrote new doc prose. The new prose is true:
      - Only one caller reads the gate now: `Tests/FoundationModelsRankerTests/AgentSessionDispatchTests.swift:92`, in an `@Test(.enabled(if:))` trait. That test needs a live Apple Intelligence model. Thus "the environment variable that enables the gated tests" is correct and complete.
      - `Examples/FullMonty/main.swift` no longer reads either symbol. Thus the old prose, which named a "gated real-model path", would be false after this change.
      - `runDefaultDemo`'s new doc says "Run with no flags". This agrees with `main.swift`, which now has one `--no-model` branch and one `else` branch.
      - The card also told the implementer to correct the file header. `Demo.swift` no longer says that `FullMonty` has three paths. It says two.
    - out of scope, as the card states: `Package.swift` still names the Router packages (card `^2q0p8gr` owns the manifest), and `README.md` still names the deleted path (card `^jdw7sf0` owns the README).
    - next: commit.
  timestamp: 2026-08-29T14:38:47.498829+00:00
- actor: claude-code
  id: 01m16zbm0ee8xa8852ffqttb3m
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 4 files; LiveRouter.swift deleted (173 lines), the two gate symbols moved to Demo.swift, main.swift down to two paths, two gate tests added
    - test: green — swift test, 243 passed, 0 failed, 1 documented gated skip; swift run FullMonty --no-model exits 0
    - commit: 9cb5dbf — 8 files changed, 156 insertions, 210 deletions
    - review: clean — zero findings; the declared doc-comment deviation was judged accurate
    - next: none — task is in done
  timestamp: 2026-08-29T14:39:10.350678+00:00
depends_on:
- 01M16WV88B4043AXS1XY2ZNSQB
position_column: done
position_ordinal: '9580'
title: Delete the live-Router path from the FullMonty example
---
## What

`Examples/FullMontyCore/LiveRouter.swift` is the only example code that uses `FoundationModelsRouter`, MLX, and Hugging Face. Delete it. Keep the two paths that do not need Router: the default on-device system model path, and the `--no-model` keyword-only path.

`LiveRouter.swift` also holds two symbols that other code uses. Move them first:

- `foundationModelsRankerIntegrationEnvVar` (line 36)
- `isFoundationModelsRankerIntegrationEnabled` (lines 39-41)

`Tests/FoundationModelsRankerTests/AgentSessionDispatchTests.swift:71` uses the second symbol to gate a test that needs Apple Intelligence. That gate has nothing to do with Router, so it must keep working.

Files to change:

- `Examples/FullMontyCore/LiveRouter.swift` — delete the file.
- `Examples/FullMontyCore/Demo.swift` — add `foundationModelsRankerIntegrationEnvVar` and `isFoundationModelsRankerIntegrationEnabled`, both `public`, copied without a change. Update the file header at line 22 to drop the live-Router path.
- `Examples/FullMonty/main.swift` — delete the `if isFoundationModelsRankerIntegrationEnabled` branch (lines 39-42) and the mention of the branch in the `else` message (lines 51-52). Update the header comment at lines 19-37 to describe two paths, not three.
- `Tests/FoundationModelsRankerTests/ExamplesSmokeTests.swift` — update the doc comment at line 16. Delete any test that calls `runLiveFullMontyDemo`.

## Acceptance Criteria

- [x] `Examples/FullMontyCore/LiveRouter.swift` does not exist.
- [x] `grep -rn "FoundationModelsRouter\|MLX\|HuggingFace\|Tokenizers" Examples/` finds nothing.
- [x] `swift run FullMonty --no-model` prints ranked results and exits with code 0.
- [x] `AgentSessionDispatchTests.swift` still compiles and its gate still reads the same environment variable.

## Tests

- [x] `Tests/FoundationModelsRankerTests/ExamplesSmokeTests.swift` keeps its test of `runNoModelDemo`. The test must pass on a machine with no GPU.
- [x] Add a test that `isFoundationModelsRankerIntegrationEnabled` is `false` when the environment variable is absent, so the moved gate is covered.
- [x] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.