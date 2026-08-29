---
assignees:
- claude-code
position_column: todo
position_ordinal: '8980'
title: Render each candidate id in the assembled selection prefix
---
## What

The selection prompt never shows the model an id. `SelectionTier.assemblePrefix(preamble:ids:catalog:)` joins `catalog.summaryBlock(forID:)` values and nothing else. `SearchCorpus.summaryBlock(forID:)` (`Sources/FoundationModelsRanker/SearchCorpus.swift:211`) returns `rows[id]?.summary`, which is the bare summary text. The preamble then tells the model "Do not invent ids", but the model has seen no ids at all.

Measured on 2026-08-29 with `swift run FullMonty` on the default on-device path: every query printed `(no matches)`, and every query reported a diagnostic of the form `unknownSelectedId(id: "Search file contents with regular expressions")`. The model answered with a description, because a description is all it saw.

Until now a Router caller did not see this. Its id-enum `Grammar` made the decoder emit a member of the id set, whatever the prompt showed. Task `^4kx83sx` removes the grammar from the seam. After that task lands, nothing corrects the prompt. This task must land first.

Files to change:

- `Sources/FoundationModelsRanker/Selection/SelectionTier.swift` — change `assemblePrefix(preamble:ids:catalog:)` so each candidate renders its id together with its summary. Use a heading that a model reads as a label, for example:

  ```
  ## <id>
  <summary>
  ```

  The whole-catalog overload `assemblePrefix(preamble:catalog:)` calls the same helper, so one change covers both the cached-root path and the over-budget path.
- Check every test that asserts on prefix text or on `capacityCharacterLimit` boundaries. The prefix grows by the length of each id plus the heading, so a fixture that sits on a budget edge may cross it. Adjust the fixture, not the budget.

Do not change `SelectionCatalog.summaryBlock(forID:)` or `SearchCorpus`. The id belongs to the prefix format, not to the stored summary.

## Acceptance Criteria

- [ ] `SelectionTier.assemblePrefix(preamble:ids:catalog:)` output holds every id it was given.
- [ ] The output still holds every candidate summary.
- [ ] The over-budget path's prefix holds only the top-M ids, not every catalog id.
- [ ] `swift build` gives no error and `swift test` passes.

## Tests

- [ ] Add to `Tests/FoundationModelsRankerTests/SelectionTests.swift`: `assemblePrefix` over a three-item catalog returns text that holds all three ids and all three summaries.
- [ ] Add a test that drives `SelectionTier.search(intent:limit:)` with a `ScriptedAgentSession` and asserts the instructions text the session received holds each catalog id.
- [ ] Add to `Tests/FoundationModelsRankerTests/OverBudgetTests.swift`: over budget, the one-off session's instructions hold the top-M ids and do not hold an id that was cut.
- [ ] Add a regression test for the measured failure: when the scripted session answers with an item's summary text rather than its id, `search(intent:limit:)` returns no match for it and reports `.unknownSelectedId`. This pins the backstop that the deleted grammar used to provide.
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.