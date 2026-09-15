# FoundationModelsRanker

[![CI](https://github.com/swissarmyhammer/FoundationModelsRanker/actions/workflows/ci.yml/badge.svg)](https://github.com/swissarmyhammer/FoundationModelsRanker/actions/workflows/ci.yml)

Hybrid search and ranking for Swift: give it a list of items and a query, and
get back ranked results.

The ranker fuses BM25 keyword matching, trigram fuzzy matching, and optional
cosine similarity with reciprocal rank fusion. An agent on the on-device
system model can then pick the final result. You supply the model and the
embedder, and the package has no package dependency.

```swift
import FoundationModelsRanker

// The things to search: an id and the text that describes it.
let items = [
    SearchItem(id: "grep",  text: "Search file contents with regular expressions"),
    SearchItem(id: "glob",  text: "Find files by name pattern, sorted by mtime"),
    SearchItem(id: "watch", text: "Watch a directory and stream change events"),
    // ...hundreds more...
]

// Zero config: an agent on the on-device system model picks the result.
let searcher = try await Searcher(items)
let hits = try await searcher.search("how do I find TODO comments in my code")
// hits[0].id == "grep"
```

Any `LanguageModelSession` can be the `session:`, and any `TextEmbedding`
conformer can be the `embedder:`. The [guide](docs/GUIDE.md) shows both.

## Install

Add the package to `Package.swift`:

```swift
.package(url: "https://github.com/swissarmyhammer/FoundationModelsRanker", branch: "main")
```

## Documentation

- [Guide](docs/GUIDE.md): sessions, your own embedder, guided output, modes,
  and graceful degradation.
- [`Examples/FullMonty`](Examples/FullMonty): a runnable demo.
  `swift run FullMonty --no-model` needs no model, no GPU, and no network.
- [Contributing](CONTRIBUTING.md): the two test suites and how to run them.

## License

No license file is included in this repository.
