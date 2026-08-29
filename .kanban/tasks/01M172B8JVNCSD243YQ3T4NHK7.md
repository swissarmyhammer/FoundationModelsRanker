---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m17dzthev4gt9x6ag3cn5bar
  text: |-
    Research and decision.

    `SelectionTier.assemblePrefix(preamble:ids:catalog:)` makes `"<preamble>\n\n# Candidates\n"` plus one entry for each id, and `candidateEntry(forID:catalog:)` makes each entry as `"## <id>\n<summary>"`. Commit `cbcee8c` (task `^g69hyyc`) added that heading. The phase 3 bullet in `plan.md` §6 still described the prefix as preamble + `# Candidates` + each candidate's summary block, so a reader who followed the "plan.md §6" citation in the `SelectionTier` doc comments found a contradiction.

    Two options were open: amend the sentence in `plan.md` §6, or delete the "plan.md §6" citation from the doc comments. Option 1 was used. Reason: the bullet is one self-contained sentence in a bullet list, so an amendment note goes under it cleanly. The note keeps the previous wording, the date, and the reason, so the plan stays a record and is not silently rewritten. Option 2 would have deleted a citation that is correct about where the prefix format is specified.

    `plan.md` is the historical design record. Only the one stale sentence was changed, plus the amendment note. No other part of the plan was touched.

    Citations checked in `Sources/FoundationModelsRanker/Selection/SelectionTier.swift`, against the section each one names:
    - File header, "plan.md §6 phase 3" (the port of `SelectionTier` over `any SelectionCatalog`) — agrees. §6 phase 3 gives `SelectionCatalog` as the seam that replaces the source index type. The plan spells the argument label `summaryBlock(forId:)`, the code spells it `summaryBlock(forID:)`. That is a label spelling from the plan era, not a contradiction of the prefix format, and it was left alone.
    - Type doc, "plan.md §6" (the tier over a `SelectionCatalog`) — agrees.
    - Type doc, "plan.md §4" (the summary seeds the prefix; retrieval indexes the full block) — §4 is "API reconciliations" and says nothing about the summary or the prefix, so it does not contradict the code. The statement itself is correct, and §6 phase 3 is the section that carries it. The citation was left alone: it is out of the scope of this card.
    - Type doc, "plan.md §3a" (each selected id carries its real fused score and signals) — agrees with §3a.
    - Type doc, "plan.md §6, decision #4" (IDs only) — §6 has no numbered decisions, so nothing there contradicts the code. §6 phase 3 says "ids-only grammar-constrained output", which agrees. The citation was left alone.
    - `search(intent:limit:)` doc, "plan.md §6" over-budget path — agrees with §6 phase 3 ("over-budget retrieval top-M into a one-off session").
    - `overBudgetSearch(intent:limit:)` doc, "plan.md §6 Over budget" — agrees.
    - `resolveSelection` doc, "plan.md §6 Verbatim lookup" — agrees with §6 phase 3 ("verbatim block lookup").
    - `assemblePrefix(preamble:catalog:)` doc, "plan.md §6" and "plan.md §4" — this is the defect. §6 now describes the `## <id>` heading, so the two agree.
    - `assemblePrefix(preamble:ids:catalog:)` doc, "plan.md §6" — same defect, same fix.
    - `idEnumSchema(ids:)` doc, "plan.md §6 IDs only, grammar-enforced" — agrees with §6 phase 3.

    Discovery, not corrected here: `Sources/FoundationModelsRanker/Selection/SelectionConfig.swift` documents `capacityCharacterLimit` as "The assembled prefix's character budget (preamble + every candidate's summary block)". The budget also counts the `# Candidates` header and each `## <id>` heading. That comment cites no section of `plan.md`, so it does not break this card's check. A new task holds it.
  timestamp: 2026-08-29T18:54:52.462770+00:00
- actor: claude-code
  id: 01m17e0aq535fykeh4a9mn6pm0
  text: |-
    ### implement — changed
    - evidence: 1 file — plan.md. The §6 phase 3 "Selection prompt" bullet now says the prefix is preamble + `# Candidates` + one entry for each candidate, and that each entry is the candidate id as a `## <id>` markdown heading above that candidate's summary block. An amendment note under the bullet gives the date (2026-08-29), the previous wording, and the reason. `swift build`: complete, no warning. `swift test`: 273 tests in 21 suites passed, 0 failed, no warning.
    - next: /review
  timestamp: 2026-08-29T18:55:09.029157+00:00
position_column: doing
position_ordinal: '80'
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

- [x] The phase 3 bullet in `plan.md` that describes the prefix states that each candidate renders its id as a markdown heading above its summary block.
- [x] No other statement in `plan.md` about the prefix format contradicts `SelectionTier.assemblePrefix`.

## Tests

- [x] None. This is a documentation change with no code behavior to test.
