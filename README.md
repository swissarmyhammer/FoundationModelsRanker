# FoundationModelsRanker

[![CI](https://github.com/swissarmyhammer/FoundationModelsRanker/actions/workflows/ci.yml/badge.svg)](https://github.com/swissarmyhammer/FoundationModelsRanker/actions/workflows/ci.yml)

Hybrid search and ranking for Swift: give it a list of items and a query, and
get back ranked results.

The ranker fuses BM25 keyword matching, trigram fuzzy matching, and optional
cosine similarity with reciprocal rank fusion. An agent on the on-device
system model can then pick the final result. You can supply your own model
and embedder: any FoundationModels `LanguageModel` is a model, and any
`PooledEmbedding` of FoundationModelsExtras is an embedder.

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

The `model:` argument takes `SystemLanguageModel.default` (the default) or a
`PooledModel` of FoundationModelsExtras, for example
`PooledModel(ref: "mlx-community/Qwen3-4B-4bit")`. The `embedder:` argument
takes a `PooledEmbedder`, for example
`PooledEmbedder(ref: "mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ")`. The
[guide](docs/GUIDE.md) shows each.

## Install

Add the package to `Package.swift`:

```swift
.package(url: "https://github.com/swissarmyhammer/FoundationModelsRanker", branch: "main")
```

## Documentation

- [Guide](docs/GUIDE.md): models, embedders, modes, and graceful
  degradation.
- [`Examples/FullMonty`](Examples/FullMonty): a runnable demo.

## Run the example

The runnable example is in the separate [`Examples/`](Examples/) package.
`FullMonty` searches a catalog of ~50 developer command-line tools. For each
query, it writes the retrieval ranking with the value of each signal, and
then the selection of a language model. It uses two MLX models from the
Hugging Face hub. It embeds with
`mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ` (about 0.3 GB), and it selects
with `mlx-community/Qwen3-4B-4bit` (about 2.3 GB). The first run downloads
the models into the Hugging Face cache; a later run loads them from the
cache. Run it with:

```sh
swift run --package-path Examples FullMonty
```

Add `--no-model` to search with the keyword signals only. That path needs no
model, no GPU, and no network.

## Run the tests

A package boundary separates the two test suites:

- `swift test` runs the unit suite. Every test in it drives a double, so it
  needs no model, no GPU, and no network.
- `swift test --package-path IntegrationTests` runs the real-model suite in
  the nested [`IntegrationTests`](IntegrationTests) package. Those tests drive
  a real `SystemLanguageModel`, so run them on a Mac with Apple Intelligence
  turned on.

The package structure selects the suite, and no environment variable changes
it. The root `Package.swift` declares one test target, the unit suite, so a
root `swift test` cannot reach a model. The real-model target exists only in
the nested package.

## License

No license file is included in this repository.
