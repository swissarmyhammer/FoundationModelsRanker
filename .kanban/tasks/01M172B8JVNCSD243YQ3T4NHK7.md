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
- actor: claude-code
  id: 01m17e3arr3yj44s8syc7ygrhs
  text: |-
    ### commit — changed
    - evidence: f0f626d — 7 files changed (plan.md + 6 kanban board files). Local commit only, not pushed.
    - next: none
  timestamp: 2026-08-29T18:56:47.384046+00:00
- actor: claude-code
  id: 01m17e6hqz8k9mhy5jxzac4b83
  text: |
    ### review — clean
    - evidence: zero new findings. `review sha HEAD~1..HEAD` (commit f0f626d): 0 findings, 0 confirmed, 0 refuted. No validator reads Markdown, so `plan.md` got a manual check. Three checks, all correct:
      1. Format agrees with the code. `SelectionTier.swift` line 359 makes `"\(preamble)\n\n# Candidates\n\(entries.joined(separator: "\n\n"))"`, and line 378 makes each entry as `"## \(id)\n\(summary)"`. The amended bullet (plan.md lines 307-310) says preamble + `# Candidates` + one entry for each candidate, and that each entry is the candidate id as a `## <id>` markdown heading above that candidate's summary block. The two agree.
      2. The amendment note is honest. The note (plan.md lines 318-325) quotes the previous wording word for word. The text at `HEAD~1:plan.md` reads "the full prefix is preamble + `# Candidates` + each candidate's summary block, assembled in `SelectionTier.assemblePrefix`", which is the same text as the quotation. The note gives task `^g69hyyc` as the cause, and commit cbcee8c is that task: it added `candidateEntry(forID:catalog:)` to render the `## <id>` heading. The reason in the note ("A prefix that shows only the summary blocks does not show the model which ids it can return") is the same reason that commit cbcee8c gives.
      3. The change stays in scope. `plan.md` has exactly 1 diff hunk. A word-level diff shows word changes only in the prefix clause and in the new note. All other lines in the hunk are the same words with a new line wrap. No other part of `plan.md` changed, so the historical record stays as it was. The `summaryBlock(forId:)` label spelling at plan.md line 292 and the `summary` mention at line 186 make no statement about the prefix format, and they were correctly left alone.
    - next: none
  timestamp: 2026-08-29T18:58:32.831158+00:00
- actor: claude-code
  id: 01m17e7a00z3bph17857eyhdhn
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — plan.md only; §6 phase 3's prefix-format bullet amended, with a dated note recording the previous wording and the reason
    - test: green — folded into the implement step's own run, because this change touches no compiled file: swift build clean, swift test 273 passed, 0 failed, 0 warnings. A separate test agent would have verified nothing new; recording the fold rather than skipping it silently.
    - commit: f0f626d — 7 files changed
    - review: clean — zero findings; the reviewer verified the amended bullet against the code, verified the quoted previous wording against `git show HEAD~1:plan.md`, and confirmed a single diff hunk so the rest of the historical record is untouched
    - next: none — task is in done
  timestamp: 2026-08-29T18:58:57.664656+00:00
position_column: done
position_ordinal: '9e80'
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
