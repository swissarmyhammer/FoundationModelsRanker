---
assignees:
- claude-code
depends_on:
- 01M16WV88B4043AXS1XY2ZNSQB
position_column: todo
position_ordinal: '8380'
title: Delete the live-Router path from the FullMonty example
---
## What

`Examples/FullMontyCore/LiveRouter.swift` is the only example code that uses `FoundationModelsRouter`, MLX, and Hugging Face. Delete it. Keep the two paths that do not need Router: the default on-device system model path, and the `--no-model` keyword-only path.

`LiveRouter.swift` also holds two symbols that other code uses. Move them first:

- `foundationModelsRankerIntegrationEnvVar` (line 36)
- `isFoundationModelsRankerIntegrationEnabled` (lines 39-41)

`Tests/FoundationModelsRankerTests/AgentSessionDispatchTests.swift:71` uses the second symbol to gate a test that needs Apple Intelligence. That gate has nothing to do with Router, so it must keep working.

Files to change:

- `Examples/FullMontyCore/LiveRouter.swift` — delete the file.
- `Examples/FullMontyCore/Demo.swift` — add `foundationModelsRankerIntegrationEnvVar` and `isFoundationModelsRankerIntegrationEnabled`, both `public`, copied without a change. Update the file header at line 22 to drop the live-Router path.
- `Examples/FullMonty/main.swift` — delete the `if isFoundationModelsRankerIntegrationEnabled` branch (lines 39-42) and the mention of the branch in the `else` message (lines 51-52). Update the header comment at lines 19-37 to describe two paths, not three.
- `Tests/FoundationModelsRankerTests/ExamplesSmokeTests.swift` — update the doc comment at line 16. Delete any test that calls `runLiveFullMontyDemo`.

## Acceptance Criteria

- [ ] `Examples/FullMontyCore/LiveRouter.swift` does not exist.
- [ ] `grep -rn "FoundationModelsRouter\|MLX\|HuggingFace\|Tokenizers" Examples/` finds nothing.
- [ ] `swift run FullMonty --no-model` prints ranked results and exits with code 0.
- [ ] `AgentSessionDispatchTests.swift` still compiles and its gate still reads the same environment variable.

## Tests

- [ ] `Tests/FoundationModelsRankerTests/ExamplesSmokeTests.swift` keeps its test of `runNoModelDemo`. The test must pass on a machine with no GPU.
- [ ] Add a test that `isFoundationModelsRankerIntegrationEnabled` is `false` when the environment variable is absent, so the moved gate is covered.
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.