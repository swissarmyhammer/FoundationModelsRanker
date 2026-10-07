import FoundationModelsExtras
import FoundationModelsRanker

// # FullMonty: every tier of the `Searcher` facade over one catalog.
//
// The catalog has ~50 developer command-line tools. For each demo query, the
// example writes two answers:
//
// - The retrieval ranking. BM25, trigram, and cosine similarity are fused
//   by RRF, and each match shows the value of each signal.
// - The selection. A language model reads the candidate prefix and gives
//   the ids that the query needs. The searcher maps each id back to
//   its catalog item, so each result is catalog text, not generated text.
//   When the model gives an id that is not in the catalog, the searcher
//   drops that id and reports `.unknownSelectedId`.
//
// The embedder is `exampleEmbedder`, a `PooledEmbedder` for Qwen3 Embedding
// 0.6B, 4-bit. The selection model is `exampleSelectionModel`, a
// `PooledModel` for Qwen3 4B, 4-bit. Both come from the Hugging Face hub
// through `ModelPool.shared`, and neither loads when you make it. The first
// run downloads the weights (about 0.3 GB and about 2.3 GB) into the Hugging
// Face cache; a later run loads them from the cache. The selection can
// change from one run to the next.
//
// Run with `--no-model` to search with no model at all. Then the searcher
// uses the keyword signals only, it reports `.embeddingUnavailable` for each
// query, and the example writes no selection. This path needs no GPU and no
// network.
//
// Run with `swift run --package-path Examples FullMonty` or
// `swift run --package-path Examples FullMonty --no-model`.

/// The maximum number of matches for each query.
let matchLimit = 5

let noModel = CommandLine.arguments.contains("--no-model")

/// Writes each diagnostic of the two searchers to the report.
let writeDiagnostic: @Sendable (RankDiagnostic) -> Void = { diagnostic in
    Report.write("[diagnostic] \(diagnostic)")
}

/// The shared embedding model, or `nil` for `--no-model`.
let embedder: PooledEmbedder? = noModel ? nil : exampleEmbedder

/// The retrieval searcher: no model, so it only ranks.
let retrieval = try await Searcher(
    toolCatalog,
    embedder: embedder,
    model: nil,
    mode: .retrieval,
    onDiagnostic: writeDiagnostic
)

/// The selection searcher, or `nil` for `--no-model`. Each candidate prefix
/// becomes the instructions of a new session on the selection model.
let selection: Searcher? =
    noModel
    ? nil
    : try await Searcher(
        toolCatalog,
        embedder: embedder,
        model: exampleSelectionModel,
        mode: .selection,
        onDiagnostic: writeDiagnostic
    )

Report.write("FullMonty catalog: \(toolCatalog.count) tools\(noModel ? " (--no-model)" : "")\n")
for query in demoQueries {
    Report.write("Query: \"\(query)\"")
    Report.write("Retrieval:")
    Report.write(formattedMatches(try await retrieval.search(query, limit: matchLimit)))
    if let selection {
        Report.write("Selection:")
        Report.write(formattedMatches(try await selection.search(query, limit: matchLimit)))
    }
    Report.write("")
}
