---
comments:
- actor: claude-code
  id: 01m3vvekv2q3cqz6ah9mnbssfk
  text: |-
    Research done.
    - The prefix, the entry and the prompt come from SelectionTier.assemblePrefix, candidateEntry and prompt(prefix:intent:). candidateRuns counts the header from assemblePrefix(ids: []) and the separator from candidateSeparator, so it follows a new format with no other change.
    - Unit tests that pin the old text: SelectionTests (supplied-session prompt, factory prompt), OverBudgetTests ("## <id>\n" match, "# Task" prompts), SearcherTests ("# Candidates", "## glob", "## <id>\n"), PooledConformanceTests (taskPrompt), SelectionConfigTests (preamble must contain "items" and "ids"; the new preamble from the card has neither word, so this test changes to pin the new wording).
    - The run-split tests compute their limits from assemblePrefix, so the new lengths need no new numbers.
    - No other preamble constant exists in the sources (.librarianDefault is only named in port comments).
    - README and docs/GUIDE.md do not show the prefix or the prompt text. No README change is necessary.
    - The integration package depends only on the root package. To use PooledModel(ref:) it must declare the FoundationModelsExtras package too (same URL and branch as the root manifest).
    - CI does not copy the MLX metallib now (ci.yml says no test loads a real MLX model). A Qwen3-4B test loads one, so ci.yml needs integration-metallib-glob "*Cmlx*/default.metallib", as FoundationModelsMetadataRegistry has.
  timestamp: 2026-10-01T13:46:20.898825+00:00
- actor: claude-code
  id: 01m3vy0t4xpfqt82hwbtvnmx6r
  text: |-
    Implementation landed (TDD).
    - RED: the updated and new unit tests failed for the expected reason (12 tests, 59 issues: old `## <id>` / `# Candidates` / `# Task` text, old preamble, old guide).
    - GREEN: SelectionTier.candidateEntry renders `<candidate>\nid: <id>\ndescription: <summary>\n</candidate>`. assemblePrefix puts one blank line below the preamble and between entries (the constant `partSeparator`, which candidateRuns also counts). prompt(prefix:intent:) sends `<request>\n<intent>\n</request>\n` + `exactIDsLine`; a `.session` source puts the prefix and one blank line first. SelectionConfig.selectionDefault and the Selection.ids @Guide have the card text. Doc comments updated.
    - Integration: new IntegrationTests/.../UriCatalogQwenRealModelTests.swift, a 20-entry URI catalog with one needle on `mlx-community/Qwen3-4B-4bit` (PooledModel), 5 serialized rounds. It passed 5 of 5. With Sources/ stashed (the old prompt), the same test failed 5 of 5 with `.unknownSelectedId(id: "quantum-flux-capacitor")`, so the test reproduces the defect.
    - Needed for the integration test: IntegrationTests/Package.swift now names the FoundationModelsExtras package (same URL and branch as the root manifest), and .github/workflows/ci.yml now gives `integration-metallib-glob: "*Cmlx*/default.metallib"`, because a CI integration test now loads a real MLX model.
    - LiveToolCatalog.summaryBlock now gives the description alone. Before, it repeated `id: <id> --` in the summary, which put a second `id:` text in each `description:` line.
    - README and docs/GUIDE.md show no prefix or prompt text, so they did not change. No other preamble constant exists.
    - Discovery: one full integration run recorded 1 issue in FunctionCatalogRealModelTests (system model). The output was cut, so the query is not known. The suite alone passed 10 of 10 and the next full run passed 6 of 6 suites. Follow-up task ^xrd68c1 measures it.
    - Not done by instruction: push to origin main, and the message to the FoundationModelsMetadataRegistry session. Both are left for the user. The task stays in doing.
  timestamp: 2026-10-01T14:31:14.333489+00:00
- actor: claude-code
  id: 01m3vy0x91qmc1wph3h9epahbe
  text: |-
    ### implement — changed
    - evidence: 13 files — Sources/FoundationModelsRanker/Selection/{SelectionTier,SelectionConfig,Selection}.swift; Tests/FoundationModelsRankerTests/{SelectionTests,OverBudgetTests,SearcherTests,PooledConformanceTests,SelectionConfigTests}.swift, Support/ExpectedSelectionPrompt.swift (new); IntegrationTests/Package.swift, Support/LiveToolCatalog.swift, ZeroConfigSearcherRealModelTests.swift, UriCatalogQwenRealModelTests.swift (new); .github/workflows/ci.yml. `swift test`: 302 tests in 24 suites passed. `swift test --package-path IntegrationTests`: 6 suites passed (URI suite 5 of 5 rounds). Push and the registry message are left for the user.
    - next: /review
  timestamp: 2026-10-01T14:31:17.537189+00:00
- actor: claude-code
  id: 01m3vychmrgv4dtthrpcfzdteb
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (30b6d91). 0 findings, 0 confirmed, 0 refuted. 7 validators ran, 0 failed. 14 files reviewed. 6 .kanban files not reviewed (.reviewignore).
    - next: The orchestrator pushes to origin main, then makes sure that CI is green on the pushed commit.
  timestamp: 2026-10-01T14:37:38.840468+00:00
- actor: claude-code
  id: 01m3vyctt6vdcqerf756zgvwdt
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 14 files
    - test: green — swift test 302 passed; IntegrationTests 6 passed
    - commit: 30b6d91
    - review: clean — 0 findings (7 validators, 14 files)
  timestamp: 2026-10-01T14:37:48.230898+00:00
position_column: done
position_ordinal: b180
title: 'Selection prompt: format each candidate with labeled id and description fields, and ask for the exact id'
---
## What
A real model (Qwen3-4B, and the Apple on-device model before it) answers a shortened id when the id is a URI: for `https://example.com/modules/quantum-flux-capacitor` it answers `"quantum-flux-capacitor"`. The tier drops that id as unknown, so the FoundationModelsMetadataRegistry `BigCatalog` example returns no selection. The cause is the prompt format: each candidate is a Markdown heading `## <id>` followed by its summary, so the id reads like a title, and no instruction says to copy the id exactly.

The answer stays a list of ids, and the tier keeps mapping each id back to the catalog item (`matches(forIDs:limit:)`), so the result stays the verbatim catalog text. Only the prompt text and the output guide change.

New `SelectionConfig.selectionDefault` (`Sources/FoundationModelsRanker/Selection/SelectionConfig.swift`):

```
Each candidate below has an id and a description. Given a request, choose the candidates
that serve it: the fewest that suffice, in order of use when order matters.

Answer with the id of each chosen candidate. Copy each id exactly as it is written after
"id:", character for character, with its full scheme, path and punctuation. An id is not a
name or a title: do not shorten it, change it or make one up.

Answer with an empty list only when no candidate is related to the request at all.
```

New candidate entry (`SelectionTier.candidateEntry(forID:catalog:)` and `assemblePrefix`; remove the `# Candidates` heading and the `## <id>` heading):

```
<candidate>
id: <id>
description: <summaryBlock(forID:)>
</candidate>
```

Entries are separated by one blank line, after one blank line below the preamble. `candidateRuns(preamble:catalog:limit:)` counts the new entry and header lengths.

New prompt (`SelectionTier.prompt(prefix:intent:)`; a `.session` source still puts the prefix first):

```
<request>
<intent>
</request>
Answer with the exact ids of the chosen candidates.
```

New `@Guide` on `Selection.ids` (`Sources/FoundationModelsRanker/Selection/Selection.swift`): "the exact id of each chosen candidate, copied character for character from its id: line; empty only when no candidate is related to the request".

- Update each doc comment and the README section that shows the prefix or the prompt.
- If other preamble constants exist (for example `.librarianDefault`), give them the same id instruction, or delete them if nothing uses them.
- Push to `origin main` when CI is green, and tell the FoundationModelsMetadataRegistry session (`foundationmodelsmetadataregistry-f7`) the sha.

## Acceptance Criteria
- [x] No prompt text contains `## ` before an id or the `# Candidates` heading.
- [x] Each candidate entry is a `<candidate>` block with `id:` and `description:` lines.
- [x] With `mlx-community/Qwen3-4B-4bit` (Extras `PooledModel(ref:)`), a catalog whose ids are URIs gives back the full URI id of the matching candidate, not a shortened one, and the tier reports no `.unknownSelectedId` for it.
- [x] Existing selection behavior (cached root + fork, over-budget runs, unknown-id filter) is unchanged.
- [ ] CI is green on the pushed commit.

## Tests
- [x] Update the unit tests that pin the prefix, the candidate entry and the prompt text (`Tests/FoundationModelsRankerTests/`), and the run-split tests whose lengths change.
- [x] New unit test: an entry for a URI id renders as `<candidate>\nid: https://…\ndescription: …\n</candidate>`.
- [x] New integration test (`IntegrationTests/`): a 20-entry catalog with URI ids (one needle, as in the registry `BigCatalog` example) selected by Qwen3-4B returns the needle's full URI. Run it 5 times; it must pass each time.
- [x] `swift test` and `swift test --package-path IntegrationTests` pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #selection