---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m17ea3jx37t8dnkdgdka3k9s
  text: |-
    Picked up. Research done.

    `SelectionTier.assemblePrefix(preamble:ids:catalog:)` builds:
    `"\(preamble)\n\n# Candidates\n\(entries.joined(separator: "\n\n"))"`, and each entry is `## <id>` above that id's `summaryBlock(forID:)`. `SelectionTier.search(intent:limit:)` guards on `assembledPrefix.count <= config.capacityCharacterLimit`, so the guard measures the whole assembled string -- header and headings included.

    Searched the repository for the stale wording. Two places state it:

    1. `Sources/FoundationModelsRanker/Selection/SelectionConfig.swift` -- the `capacityCharacterLimit` property doc: "The assembled prefix's character budget (preamble + every candidate's summary block)".
    2. `Tests/FoundationModelsRankerTests/OverBudgetTests.swift` -- the suite doc: "when the assembled prefix (preamble + every candidate's `summaryBlock(forID:)`) exceeds `capacityCharacterLimit`".

    Places checked and found correct, so they stay unchanged:

    - `Searcher.swift` `preamble`/`candidateLimit` parameter docs (4 sites) say only "the selection guidance prepended to the assembled prefix" and "how many top-ranked candidates the over-budget selection path seeds a one-off session with". Neither enumerates the prefix parts.
    - `SelectionTier.swift` type doc and `assemblePrefix` docs already name the `# Candidates` header and the id headings.
    - `SelectionCatalog.swift`, `SearchItem.swift`, `SearchCorpus.swift` speak only about the summary feeding the prefix, which is still true.
    - The three other `capacityCharacterLimit` doc sites in `SelectionConfig.swift` (the two public initializers and the private one) say "the assembled prefix's character budget" with no parenthetical, so they do not disagree.
  timestamp: 2026-08-29T19:00:29.405271+00:00
- actor: claude-code
  id: 01m17exxm9zs3eqj90mpgf6eh1
  text: |-
    Implementation landed. Three doc comments corrected. No code behavior changed. The budget value and the guard stay as they are.

    1. `Sources/FoundationModelsRanker/Selection/SelectionConfig.swift`, the `capacityCharacterLimit` property doc. The wrong parenthetical is replaced with a full list of what the budget measures: the preamble, the `# Candidates` header, and one `## <id>` heading above each candidate's summary block.
    2. `Sources/FoundationModelsRanker/Selection/SelectionTier.swift`, the `SelectionTier` type doc. This doc gives the prefix as a formula. It named the id headings but not the `# Candidates` header, so the formula was short one part. The header is now in the list.
    3. `Tests/FoundationModelsRankerTests/OverBudgetTests.swift`, the suite doc. It carried the same wrong parenthetical as site 1. It is now correct.

    Discovery: the defect had a third instance. The card named only `SelectionConfig.swift`, but `SelectionTier.swift`'s type doc had the same cause -- a doc that claims to list every part of the prefix and does not. All three are corrected.

    Sites checked and left unchanged, because each is correct as written:

    - `Searcher.swift`, the `preamble` and `candidateLimit` parameter docs at 4 call sites. They say only "the selection guidance prepended to the assembled prefix" and "how many top-ranked candidates the over-budget selection path seeds a one-off session with". Neither lists the parts of the prefix.
    - The two `assemblePrefix` docs and the `candidateEntry` doc in `SelectionTier.swift`. These already name the header and the id headings.
    - The three other `capacityCharacterLimit` parameter docs in `SelectionConfig.swift`. They say "the assembled prefix's character budget" with no list.
    - `SelectionCatalog.swift`, `SearchItem.swift`, `SearchCorpus.swift`, `StreamingSearchCorpus.swift`. They say the summary feeds the prefix, which is still true.
    - `OverBudgetTests.swift` line comments about the budget boundary and the `## alpha` heading. Both match the code.
  timestamp: 2026-08-29T19:11:18.665474+00:00
- actor: claude-code
  id: 01m17ey1dwcaw6np4mbfmx8ttq
  text: |-
    ### implement — changed
    - evidence: 3 files — Sources/FoundationModelsRanker/Selection/SelectionConfig.swift, Sources/FoundationModelsRanker/Selection/SelectionTier.swift, Tests/FoundationModelsRankerTests/OverBudgetTests.swift. `swift build` complete, 0 warnings. `swift test` passed, 273 tests in 21 suites, 0 failures.
    - next: /review
  timestamp: 2026-08-29T19:11:22.556452+00:00
position_column: doing
position_ordinal: '80'
title: Update SelectionConfig.capacityCharacterLimit's doc comment to count the candidate id headings
---
## What

`Sources/FoundationModelsRanker/Selection/SelectionConfig.swift` documents `capacityCharacterLimit` as:

> The assembled prefix's character budget (preamble + every candidate's summary block)

`SelectionTier.assemblePrefix` measures more than that. The assembled prefix is the preamble, then a `# Candidates` header, then one entry for each candidate, and each entry is `## <id>` above that candidate's summary block. The headings count against the budget, so the parenthetical under-states what the limit measures.

Found while doing task `^3t4nhk7`, which corrected the same staleness in `plan.md` §6. That card was scoped to `plan.md`, so this comment was left alone.

## Acceptance Criteria

- [x] The `capacityCharacterLimit` doc comment names the `# Candidates` header and the `## <id>` headings as part of the measured prefix.
- [x] No other doc comment in `SelectionConfig.swift` describes the assembled prefix in a way that disagrees with `SelectionTier.assemblePrefix`.

## Tests

- [x] None. This is a documentation change with no code behavior to test.
