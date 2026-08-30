# FoundationModelsRanker

[![CI](https://github.com/swissarmyhammer/FoundationModelsRanker/actions/workflows/ci.yml/badge.svg)](https://github.com/swissarmyhammer/FoundationModelsRanker/actions/workflows/ci.yml)

Hybrid search and ranking for Swift: give it a list of things and a query,
get back ranked results. Under the hood it fuses BM25 keyword matching,
trigram fuzzy matching, and (optionally) cosine similarity by reciprocal
rank fusion, then optionally lets an agent make the final pick from the top
candidates. Targets macOS 27+ and has no external dependency: the package
builds against the macOS SDK alone.

```swift
import FoundationModelsRanker

// The things to search: an id and the text that describes it.
let items = [
    SearchItem(id: "grep",  text: "Search file contents with regular expressions"),
    SearchItem(id: "glob",  text: "Find files by name pattern, sorted by mtime"),
    SearchItem(id: "watch", text: "Watch a directory and stream change events"),
    // ...hundreds more...
]

// Zero config: BM25 + trigram retrieval fused by RRF narrows the field,
// then an agent picks the final result on the on-device system model.
let searcher = try await Searcher(items)
let hits = try await searcher.search("how do I find TODO comments in my code")
// hits[0].id == "grep" -- the agent's pick, carrying the real fused
// .score and per-signal .signals retrieval reports for the query
```

Any `LanguageModelSession` works — the model is never hardcoded. If you
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
factory is also what the zero-config call above does
(`Searcher.defaultSessionFactory`):

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

`myBackend` is your own embedding service: a local model, or a network
call.
[`Examples/FullMontyCore/DemoEmbedder.swift`](Examples/FullMontyCore/DemoEmbedder.swift)
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

`mode:` picks which tier `search(_:limit:)` answers through — defaults to
`.auto`:

- `.retrieval` — the fused BM25 + trigram (+ cosine) ranking only; no
  session is ever consulted. Results carry the real fused `score` and
  per-signal `.signals`.
- `.selection` — an agent picks from the top candidates; throws if no
  `session:` is configured. Picks carry the real fused `score` and
  per-signal `.signals` retrieval reports for the query: when the item
  list fits the selection budget the whole catalog stays selectable and is
  ranked once per search to attach those scores (one query-embedding call
  when an `embedder:` is configured); once it doesn't fit, the one-off
  fallback seeds itself from the top retrieval candidates.
- `.auto` — selection when a session is configured, retrieval otherwise
  (the lead example's zero-config call resolves here).

## Graceful degradation

Every fallback is reported, never silent: no `embedder` (or a failed query
embed) drops to keyword-only retrieval and reports `.embeddingUnavailable`
via `onDiagnostic`; `mode: .selection` with no session throws
`SelectionTierUnavailable`; `mode: .auto` degrades to retrieval instead of
failing.

## Install

Add the package to `Package.swift`:

```swift
.package(url: "https://github.com/swissarmyhammer/FoundationModelsRanker", branch: "main")
```

## Development

- **`swift run FullMonty` has three paths.** With no argument it runs the agent selection
  tier on the on-device system model, so it needs a Mac with Apple Intelligence turned on.
  `swift run FullMonty --no-model` prints keyword-only retrieval results. `swift run FullMonty
  --embedder` adds the cosine signal from a demonstration embedder. The last two paths need no
  model, no GPU, and no network. See [`Examples/FullMonty`](Examples/FullMonty).
- **There are two test suites, and a package boundary separates them.** `swift test` runs the
  unit suite. Every test in it drives a double, so it needs no model, no GPU, and no network.
  `swift test --package-path IntegrationTests` runs the real-model suite in the nested
  [`IntegrationTests`](IntegrationTests) package. Those tests drive a real `SystemLanguageModel`,
  so run them on a Mac with Apple Intelligence turned on.
- **The selection is structural, and no environment variable changes it.** The root
  `Package.swift` declares one test target, and it is the unit suite, so a root `swift test`
  cannot reach a model. The real-model target exists only in the nested package.

## License

No license file is included in this repository.
