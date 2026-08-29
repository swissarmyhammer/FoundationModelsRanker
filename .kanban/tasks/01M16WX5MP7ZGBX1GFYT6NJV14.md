---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m176dw8qrf9t9zgvgtrwj1yg
  text: |-
    Research done. What the code shows now (the card sketch is older than the last seven commits):

    - `SelectionConfig.model` is already `@Sendable (String) -> any AgentSession` (instructions text only, no grammar argument). Only the property name changes; the closure shape does not.
    - Readers of `config.model`: `SelectionTier.cachedRootSession()` and `SelectionTier.overBudgetSearch(intent:limit:)`, plus one test, `LanguageModelSessionSupportTests.languageModelSessionFactoryClosureTypeChecksAsASelectionConfigModelFactory`, which calls `config.model("selection guidance")` directly. That test must read through `sessionSource` after the change.
    - Callers of the `init(model:...)` form: `Searcher.init` and many tests. The signature stays, so none of them change.
    - `SelectionTier.assemblePrefix` renders each candidate as `## <id>` above its `summaryBlock(forID:)`, so the `.session` prompt carries the ids.

    Design chosen for `.session`, and why:
    - `cachedRootSession()` returns the supplied session AS IT IS (no fork). `search(intent:limit:)` already forks the root once per call, so the session the model answers on is `try await supplied.fork()` -- exactly what the card asks -- and `fork()` is called exactly once per `search` call. Forking inside `cachedRootSession()` too would make it 1 + N forks per N searches, which breaks the "once per search" requirement.
    - `overBudgetSearch(intent:limit:)` has no cached root, so it forks the supplied session directly.
    - One `private func prompt(prefix:intent:)` gives both paths their prompt.
  timestamp: 2026-08-29T16:42:44.375520+00:00
- actor: claude-code
  id: 01m178f5bw61vxhmvnbndrbxww
  text: |-
    ### test — green
    - evidence: `swift build` clean (only the documented mlx-swift Cmlx.bundle warning). `swift test` — 263 tests in 21 suites passed, 0 failed. Only skip is the documented `selectionTierWithABareLanguageModelSessionReachesGuidedGeneration` (gated test). All 8 required tests found and passing: `theSessionInitializerStoresTheSuppliedSession`, `theModelInitializerWrapsItsFactoryInTheFactorySource`, `theSessionInitializerClampsNegativeLimitsToZero`, `aFactorySessionIsPromptedWithTheIntentAlone`, `aSuppliedSessionIsPromptedWithThePrefixAboveTheIntent`, `aSuppliedSessionIsForkedOncePerSearchAndNeverRebuilt`, `overBudgetFactorySessionIsPromptedWithTheIntentAlone`, `overBudgetSuppliedSessionIsPromptedWithTheTopMCandidatesOnly`. Checked touched files (`SelectionConfig.swift`, `SelectionTier.swift`, `LanguageModelSessionSupport.swift`, `ScriptedAgentSession.swift`) for stray TODO/FIXME markers and dangling symbol references — none found. `swift run FullMonty --no-model` exit 0. `swift run FullMonty --embedder` exit 0 — both logs show only the documented mlx warning.
    - next: ready for review.
  timestamp: 2026-08-29T17:18:23.612077+00:00
- actor: claude-code
  id: 01m178gss41erbnqzytqb8zbb1
  text: |-
    ### commit — changed
    - evidence: 18b3c2f feat(selection): let a caller supply one session to SelectionConfig — 12 files changed, 391 insertions(+), 41 deletions(-)
    - next: push when ready
  timestamp: 2026-08-29T17:19:17.284073+00:00
- actor: claude-code
  id: 01m178sksmw5r5ksnf8h9jbx5z
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (commit 18b3c2f). 7 validators ran, 0 failed. Counts: 0 findings, 0 confirmed, 0 refuted. 8 files reviewed; 4 `.kanban/` files excluded by `.reviewignore`. No prior `## Review Findings` section on this card.
    - checks: `SelectionConfig.init(model:preamble:capacityCharacterLimit:candidateLimit:)` keeps its exact signature, its defaults, and its clamps; it wraps the closure in `.factory` through the shared private init, so no caller changes behavior. No code reads `config.model` now. With `.session`, `prompt(prefix:intent:)` gives `<prefix>\n\n# Task\n\n<intent>`, and the prefix is the same text that `.factory` puts in the instructions: `assembledPrefix` on the cached-root path, the per-call `prefix` on the over-budget path. Both paths make the prompt with the one helper `prompt(prefix:intent:)`; there is no second copy of the assembly. `cachedRootSession()` gives back the supplied session as it is and never replaces it; `search(intent:limit:)` forks it one time for each call, and `overBudgetSearch(intent:limit:)` forks the supplied session directly.
    - note: `LanguageModelSession.fork()` gives back `self`. The file `LanguageModelSessionSupport.swift` already writes down this tradeoff and tells the caller what to do instead. The engine found no fault here.
    - next: done.
  timestamp: 2026-08-29T17:24:06.068121+00:00
- actor: claude-code
  id: 01m178tmps5et2np1nz1fean2k
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 8 files; SelectionSessionSource added with .factory and .session, one shared prompt(prefix:intent:) helper, 8 new tests. The implement agent was terminated mid-run after it hung on an LSP `diagnostics` call, so it never wrote its own record. Its edits were complete on disk.
    - test: green — independently re-verified after the kill: swift test 263 passed, 0 failed, 1 documented gated skip; both FullMonty paths exit 0; no half-edited file
    - commit: 18b3c2f — 12 files changed
    - review: clean — zero findings; all four directed checks passed, including that the existing init keeps its exact signature and that .session really delivers the prefix
    - next: none — task is in done

    The description checkboxes stay unchecked because the implement agent was killed before it could mark them. The work itself is verified by the test and review steps above.

    Tooling note for later cards: do not call the `diagnostics` MCP op in this workspace. sourcekit-lsp is not installed here, and the call hangs. Use `swift build` output instead.
  timestamp: 2026-08-29T17:24:39.769994+00:00
depends_on:
- 01M16WTDBSFXJKRSDK44KX83SX
position_column: done
position_ordinal: 9a80
title: Let a caller supply one AgentSession instead of a session factory
---
## What

`SelectionConfig.model` is a factory: it takes the assembled candidate prefix and returns a new session seeded with that prefix as its instructions. A caller who already holds one `LanguageModelSession` must wrap it in a closure, and that closure must throw the prefix away, because a live session cannot take new instructions. The model then never sees the catalog.

Add a second way to supply the session. The prefix must reach the model on either way.

Add to `Sources/FoundationModelsRanker/Selection/SelectionConfig.swift`:

```swift
public enum SelectionSessionSource: Sendable {
    /// Makes a new session per prefix. The prefix becomes the session's
    /// instructions.
    case factory(@Sendable (String) -> any AgentSession)
    /// Reuses one session. The prefix rides on each prompt.
    case session(any AgentSession)
}
```

Replace the `model` property with `sessionSource: SelectionSessionSource`. Keep the existing `init(model:preamble:capacityCharacterLimit:candidateLimit:)` as a convenience that wraps its argument in `.factory`, so callers of the factory form need no change. Add a second `init` that takes `session: any AgentSession`.

Change `Sources/FoundationModelsRanker/Selection/SelectionTier.swift` so both paths honour the source:

- `.factory(f)` — as today. Session is `f(prefix)`. The prompt is the intent alone.
- `.session(s)` — the session is `try await s.fork()`. The prompt is the prefix, then a blank line, then `# Task`, then a blank line, then the intent.

Both `cachedRootSession()` and `overBudgetSearch(intent:limit:)` must use the same rule. Put the prompt assembly in one `private func prompt(prefix:intent:)` so the two paths cannot drift apart.

## Acceptance Criteria

- [ ] `SelectionConfig` has `sessionSource` and both initializers.
- [ ] The existing factory-form initializer keeps its signature, so no current caller breaks.
- [ ] With `.session`, the model receives the preamble and every candidate summary block in the prompt.
- [ ] With `.factory`, the prompt is the intent alone, exactly as today.
- [ ] `swift build` gives no error.

## Tests

- [ ] Add to `Tests/FoundationModelsRankerTests/SelectionTests.swift`: with `.session`, a `ScriptedAgentSession` records a prompt that holds the preamble, a candidate id, and the intent.
- [ ] Add a test that with `.session`, `SelectionTier` calls `fork()` once per `search(intent:limit:)` call and never makes a new session.
- [ ] Add to `Tests/FoundationModelsRankerTests/OverBudgetTests.swift`: over budget with `.session`, the prompt holds only the top-M candidate blocks, not the whole catalog.
- [ ] Add a test that with `.factory` the prompt is still the intent alone, so the current path does not change.
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.