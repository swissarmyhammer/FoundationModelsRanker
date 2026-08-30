---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m19h6j3bbvwf9yqq6xmtthsb
  text: |-
    Discoveries while implementing, for whoever picks this up next.

    **1. The nested package could not reach `runDefaultDemo` at all.** `FullMontyCore` was a target with no product, and a target in one package reaches another package's code only through a product. The root manifest now declares a `FullMontyCore` library product, and `IntegrationTests/Package.swift` depends on it. No library target depends on that product, so the example stays a demo. `TestPartitioningTests` still passes: it counts `.testTarget(` in the root manifest, and that count is still one.

    **2. The on-device model does not answer every demo query on a cold session.** The first draft of the zero-config test asked "record my staged changes as a new commit" -- the query the card's own text points at as unambiguous. It failed three runs out of three, with an empty match list and NO `.unknownSelectedId`, which means the model answered `{"ids":[]}`. The same query answers `commit` inside `runDefaultDemo`.

    The difference is session history. The under-budget selection path caches one root session and reuses it for every query, so `FullMonty`'s second query is asked of a session that has already answered the first. A test that asks one question gets a session that has answered nothing. Probing all four demo queries one at a time, each on its own new `Searcher`:

    ```
    PROBE search file contents for a pattern using a regular expression -> ["grep"]
    PROBE record my staged changes as a new commit                      -> []
    PROBE how do I list or delete a branch                              -> ["branch"]
    PROBE temporarily set aside my uncommitted changes to switch tasks  -> ["stash"]
    ```

    The test now asks the `grep` query, which the model answers cold, and the reason is written in the fixture's doc comment. Do not move it back to the commit query.

    This is worth a card of its own: one query in four returns nothing from a cold session on the package's own front door. It is not a defect this card can correct, and no assertion here is loose enough to hide it -- the test asserts a match came back.

    **3. `Demo.swift:125` is not what the card says it is.** Full measurement and the two corrections a person can choose between are in the description's **Blocker** section. Short version: the line is the closure body of the default argument, not the default-argument generator, so a bare call does not reach it; the `--embedder` path reports no diagnostic by design, so the body cannot run. Two root tests already make the bare call the card asks for, so no third copy was added.
  timestamp: 2026-08-30T14:29:27.787268+00:00
- actor: claude-code
  id: 01m19h7kc0da6tcjapxqee6a8x
  text: |-
    ### implement — stuck

    - evidence: 5 files. New: `IntegrationTests/Tests/FoundationModelsRankerIntegrationTests/ZeroConfigSearcherRealModelTests.swift`, `IntegrationTests/Tests/FoundationModelsRankerIntegrationTests/FullMontyDefaultDemoRealModelTests.swift`. Changed: `Tests/FoundationModelsRankerTests/ExamplesSmokeTests.swift`, `Package.swift`, `IntegrationTests/Package.swift`.
    - suites: root `swift test` 279 tests in 22 suites pass (was 278). `swift test --package-path IntegrationTests` 4 tests in 4 suites pass (was 2), green on 5 runs in a row. `swift build` reports no warning.
    - coverage, by parsing `DA:` from lcov written to /tmp, never into the repository:
      - `Sources/FoundationModelsRanker/Searcher.swift` 101-103 (`defaultSessionFactory`): 0,0,0 -> 2,2,2 in the integration run. File 122/125 -> 125/125 across the two runs.
      - `Examples/FullMontyCore/Demo.swift` 151-154 (`runDefaultDemo`): 0,0,0,0 -> 4,1,1,1 in the integration run.
      - `Examples/FullMontyCore/Demo.swift` 208-210 (`printDiagnostic`): 0,0,0 -> 3,3,3 in the root run. Root file 51/59 -> 54/59.
      - `Examples/FullMontyCore/Demo.swift` union of both runs: 51/59 -> 58/59.
      - `Examples/FullMontyCore/Demo.swift` 125 (the card's `:140`): 0 -> 0. This is the gap.
    - gap: the card asks for `Demo.swift:140` covered by the root run AND for no production code change. Both cannot hold. `llvm-cov` maps that line to the closure BODY of the default argument, not to the default-argument generator, so a bare `runEmbedderDemo()` call does not reach it -- two root tests already make that call and the line still reads 0. The `--embedder` path reports no diagnostic by design, so the body cannot run. A person chooses: drop the line from the criterion, or allow a change to `Examples/FullMontyCore/Demo.swift`.
    - next: a person decides the gap above. Card left in `doing`. New card `^5pg59d2` records the separate finding that one demo query returns no match on a cold selection session.
  timestamp: 2026-08-30T14:30:01.856694+00:00
- actor: claude-code
  id: 01m19h94jcpfc9emm5rqj85e3s
  text: |-
    ### Orchestrator: card correction, and the `stuck` is cleared

    The implement step reported `stuck` on one acceptance item. That item was my error, not a blocked piece of work. Clearing it.

    **The item was factually wrong.** I asked for coverage of `Demo.swift:140` (now `:125`), describing it as "the default `onDiagnostic` argument of `runEmbedderDemo`, uncovered because every caller passes one". The implement step measured what that line actually is: `llvm-cov` maps it to `closure #1 in default argument 0 of runEmbedderDemo` — the closure BODY, not the site where the default is supplied. The counter increments when the body runs, which needs a diagnostic to fire.

    Two root tests already call `runEmbedderDemo()` bare and the line still reads `DA:125,0`, while `runNoModelDemo`'s identical default reads 20. The reason is design, not a gap: the `--embedder` path reports no diagnostic on purpose, `DemoEmbedder.embed` never throws, and `ExamplesSmokeTests.embedderDemoReportsNoEmbeddingUnavailableDiagnostic` asserts exactly that. So the body is unreachable through the public surface, and the only way to cover it is to change `Examples/FullMontyCore/Demo.swift` — which the card forbids, and which would mean changing product behavior to move a coverage number. That is the wrong trade.

    The implement step was right to stop rather than resolve the conflict itself, and right not to add a third bare call that would not have moved the line anyway.

    **That acceptance item is withdrawn as not applicable.** The remaining three pieces are done and measured. This is a correction of a criterion that misdescribed the code, not a criterion weakened to make a run pass.

    **One deviation to judge at review, not a defect on its face.** The nested package could not reach `runDefaultDemo`, because `FullMontyCore` was a target with no product. The root manifest now declares a `FullMontyCore` library product. That is a real change to the package's public surface — a consumer can now depend on the example target. The alternative was to drop the `runDefaultDemo` test. The reviewer should judge which is right.

    **A genuine product finding came out of this card**, recorded as `^5pg59d2`: on a COLD `Searcher`, the on-device model answered `{"ids":[]}` to "record my staged changes as a new commit" on three runs of three, with no `.unknownSelectedId` — the model returned an empty list, not a wrong id. The same query succeeds inside `runDefaultDemo`, where one session has already answered an earlier query. That is worth understanding on its own.
  timestamp: 2026-08-30T14:30:52.236803+00:00
- actor: claude-code
  id: 01m19hctzf5nx3vn5sn0qah4pt
  text: |-
    ### test — green
    - evidence: `swift build` clean, 0 warnings. `swift test` — 279 tests passed, 0 failed, 0 skipped. `swift build --package-path IntegrationTests --build-tests` clean, 0 warnings. `swift test --package-path IntegrationTests` run 5 times in a row — each run: 4 tests passed, 0 failed, 0 skipped (run 1: 4.692s, run 2: 3.773s, run 3: 3.744s, run 4: 3.911s, run 5: 3.707s). `swift run FullMonty --no-model` exit 0. `swift run FullMonty --embedder` exit 0. `Package.swift` has the `FullMontyCore` product. No library target has a dependency on `FullMontyCore`. `swift build --target FoundationModelsRanker` builds the library alone, exit 0.
    - next: none. All checks pass.
  timestamp: 2026-08-30T14:32:53.487328+00:00
- actor: claude-code
  id: 01m19hp1f0rk4f7zbmqce2477t
  text: |-
    ### review — clean

    - evidence: `review sha HEAD~1..HEAD` (commit `03319bf`), 7 validators, 0 findings, 0 confirmed, 0 refuted, 0 failed. 5 files reviewed. Build before the review: `rm -rf .build/out && swift build --build-tests` — complete, 0 warnings.
    - next: none. No new review findings. The card moves to `done`.

    #### The four judgment items

    **1. The new `FullMontyCore` library product. Recommendation: keep it.**

    The root manifest now shows two products. A user of the package can import `FullMontyCore`. This is a change to the public surface.

    Facts:

    - SwiftPM gives no product that is only for tests. A target in one package reads code in another package only through a product. There is no third way.
    - The symbols in `FullMontyCore` were already `public` before this change. A target is a module, so the root test target needed them public. The change adds reach, not new declarations.
    - The library target keeps `dependencies: []`. No library target depends on `FullMontyCore`. The test step measured this: `swift build --target FoundationModelsRanker` builds the library alone, exit 0.
    - The alternative is to remove the `runDefaultDemo` test. `runDefaultDemo` is the path with no flag. It is the path that uses the on-device model through `Searcher.defaultSessionFactory`. It is also the kind of path that commit `cbcee8c` broke without a signal. To remove the test keeps the surface at one product, but it keeps the front door of the demo untested.

    The trade is correct. The cost is bounded and the manifest comment records it. The value is a test of the path that most needs one.

    One recommendation, not a finding: the product now carries a promise of compatibility to a user who imports it. The manifest comment tells the reader that no library target depends on the example. It does not tell a user that the example has no compatibility promise. Add that sentence to the manifest comment or to the README.

    **2. The query in the zero-config test. The record is honest and the test proves its claim.**

    The doc comment of `query` in `ZeroConfigSearcherRealModelTests.swift` names the query that the card suggested, gives the measured behavior of that query, and gives the reason for the change: "record my staged changes as a new commit" gives the model no id on a cold session, and answers `commit` only after the same session answered an earlier query. The comment does not hide the change. Comment 1 on this card holds the full measurement, three runs of three. Card `^5pg59d2` records the behavior as work of its own.

    The test still proves the claim. It asserts that the match list is not empty, that each match id is in the catalog, and it records an `Issue` if the run reports `.unknownSelectedId`. The claim is unchanged: the default path gives a real match with no `.unknownSelectedId`. Only the stimulus changed. The diagnostic handler runs on the task of the test, because no code in `Sources/` sends a diagnostic from a detached task, so the guard can fail the test.

    **3. `Searcher.defaultSessionFactory` coverage. Confirmed.**

    `ZeroConfigSearcherRealModelTests` calls `Searcher(toolCatalog, onDiagnostic: ...)`. The call gives two arguments, and neither is `session:`. Only the initializer with `session: ... = Searcher.defaultSessionFactory` can accept that call. The other public initializer needs a `session: any AgentSession` argument, so it cannot match. `FullMontyDefaultDemoRealModelTests` calls `runDefaultDemo()`, which uses the same default. The coverage moved because the default factory ran.

    **4. The root library target. Confirmed.**

    `Package.swift` keeps `.target(name: packageName, dependencies: [], path: "Sources/\(packageName)")`. The library target has no dependency on `FullMontyCore`. The dependency goes one way only: the `FullMontyCore` target depends on the library target.

    #### Out of scope

    `Demo.swift:125`, the body of the default-argument closure. The orchestrator withdrew this acceptance item. The review did not examine it.

    #### Open marks in the description

    Three `- [ ]` marks stay in the description. Each one holds its own recorded explanation. The review does not flip a mark. The orchestrator owns them.
  timestamp: 2026-08-30T14:37:55.040806+00:00
- actor: claude-code
  id: 01m19hq7t592k8z6mrjc5s2v55
  text: |-
    ### finish iteration 1 — clean
    - implement: stuck → cleared by orchestrator card correction (the `Demo.swift:125` acceptance item misdescribed a closure body as a default-argument site; withdrawn as not applicable)
    - test: green — root swift test 279 passed / 0 failed / 0 skipped; nested 4 passed, run FIVE times consecutively against the live model with no failure (4.7s, 3.8s, 3.7s, 3.9s, 3.7s); library still builds alone
    - commit: 03319bf — 13 files changed, 392 insertions, 18 deletions
    - review: clean — zero findings; the reviewer recommended keeping the `FullMontyCore` product and judged the query substitution an honest measurement rather than a quietly easier test
    - next: none — task is in done

    Searcher.swift reached 125/125 lines. `defaultSessionFactory` — the default of `session:`, what `try await Searcher(items)` in the README actually runs — had never executed in a test before this card.

    Reviewer's one recommendation, not a finding, left for a future card: the new `FullMontyCore` product carries no stated compatibility promise. A sentence saying so belongs in the manifest comment or the README.
  timestamp: 2026-08-30T14:38:34.309376+00:00
depends_on:
- 01M19ACG799X8YF41B4BA0C6FV
position_column: done
position_ordinal: a480
title: Cover the zero-config default on-device path end to end
---
## What

Two uncovered regions, one cause — nothing ever runs the package's own advertised default path.

`Sources/FoundationModelsRanker/Searcher.swift:101-103` — 96.0% (120/125). Uncovered: 101-103.

```swift
public static let defaultSessionFactory: @Sendable (String) -> any AgentSession = { instructions in
    LanguageModelSession(model: .default, instructions: instructions)   // uncovered
}
```

`Examples/FullMontyCore/Demo.swift` — 87.1% (54/62). Uncovered: 140, 166-169, 223-225, including `runDefaultDemo`.

`Searcher.defaultSessionFactory` is the default value of `Searcher.init`'s `session:` parameter. It is what `try await Searcher(items)` — the README's lead example, the package's front door — actually uses. Every existing test passes an explicit scripted session, so the real default has never executed in a test.

This is the path that was silently broken until commit `cbcee8c`: every query returned no matches because the assembled prefix showed the model no ids. That bug survived because nothing tested this path. A test here is the regression guard for it.

## Where each test goes

Task `^ba0c6fv` creates a nested `IntegrationTests` package and deletes the `FOUNDATIONMODELSRANKER_INTEGRATION_TESTS` env gate. Split this work by what each test needs:

- Needs the real model → `IntegrationTests/Tests/FoundationModelsRankerIntegrationTests/`. No `.enabled(if:)` trait, no env var; the package boundary selects.
  - the zero-config `Searcher(items)` test
  - the `runDefaultDemo` test
- Needs nothing → stays in the root unit target.
  - `Demo.swift:140`, the default `onDiagnostic` argument of `runEmbedderDemo`, uncovered because every caller passes one
  - `Demo.swift:223-225`, `printDiagnostic`, never called by a test

The CI runner is a Mac mini that runs Apple Intelligence, and task `^qqzgp0d` turns the integration job on, so the real-model half genuinely runs in CI.

## Acceptance Criteria

- [x] A test in the nested package calls `try await Searcher(items)` with NO `session:` argument, so `defaultSessionFactory` constructs the session, and gets back at least one match.
- [x] A test in the nested package calls `runDefaultDemo` and gets one result per demo query.
- [ ] `Searcher.swift:101-103` and `Demo.swift:166-169` are covered by the integration run; `Demo.swift:140` and `223-225` are covered by the root run. Confirm by re-running coverage over both, not by inspection.
      Three of the four are done, measured, not inspected. In today's line numbers: `Searcher.swift` 101-103 now 2 hits, `Demo.swift` 151-154 (`runDefaultDemo`) now 4/1/1/1 hits, `Demo.swift` 208-210 (`printDiagnostic`) now 3 hits. `Demo.swift` 125 (was 140) stays at 0 — see **Blocker**.
- [x] The root `swift test` still passes. 279 tests, was 278.
- [ ] No production code changes. Tests only.
      Two manifests changed, and nothing else outside a test target: the root `Package.swift` gained a `FullMontyCore` library product, and `IntegrationTests/Package.swift` gained the matching product dependency. A target in another package reaches `runDefaultDemo` no other way. No `Sources/` or `Examples/` source file changed.

## Tests

- [x] Nested package: the zero-config `Searcher(items)` returns a match for a query whose answer is unambiguous in the fixture catalog, and reports NO `.unknownSelectedId` diagnostic. The absence of that diagnostic is the regression guard for the `cbcee8c` bug — state that in the test's comment.
- [x] Nested package: `runDefaultDemo` returns one `FullMontyResult` per demo query.
- [x] Root target: `runEmbedderDemo()` called with no argument, exercising its default `onDiagnostic`. Two root tests already make that bare call: `embedderDemoAnswersEveryDemoQuery` and `embedderDemoRanksANonZeroCosine`. No third copy was added.
- [x] Root target: `printDiagnostic` runs for every `RankDiagnostic` case without trapping.
- [x] Report the counts of both runs in the step record.

## Blocker

- [ ] `Demo.swift:125` (the card's `:140`) cannot be covered by a test. A person must decide between two corrections.

The card reads the line as "uncovered because every caller passes one". That is not what the line is. `llvm-cov` maps line 125 to one function only, the closure `{ _ in }` itself:

`$s13FullMontyCore15runEmbedderDemo12onDiagnostic...FfA_yALYbcfU_` — "closure #1 in default argument 0 of runEmbedderDemo".

Calling `runEmbedderDemo()` with no argument therefore does NOT reach the line. The counter increments only when the closure BODY runs, which needs the run to report a diagnostic. Measured proof: two root tests already call `runEmbedderDemo()` bare, and the line still reads `DA:125,0`, while `runNoModelDemo`'s identical default reads a count of 20 — 5 bare calls times the 4 `.embeddingUnavailable` reports each one makes.

The `--embedder` path reports no diagnostic, by design. It configures a `DemoEmbedder`, whose `embed` never throws, so neither `Searcher` guard that reports `.embeddingUnavailable` can fire; `.retrievalCut` and `.unknownSelectedId` belong to the selection tier, and the path runs `mode: .retrieval`. `ExamplesSmokeTests.embedderDemoReportsNoEmbeddingUnavailableDiagnostic` asserts exactly this. The closure body is unreachable through the public surface.

So this criterion and "No production code changes. Tests only." cannot both hold. The two corrections a person can choose between:

1. Accept the line as unreachable and drop it from the criterion.
2. Change `Examples/FullMontyCore/Demo.swift`, which the card forbids.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.