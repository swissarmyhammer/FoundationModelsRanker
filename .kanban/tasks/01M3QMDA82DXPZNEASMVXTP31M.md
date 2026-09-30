---
depends_on:
- 01M3QMD9KJ8T723R02085BEFYY
- 01M3QMD9X40XA640Z9CXCREQAM
position_column: todo
position_ordinal: '8280'
title: Depend on Extras; PooledSession is an AgentSession and PooledEmbedder is a TextEmbedding
---
**Wait for:** FoundationModelsExtras tasks 01M3QMD8KBM42ZRNF447E06VVC ("PooledEmbedder from a Hugging Face name") and 01M3QMD98E12JEEZGKAVZB8CXN ("PooledModel and PooledSession for an LLM by Hugging Face name") on the Extras board: done and pushed.

## What
Each consumer gets the conformances without code of its own.

```swift
let qwen = PooledModel("mlx-community/Qwen3-4B-4bit")
SelectionConfig(model: { try await qwen.session(instructions: $0) })          // PooledSession: AgentSession
let e: any TextEmbedding = PooledEmbedder("mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ")
```

- `Package.swift`: depend on the core `FoundationModelsExtras` product (`git@github.com:swissarmyhammer/FoundationModelsExtras.git`, branch `main`).
- New `Sources/FoundationModelsRanker/Selection/PooledSessionSupport.swift`: `extension PooledSession: AgentSession` — forward `respond(to:)` and `fork()` (the two requirements of `AgentSession`).
- New `Sources/FoundationModelsRanker/PooledEmbedderSupport.swift`: `extension PooledEmbedder: TextEmbedding` — forward `embed(_:)`.
- `.github/workflows/ci.yml` (and its workflow test, if one exists): the build now compiles MLX through Extras; give the shared workflow the metallib input if a test loads a real model.
- `swift package update`, confirm the new Extras revision; push to `origin main` when green.

## Acceptance Criteria
- [ ] `PooledSession` is an `AgentSession` and `PooledEmbedder` is a `TextEmbedding` with no consumer code.
- [ ] The cached-root path forks the pooled session (it does not send the prefix again).
- [ ] CI is green on the pushed commit.

## Tests
- [ ] `Tests/FoundationModelsRankerTests/PooledConformanceTests.swift`: with `ModelPool(loader:)` and a stub `LanguageModel`, a `SelectionTier` over a `PooledModel` factory selects ids, and a fork is used for each query; a `HybridRanker` with a `PooledEmbedder` on a test loader reports cosine.
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #model-pool