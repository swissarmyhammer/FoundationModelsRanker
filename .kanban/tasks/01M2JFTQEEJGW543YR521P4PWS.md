---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m2jga152kx72k1b6nf4k367j
  text: |-
    Baseline before the first edit:
    - `swift build 2>&1` (clean build in a new scratch path, so that all files compile): 0 `warning:` lines, exit 0. A cached `swift build` in `.build` also gives 0 `warning:` lines.
    - `swift test`: "Test run with 283 tests in 22 suites passed".
    Research: `rg -n "plan\.md|§" Sources` finds references in 19 files, as the task lists. Many pointers continue on the next comment line (for example "(plan.md\n// §3a)"). Some have a quoted plan heading (for example "Verbatim lookup").
  timestamp: 2026-09-15T12:22:44.642331+00:00
- actor: claude-code
  id: 01m2jgkf2zz9zr2w61s0fna7vc
  text: |-
    Implementation done. Comment-only edits in 19 files in `Sources/FoundationModelsRanker/`. No change to `Tests/`, `Examples/`, `Package.swift`, or `plan.md`.
    - Pointers only ("(plan.md §3)", "(see plan.md \"Search\")", "(plan.md §6 phase 3)") are removed. Lineage notes ("Ported from ...", "Lineage: ... -> FoundationModelsRanker") stay.
    - A pointer that gave the reason for a design choice now has the reason in the comment:
      - `LanguageModelSessionSupport.swift` header: "The code never hardcodes the selection model: the caller always chooses it." SDK note: "(the `.fast` and `.default` model names must agree with the macOS 27 SDK)". "the retroactive conformance §3a promises" becomes "a retroactive conformance". The `respond(to:generating:)` doc now says "the rule that the session sets how its output is constrained". The `fork()` doc now says "The caller, not this package, chooses the model."
      - `SelectionMatch.block` doc: "The code, not the prompt, keeps the block verbatim."
      - `CosineScoring.swift` header: "The two repos' cosine-scoring strategies are really different. This file keeps them side by side ..."
      - `Searcher.swift` header: the quoted plan guidance is now in the comment itself: "The preferred shipped default is the `.fast` variant of the on-device system model, but that is guidance, not a requirement."
    - Quoted plan headings are removed with the pointer: "Verbatim lookup", "IDs only, grammar-enforced", "decision #4", "Genuinely different (stays put)", "Verbatim by construction, not by prompt".
    - Pointers that continue on the next comment line (for example `(plan.md\n/// §6)`) are removed as one unit.
    Rules loaded with `dump validators` for `.swift` (60 rules). The rules that apply to comment-only edits are missing-docs-swift, no-commented-code, and doc-parameter-naming. No public doc comment was removed, and no `- Parameter` key was changed. No Router text was added.
  timestamp: 2026-09-15T12:27:53.823864+00:00
- actor: claude-code
  id: 01m2jgm1r5kwwdjjce3c5dg9z6
  text: |-
    ### implement — changed
    - evidence: 19 files changed in `Sources/FoundationModelsRanker/` (76 insertions, 76 deletions, comment lines only). `rg -n "plan\.md" Sources`: no match (exit 1). `rg -n "§" Sources`: no match (exit 1). `git diff -U0 -- Sources | rg '^[+-][^+-]' | rg -v '^[+-]\s*//'`: no match (exit 1). No Router text in added lines (exit 1). Warnings: baseline 0, after 0 (clean build in a new scratch path, and `swift build` in `.build`). Tests: baseline 283 tests in 22 suites passed, after 283 tests in 22 suites passed.
    - next: `/review`. The task stays in `doing`. No commit was made.
  timestamp: 2026-09-15T12:28:12.933903+00:00
- actor: claude-code
  id: 01m2jgnwx8ra7nq0eeqpfnkswr
  text: |-
    ### test — green
    - evidence: `swift test` — 283 tests, 22 suites, 0 failed, 0 skipped. `swift build` — build complete, 0 warnings. `swift build --package-path IntegrationTests --build-tests` — build complete, 0 warnings (real-model tests not run).
    - next: none. No fix was needed.
  timestamp: 2026-09-15T12:29:13.512682+00:00
position_column: doing
position_ordinal: '80'
title: Remove plan.md references from the library sources
---
## What
`plan.md` is the original extraction plan. The user wants it removed because the work that it describes is complete. Before we delete it, the comments that point to it must stop pointing to it. This task changes the doc comments and code comments in `Sources/FoundationModelsRanker/` only. It is a comment-only change: no code, no API, and no behavior changes.

Files and reference counts (`rg -c "plan\.md" Sources`):
- `Sources/FoundationModelsRanker/Selection/SelectionTier.swift` (9)
- `Sources/FoundationModelsRanker/Selection/LanguageModelSessionSupport.swift` (7)
- `Sources/FoundationModelsRanker/Searcher.swift` (6)
- `Sources/FoundationModelsRanker/Selection/SelectionMatch.swift` (3)
- `Sources/FoundationModelsRanker/SearchItem.swift` (3)
- `Sources/FoundationModelsRanker/HybridRanker.swift` (3)
- `Sources/FoundationModelsRanker/BM25.swift` (3)
- 2 each: `Trigram.swift`, `Tokenizer.swift`, `Selection/SelectionConfig.swift`, `Selection/RankDiagnostic.swift`, `RRF.swift`, `RankedDocument.swift`
- 1 each: `TextEmbedding.swift`, `Selection/SelectionCatalog.swift`, `Selection/Selection.swift`, `Selection/AgentSession.swift`, `Hit.swift`, `CosineScoring.swift`

Rules for each reference:
- If the comment only points to the plan (for example "(plan.md §3a)"), remove the pointer.
- Remove the section number (`§…`) and any quoted plan heading together with `plan.md`. Do this also when they are on the next comment line, and also when they have no file name. Examples: "(§6 phase 2)" in `CosineScoring.swift`, and "the retroactive conformance §3a promises" in `Selection/LanguageModelSessionSupport.swift`. Every `§` in these files is a plan section number.
- If the comment uses the plan as the reason for a design choice, write the reason in the comment itself, in one short sentence. Then remove the pointer.
- Keep lineage notes (for example "Ported from CodeContextKit's ..."). Remove only the plan part.
- Do not add references to Router.

Do not add a test for this. The user does not want guard tests.

## Subtasks
- [x] Before the first edit, record the baseline. Count the `warning:` lines from `swift build 2>&1`, and record the test count from `swift test`.
- [x] Edit the comments in the files above.
- [x] Run the checks below.

## Acceptance Criteria
- [x] `rg -n "plan\.md" Sources` gives no match.
- [x] `rg -n "§" Sources` gives no match.
- [x] Comment-only: `git diff -U0 -- Sources | rg '^[+-][^+-]' | rg -v '^[+-]\s*//'` gives no match.
- [x] `swift build` gives the same number of `warning:` lines as the baseline.
- [x] `swift test` passes with the same test count as the baseline.

## Tests
- [x] No new test. This is a comment-only change.
- [x] Run the `rg` and `git diff` commands above. Expected result: no match.
- [x] Run `swift build`, then `swift test`. Expected result: both pass, and the results agree with the baseline.