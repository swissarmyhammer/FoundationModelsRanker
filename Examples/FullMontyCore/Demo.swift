// `FullMonty`'s entry logic (plan.md §3a): runs `demoQueries` against
// `toolCatalog` through the `Searcher` facade and formats the results —
// factored into this library target (rather than living directly in
// `FullMonty`'s `main.swift`) so `ExamplesSmokeTests` can invoke every
// GPU-free path directly, with no `swift run` subprocess spawning, mirroring
// FoundationModelsMetadataRegistry's `CatalogSearchCore`/`SemanticSearchCore`
// pattern.
//
// New to FoundationModelsRanker — no source file to port (plan.md §3a).

import Foundation
import FoundationModelsRanker

// MARK: - The opt-in gate for the tests that need a live model

/// The name of the environment variable that enables the gated tests.
///
/// Some tests need a live Apple Intelligence model. Those tests run only when
/// this variable is set. This mirrors FoundationModelsMetadataRegistry's own
/// `METADATA_REGISTRY_INTEGRATION_TESTS` convention. Nothing sets the variable
/// by default, so a usual test run needs no model.
public let foundationModelsRankerIntegrationEnvVar = "FOUNDATIONMODELSRANKER_INTEGRATION_TESTS"

/// Whether the gated tests are enabled for this run.
public var isFoundationModelsRankerIntegrationEnabled: Bool {
    ProcessInfo.processInfo.environment[foundationModelsRankerIntegrationEnvVar] != nil
}

// MARK: - The demo paths

/// One `demoQueries` entry's result: the query itself alongside its ranked or selected matches.
public typealias FullMontyResult = (query: String, matches: [SelectionMatch])

/// Runs all demo queries against the catalog through a Searcher built from provided ingredients.
///
/// Runs every `demoQueries` entry against `toolCatalog` through a `Searcher`
/// built from the given ingredients — the shared plumbing all three of
/// `FullMonty`'s paths (`--no-model`, `--embedder`, and the default
/// on-device-system-model path) drive through. The three paths differ only
/// in the `embedder`, the `session`, and the `mode` they supply.
///
/// - Parameters:
///   - embedder: embeds `toolCatalog` and every query for the cosine signal,
///     or `nil` for keyword-only retrieval.
///   - session: creates a selection session, or `nil` to leave selection
///     unavailable (`mode` should then be `.retrieval`).
///   - mode: which tier `Searcher.search(_:limit:)` answers through.
///     Defaults to `.auto`.
///   - limit: the maximum number of matches per query. Defaults to `5`.
///   - onDiagnostic: called for every diagnostic `Searcher` emits.
/// - Returns: one `FullMontyResult` per `demoQueries` entry, in order.
/// - Throws: whatever `Searcher.init` or `Searcher.search(_:limit:)` throws.
public func runFullMontyDemo(
    embedder: (any TextEmbedding)?,
    session: (@Sendable (String) -> any AgentSession)?,
    mode: Searcher.Mode = .auto,
    limit: Int = 5,
    onDiagnostic: @escaping @Sendable (RankDiagnostic) -> Void = { _ in }
) async throws -> [FullMontyResult] {
    let searcher = try await Searcher(
        toolCatalog,
        embedder: embedder,
        session: session,
        mode: mode,
        onDiagnostic: onDiagnostic
    )
    var results: [FullMontyResult] = []
    results.reserveCapacity(demoQueries.count)
    for query in demoQueries {
        results.append((query: query, matches: try await searcher.search(query, limit: limit)))
    }
    return results
}

/// The one body that the two GPU-free retrieval paths share.
///
/// `--no-model` and `--embedder` both call
/// `runFullMontyDemo(embedder:session:mode:limit:onDiagnostic:)` with
/// `session: nil` and `mode: .retrieval`. Only the embedder is different.
/// This helper takes the embedder as a parameter and gives the other
/// arguments, so the two paths keep only one copy of that shape.
///
/// The default path does not use this helper. `runDefaultDemo` gives a
/// session and `mode: .auto`, so its shape is different. A helper with a
/// parameter for the session and a parameter for the mode would only be a
/// second name for `runFullMontyDemo`.
///
/// - Parameters:
///   - embedder: embeds `toolCatalog` and every query for the cosine signal,
///     or `nil` for keyword-only retrieval.
///   - onDiagnostic: called for every diagnostic `Searcher` emits.
/// - Returns: one `FullMontyResult` per `demoQueries` entry, in order.
/// - Throws: whatever `runFullMontyDemo(embedder:session:mode:limit:onDiagnostic:)`
///   throws.
private func runRetrievalDemo(
    embedder: (any TextEmbedding)?,
    onDiagnostic: @escaping @Sendable (RankDiagnostic) -> Void
) async throws -> [FullMontyResult] {
    try await runFullMontyDemo(
        embedder: embedder, session: nil, mode: .retrieval, onDiagnostic: onDiagnostic
    )
}

/// `--no-model`'s degraded, GPU-free path (plan.md §3a "the CI-safe path").
///
/// No embedder (keyword-only BM25 + trigram retrieval), no selection
/// session — `mode: .retrieval` so `Searcher.search(_:limit:)` never even
/// tries to consult a model.
///
/// - Parameter onDiagnostic: called for every diagnostic `Searcher` emits —
///   `.embeddingUnavailable` fires on every search this path runs, since no
///   embedder is configured.
/// - Returns: one `FullMontyResult` per `demoQueries` entry, in order.
/// - Throws: whatever `runFullMontyDemo(embedder:session:mode:limit:onDiagnostic:)`
///   throws.
public func runNoModelDemo(
    onDiagnostic: @escaping @Sendable (RankDiagnostic) -> Void = { _ in }
) async throws -> [FullMontyResult] {
    try await runRetrievalDemo(embedder: nil, onDiagnostic: onDiagnostic)
}

/// `--embedder`'s GPU-free path: retrieval with the cosine signal switched on.
///
/// The same keyword-only retrieval `--no-model` runs, plus a `DemoEmbedder`
/// — so BM25, trigram, and cosine all carry data, and `.embeddingUnavailable`
/// never fires. `mode: .retrieval` and `session: nil` keep the path free of
/// a model: cosine is a retrieval-tier signal, so the tier that shows it
/// needs no selection session at all, and the path stays GPU-free,
/// network-free, and fast enough for `ExamplesSmokeTests` to drive
/// directly.
///
/// - Parameter onDiagnostic: called for every diagnostic `Searcher` emits.
///   This path emits none: an embedder is configured, so the
///   `.embeddingUnavailable` degradation `--no-model` reports on every
///   query cannot happen here.
/// - Returns: one `FullMontyResult` per `demoQueries` entry, in order.
/// - Throws: whatever `runFullMontyDemo(embedder:session:mode:limit:onDiagnostic:)`
///   throws.
public func runEmbedderDemo(
    onDiagnostic: @escaping @Sendable (RankDiagnostic) -> Void = { _ in }
) async throws -> [FullMontyResult] {
    try await runRetrievalDemo(embedder: DemoEmbedder(), onDiagnostic: onDiagnostic)
}

/// The default path: keyword-only retrieval with real agent selection on the on-device system model.
///
/// Run with no flags: no embedder, so retrieval stays keyword-only. But
/// `session: Searcher.defaultSessionFactory` makes `mode: .auto` drive real
/// selection on the on-device system model.
///
/// Explicitly passes `Searcher.defaultSessionFactory` (rather than omitting
/// `session:` and letting `Searcher.init`'s own default argument supply it)
/// so this call site documents the exact swap point plan.md §3a's
/// `--model default` flag was meant to demonstrate — see this package's
/// `Searcher.swift` header for why: the installed SDK exposes only
/// `SystemLanguageModel.default`, not `.fast`, so `defaultSessionFactory`
/// already *is* `.default`; there is no longer a second value to swap to,
/// so `FullMonty` ships no `--model` flag.
///
/// - Parameter onDiagnostic: called for every diagnostic `Searcher` emits.
/// - Returns: one `FullMontyResult` per `demoQueries` entry, in order.
/// - Throws: whatever `runFullMontyDemo(embedder:session:mode:limit:onDiagnostic:)`
///   throws — in particular, whatever the on-device system model session
///   throws if Apple Intelligence is unavailable on this machine.
public func runDefaultDemo(
    onDiagnostic: @escaping @Sendable (RankDiagnostic) -> Void = { _ in }
) async throws -> [FullMontyResult] {
    try await runFullMontyDemo(embedder: nil, session: Searcher.defaultSessionFactory, mode: .auto, onDiagnostic: onDiagnostic)
}

// MARK: - Printing

/// Prints the tool catalog, one line per item.
///
/// Used by every path so a run always shows what's being searched.
public func printCatalog() {
    print("FullMonty catalog (\(toolCatalog.count) tools):")
    for item in toolCatalog {
        print("- \(item.id): \(item.text)")
    }
}

/// Formats matches into lines with rank, id, score, and signal breakdown.
///
/// Formats one query's matches, one line each, with their per-signal
/// breakdown when retrieval produced one — mirrors
/// FoundationModelsMetadataRegistry's `Examples/ExamplesSupport
/// .formattedMatches(matches:)`, adapted to FoundationModelsRanker's catalog-agnostic
/// `SelectionMatch` (no generic `Item`).
///
/// - Parameter matches: the matches to format, in ranked or selected order.
/// - Returns: one formatted line per match, joined by newlines, or a
///   placeholder line when `matches` is empty.
public func formattedMatches(_ matches: [SelectionMatch]) -> String {
    guard !matches.isEmpty else { return "(no matches)" }
    return matches.enumerated().map { index, match in
        let breakdown =
            match.signals.map {
                String(format: "bm25=%.3f trigram=%.3f cosine=%.3f", $0.bm25, $0.trigram, $0.cosine)
            } ?? "selection (no retrieval signals)"
        return String(format: "%d. %@  score=%.3f  [%@]", index + 1, match.id, match.score, breakdown)
    }.joined(separator: "\n")
}

/// Prints every `FullMontyResult`, one query block at a time.
///
/// - Parameter results: the results to print, in query order.
public func printResults(_ results: [FullMontyResult]) {
    for result in results {
        print("Query: \"\(result.query)\"")
        print(formattedMatches(result.matches))
        print("")
    }
}

/// Prints a single diagnostic emitted by Searcher or its selection tier.
///
/// FoundationModelsRanker itself never logs on a caller's behalf
/// (`RankDiagnostic.swift`'s header), so every `Examples/` target owns
/// printing its own.
///
/// - Parameter diagnostic: the diagnostic to print.
public func printDiagnostic(_ diagnostic: RankDiagnostic) {
    print("[diagnostic] \(diagnostic)")
}
