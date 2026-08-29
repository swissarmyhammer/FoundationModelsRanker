---
assignees:
- claude-code
depends_on:
- 01M16WWNSAG4EN2JDCQ2Q0P8GR
- 01M16WXKX259CBHMWBENQ132HW
position_column: todo
position_ordinal: '8880'
title: Rewrite the README for a package with no dependencies
---
## What

The README names `FoundationModelsRouter` five times and shows an example built on `RoutedEmbedderAdapter` and `RoutedAgentSession`. Both types are gone. Rewrite those parts.

Files to change:

- `README.md`:
  - Line 10-11 — delete "and depends on [FoundationModelsRouter](...)". Put a sentence in its place that says the package has no external dependencies and needs only macOS 27.
  - Lines 32-43 — keep the session factory example. Add a shorter example above it that passes one session: `let searcher = try await Searcher(items, session: LanguageModelSession(model: .default, instructions: "Pick the best tools."))`.
  - Lines 45-62 — delete the Router example. Put a "Bring your own embedder" section in its place. Show a `struct` that conforms to `TextEmbedding`, and say that any embedding backend plugs in the same way. Point at `Examples/FullMontyCore/DemoEmbedder.swift` for a runnable one.
  - Add a short "Guided output" section. Say that `SelectionTier.idEnumSchema(ids:)` returns a JSON Schema source string that constrains the answer to the given ids, and that a caller with a grammar-capable backend can pass it to that backend.
  - `Development` section — the `mlx-swift` bullets are deleted by an earlier task. Update the third bullet, which still says the gated test needs a live Router. It needs Apple Intelligence only.

Leave `plan.md` as it is. It records the original design and is history.

## Acceptance Criteria

- [ ] `grep -in "router\|mlx\|huggingface" README.md` finds nothing.
- [ ] The README states that the package has no external dependencies.
- [ ] Every Swift code block in the README compiles.

## Tests

- [ ] `Tests/FoundationModelsRankerTests/ReadmeExampleTests.swift` — add or update one test per README code block, so each block is compiled and run by the suite. This is the file's stated job.
- [ ] Add a test that reads `README.md` and asserts the text holds no `Router`, `MLX`, or `HuggingFace` token. This keeps the document from drifting back.
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.