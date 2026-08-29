---
assignees:
- claude-code
position_column: todo
position_ordinal: '8980'
title: Update plan.md's selection-prefix description to include the candidate id
---
## What

`plan.md` phase 3 describes the assembled selection prefix as:

> the full prefix is preamble + `# Candidates` + each candidate's summary block, assembled in `SelectionTier.assemblePrefix`

Task `^g69hyyc` changed that format. Each candidate now renders its id as a markdown heading above the summary:

```
## <id>
<summary>
```

The description in `plan.md` is now stale. `SelectionTier`'s own doc comments cite "plan.md §6" as the authority for the prefix format, so a reader who follows that pointer finds a description that contradicts the code.

Found while implementing `^g69hyyc`. That card listed only `SelectionTier.swift` and the test files as files to change, so `plan.md` was left alone rather than edited outside the card's stated scope.

## Acceptance Criteria

- [ ] The phase 3 bullet in `plan.md` that describes the prefix states that each candidate renders its id as a markdown heading above its summary block.
- [ ] No other statement in `plan.md` about the prefix format contradicts `SelectionTier.assemblePrefix`.

## Tests

- [ ] None. This is a documentation change with no code behavior to test.
