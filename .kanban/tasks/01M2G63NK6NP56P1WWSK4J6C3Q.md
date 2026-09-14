---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m2g673mnng1ccfhja80vkk0k
  text: |-
    Research:
    - `SelectionTier.search` has `guard limit > 0` only. For a catalog with zero ids, `assembledPrefix` is the preamble and an empty `# Candidates` part. It fits the budget, so the tier forks the root session and sends one prompt.
    - The over-budget path already sends no prompt for zero ids, because `candidateRuns` is empty. The under-budget path is the defect.
    - The test support has `ScriptedAgentSession` (counts `respond` calls and `fork` calls) in `Tests/FoundationModelsRankerTests/Support/ScriptedAgentSession.swift`, and `FixtureSelectionCatalog([])` gives an empty catalog.
    - `SelectionTests.emptyCatalogSearchReturnsNoMatchesWithoutCrashing` exists, but it scripts a valid `{"ids":[]}` answer. Thus it passes today and does not find the extra model call. The new test asserts zero calls and zero forks.
  timestamp: 2026-09-14T14:47:54.261450+00:00
- actor: claude-code
  id: 01m2g68nw4f5c06c6yqz83hs88
  text: |-
    Implementation:
    - RED: added `SelectionTests.emptyCatalogSearchSendsNoPromptToTheSession`. It supplies a `ScriptedAgentSession` and a `FixtureSelectionCatalog([])`. Before the fix it failed with `forkCount → 1` and `callCount → 1`.
    - GREEN: added `guard !catalog.ids.isEmpty else { return [] }` beside `guard limit > 0` in `SelectionTier.search`, and a doc note under `- Returns:`.
    - The signature of `search` did not change, so no caller changes.
    - Not done, as the orchestrator instructed: no commit, no push. The card text says "Commit locally only"; the `/finish` commit step does that.

    ### implement — changed
    - evidence: `swift test` gave 283 tests in 22 suites, all passed, 0 build warnings. Files: Sources/FoundationModelsRanker/Selection/SelectionTier.swift, Tests/FoundationModelsRankerTests/SelectionTests.swift
    - next: review
  timestamp: 2026-09-14T14:48:45.700223+00:00
- actor: claude-code
  id: 01m2g6a83szj0y3k5ntzzwsfp4
  text: |-
    ### test — green
    - evidence: swift test — 283 passed, 0 failed, 0 skipped, 0 warnings
    - next: commit a local checkpoint, then review HEAD~1..HEAD
  timestamp: 2026-09-14T14:49:37.145153+00:00
position_column: doing
position_ordinal: '80'
title: Add an empty-catalog guard to SelectionTier.search
---
Request from the FoundationModelsSkills session (their task ^w8cg4t6).

## The problem
`SelectionTier.search` in `Sources/FoundationModelsRanker/Selection/SelectionTier.swift` guards `limit > 0` only. For a catalog of zero items, the prompt is the preamble and an empty `# Candidates` part (see around line 433). The prompt stays below the budget, so the tier sends it to the model. The model answers with prose, and `Selection/AgentSession.swift:111` (`return try T(GeneratedContent(json: raw))`) throws when it decodes that prose as JSON. In the SWE-bench run of 2026-09-13, this failure killed the turn of 3 of 16 instances of FoundationModelsACPAgent.

FoundationModelsSkills now has its own guard (commit 027a1d2), but other callers of `MetadataSearcher` in `.auto` or `.selection` mode still reach the tier with an empty catalog.

## The work
- [ ] Beside `guard limit > 0` in `SelectionTier.search`, add a guard for an empty catalog. Return an empty result, and do not call the session.
- [ ] Add a unit test with a session double: a tier over zero items gives an empty result, and the double gets zero calls.

## When it is complete
- A selection tier over zero items sends no prompt and does not throw.

Commit locally only. Do not push.