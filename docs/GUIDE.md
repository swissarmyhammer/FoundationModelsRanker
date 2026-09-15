# FoundationModelsRanker guide

The [README](../README.md) shows the zero-config call. This guide shows the
arguments that change it.

## Sessions

Any `LanguageModelSession` works. The code never hardcodes the model. If you
already hold a session, give that session:

```swift
import FoundationModels

let searcher = try await Searcher(
    items,
    session: LanguageModelSession(model: .default, instructions: "Pick the best tools.")
)
```

One live session shares one transcript with all the calls.
`LanguageModelSession.fork()` gives back `self`, because the SDK has no
branch primitive, so each call adds turns to the same session. Give a
session factory instead when each call must get a fresh context. The
zero-config call uses a factory too (`Searcher.defaultSessionFactory`):

```swift
import FoundationModels

let searcher = try await Searcher(items, session: { instructions in
    LanguageModelSession(model: .default, instructions: instructions)
})
```

## Bring your own embedder

`TextEmbedding` is `dimension` and `embed(_:)`. Nothing else. Write a
conformer around your own embedding backend and give it to `Searcher` as
`embedder:`. Cosine similarity then joins the fused ranking. This package
ships no embedder of its own, and every embedding backend connects the same
way:

```swift
import FoundationModelsRanker

struct MyEmbedder: TextEmbedding {
    /// The length of every vector `myBackend` makes.
    let dimension = 768

    /// Gives the texts to your own embedding backend.
    func embed(_ texts: [String]) async throws -> [[Float]] {
        try await myBackend.embed(texts)
    }
}

let searcher = try await Searcher(items, embedder: MyEmbedder())
```

`myBackend` is your own embedding service: a local model, or a network call.
[`Examples/FullMontyCore/DemoEmbedder.swift`](../Examples/FullMontyCore/DemoEmbedder.swift)
holds a runnable conformer that needs no model, no GPU, and no network.

## Guided output

`SelectionTier.idEnumSchema(ids:)` gives back a JSON Schema source string.
The schema limits the answer to the ids you give it, so the model cannot
invent an id. If your model backend accepts a JSON Schema grammar, give the
string to that backend:

```swift
import FoundationModelsRanker

let schema = try SelectionTier.idEnumSchema(ids: items.map(\.id))
```

## Modes

`mode:` selects the tier that `search(_:limit:)` uses. The default is
`.auto`.

- `.retrieval`: the fused BM25 + trigram (+ cosine) ranking only. No session
  is used. Results carry the real fused `score` and the per-signal
  `.signals`.
- `.selection`: one prompt asks the agent to pick from the whole item list.
  It throws if no `session:` is set. No retrieval runs: the picks come back
  in the agent's order, each with an order `score` (the first pick `1.0`,
  the n-th `1 / n`) and no `.signals`. When the item list does not fit the
  selection budget, the tier splits it into several prompts, and each item
  goes into exactly one of them. The answers are merged in prompt order.
- `.auto`: selection when a session is set, retrieval when no session is set.
  The zero-config call in the README uses selection.

## Graceful degradation

Every fallback is reported. No fallback is silent:

- No `embedder`, or a query embed that fails, drops to keyword-only retrieval
  and reports `.embeddingUnavailable` through `onDiagnostic`.
- `mode: .selection` with no session throws `SelectionTierUnavailable`.
- `mode: .auto` with no session uses retrieval and does not fail.
