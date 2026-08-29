---
assignees:
- claude-code
position_column: todo
position_ordinal: '80'
title: Update SelectionConfig.capacityCharacterLimit's doc comment to count the candidate id headings
---
## What

`Sources/FoundationModelsRanker/Selection/SelectionConfig.swift` documents `capacityCharacterLimit` as:

> The assembled prefix's character budget (preamble + every candidate's summary block)

`SelectionTier.assemblePrefix` measures more than that. The assembled prefix is the preamble, then a `# Candidates` header, then one entry for each candidate, and each entry is `## <id>` above that candidate's summary block. The headings count against the budget, so the parenthetical under-states what the limit measures.

Found while doing task `^3t4nhk7`, which corrected the same staleness in `plan.md` §6. That card was scoped to `plan.md`, so this comment was left alone.

## Acceptance Criteria

- [ ] The `capacityCharacterLimit` doc comment names the `# Candidates` header and the `## <id>` headings as part of the measured prefix.
- [ ] No other doc comment in `SelectionConfig.swift` describes the assembled prefix in a way that disagrees with `SelectionTier.assemblePrefix`.

## Tests

- [ ] None. This is a documentation change with no code behavior to test.
