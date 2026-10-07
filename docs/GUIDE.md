# FoundationModelsRanker guide

The [README](../README.md) shows the zero-config call. This guide shows the
arguments that change it.

## Models

`model:` takes any FoundationModels `LanguageModel`. The default is
`SystemLanguageModel.default`, the on-device system model. The code never
hardcodes another model. For each prompt, the selection tier makes a new
`LanguageModelSession` on the model, with the candidate list as its
instructions, and gets the ids through the native guided generation of the
session. No prompt sees the turns of another prompt.

A `PooledModel` of FoundationModelsExtras is a `LanguageModel`. It loads its
MLX model at the first prompt, and runs the prompts of all its users one at a
time:

```swift
import FoundationModelsExtras

let searcher = try await Searcher(items, model: PooledModel(ref: "mlx-community/Qwen3-4B-4bit"))
```

An error from the model comes out of `search`. Give `model: nil` to turn
selection off.

## Embedders

`embedder:` takes any `PooledEmbedding` of FoundationModelsExtras. That
protocol is `embed(texts:)`, and nothing else. Each vector carries its own
length, so an embedder does not declare one. With an embedder, cosine
similarity joins the fused ranking. A `PooledEmbedder` is a
`PooledEmbedding`. It loads its MLX model at the first call:

```swift
import FoundationModelsExtras

let searcher = try await Searcher(
    items,
    embedder: PooledEmbedder(ref: "mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ")
)
```

The runnable example in [`Examples/FullMonty`](../Examples/FullMonty) gives a
`PooledEmbedder` as `embedder:` and a `PooledModel` as `model:`.

## Modes

`mode:` selects the tier that `search(_:limit:)` uses. The default is
`.auto`.

- `.retrieval`: the fused BM25 + trigram (+ cosine) ranking only. No model
  is used. Results carry the real fused `score` and the per-signal
  `.signals`.
- `.selection`: one prompt asks the agent to pick from the whole item list.
  It throws if `model:` is `nil`. No retrieval runs: the picks come back in
  the agent's order, each with an order `score` (the first pick `1.0`, the
  n-th `1 / n`) and no `.signals`. When the item list does not fit the
  selection budget, the tier splits it into several prompts, and each item
  goes into exactly one of them. The answers are merged in prompt order.
- `.auto`: selection when a model is set, retrieval when `model:` is `nil`.
  The zero-config call in the README uses selection.

## Graceful degradation

Every fallback is reported. No fallback is silent:

- No `embedder`, or a query embed that fails, drops to keyword-only retrieval
  and reports `.embeddingUnavailable` through `onDiagnostic`.
- A query vector with a length different from the stored item vectors also
  drops that search to keyword-only retrieval and reports
  `.embeddingUnavailable`. This applies to `Searcher` and to
  `StreamingSearchCorpus`.
- `mode: .selection` with no model throws `SelectionTierUnavailable`.
- `mode: .auto` with no model uses retrieval and does not fail.
