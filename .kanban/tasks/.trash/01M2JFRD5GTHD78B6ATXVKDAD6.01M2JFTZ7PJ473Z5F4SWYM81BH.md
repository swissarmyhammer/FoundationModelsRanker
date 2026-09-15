---
assignees:
- claude-code
position_column: todo
position_ordinal: '8180'
title: Remove the Router design from plan.md and state the embedder boundary
---
## What
The code has no Router dependency now. Earlier commits removed it: `3dc2d99`, `4b5c8bb`, `9cb5dbf`, `392bb5f`, `00da13c`, `91b38b2`. The root package and the nested `IntegrationTests` package declare no Router dependency. But `plan.md` still says that Router is the design. Many test doc comments point to `plan.md` sections (§3, §3a, §4, §6), so the document must agree with the code.

Change `plan.md` so that it gives the current design:
- The package takes an embedder. `Searcher` and `HybridRanker` take a caller-supplied `any TextEmbedding`. The package ships no embedder and no adapter.
- If the family needs a shared place to define embedders, that place is `FoundationModelsExtras`. It is not this package, and it is not Router.
- The package declares no package dependency. The nested `IntegrationTests` package depends only on the root package, by path.

Sections to change:
- §1 table, line 30 (`RoutedEmbedderAdapter` row): say that the adapter was not kept.
- §3 tree, line 111 (`RoutedEmbedderAdapter.swift`): remove it.
- §3 bullets, lines 125-131: replace "`FoundationModelsRouter` is a plain required dependency ..." with the no-dependency rule and the Extras rule above. Keep the macOS 27 floor, but give the FoundationModels v2 reason, not Router.
- §3a example, lines 148-180: remove `import FoundationModelsRouter`. Replace the "true full monty" block with a caller-supplied `TextEmbedding` conformer, as in the README `MyEmbedder` example.
- §3a rules, lines 193-200: remove `RoutedAgentSession` and `idEnumGrammar`. Say that a backend with JSON Schema grammar support uses `SelectionTier.idEnumSchema(ids:)`.
- §3a FullMonty paragraph, lines 219-223: remove the live-Router, mlx-community, and MLX/Hugging Face text. Give the current paths: default system model, `--no-model`, `--embedder` (`DemoEmbedder`).
- §4 item 3, lines 236-238: say that the adapter was not kept.
- §6 phase 1 item 2, line 266, "+ adapter": remove it.
- §6 phase 3, lines 300-301 (`idEnumGrammar` / Router's `Grammar`) and line 350 ("without Router"): update.
- §7 risk, lines 374-377: remove the FoundationModelsRouter comparison.
- Add one dated note (2026-09-15), in the same style as the "*Amended ...*" notes. It must say that Router was removed and why.

Files:
- `plan.md` (only this file)

Do not add a test that makes sure Router stays absent. The user does not want guard tests for this.

## Acceptance Criteria
- [ ] `plan.md` does not contain `FoundationModelsRouter`, `RoutedEmbedderAdapter`, `RoutedAgentSession`, `RoutedEmbedder`, `idEnumGrammar`, `mlx-community`, or `HuggingFace`. Check this with `rg` during the work. Do not add a test for it.
- [ ] `plan.md` §3 says that the package declares no package dependency, and that shared embedder definitions belong in `FoundationModelsExtras`.
- [ ] The §3a Swift example uses only `FoundationModels` and `FoundationModelsRanker`, and its API names agree with the current public API (`Searcher`, `SearchItem`, `TextEmbedding`).
- [ ] No source, test, or manifest file changes.

## Tests
- [ ] No new test. This is a documentation change only.
- [ ] Run `rg -n "FoundationModelsRouter|RoutedEmbedder|RoutedAgentSession|idEnumGrammar|mlx-community|HuggingFace" plan.md`. Expected result: no match.
- [ ] Run `swift test`. Expected result: the full hermetic suite passes, with no change from before.