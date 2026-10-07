// The package's one-call facade. It composes `HybridRanker` (retrieval:
// BM25 + trigram + optional cosine, fused by RRF) with `SelectionTier`
// (agent final selection) over an in-memory `SelectionCatalog` built from
// the caller's `Searchable` items. `Searcher` is a plain value type: its
// catalog is fixed for its lifetime, and it has no hot reload.
//
// The default model is `SystemLanguageModel.default`, the on-device system
// model. The macOS 27 SDK has no `.fast` variant of that model, so the
// default does not name one.

import FoundationModels
import FoundationModelsExtras

/// The package's front door: "a list of things to search, then
/// a query" is the whole API.
///
/// Composes `HybridRanker` (BM25 + trigram + optional cosine, fused by RRF)
/// with `SelectionTier` (agent final selection) over an in-memory catalog
/// built once from `items` at `init`.
///
/// Every knob but `items` is optional: `embedder:` adds the cosine signal
/// (every item's `text` is embedded once, here, at `init`); `model:` swaps
/// the selection model -- defaults to the on-device system model, and is
/// never hardcoded beyond that default; `weights:` and `preamble:` tune
/// the retrieval and selection tiers directly; `mode:` picks which tier
/// answers `search(_:limit:)`.
///
/// `model:` takes any FoundationModels `LanguageModel`, for example
/// `SystemLanguageModel.default` or a `PooledModel` of
/// FoundationModelsExtras. `embedder:` takes any `PooledEmbedding` of
/// FoundationModelsExtras, for example a `PooledEmbedder`.
///
/// Degradation is graceful, never silent: no `embedder` (or
/// a query embed that itself fails, or a query vector whose length is
/// different from the item vectors) drops straight to keyword-only
/// retrieval with `.embeddingUnavailable` reported via `onDiagnostic` on
/// every such search. A `weights.cosine` of `0.0` is different -- a
/// caller's deliberate opt-out of the signal, not a degradation -- so it
/// skips cosine (and its embed call) without reporting anything: a zero
/// weight means the caller does not want the signal. `mode: .selection` with
/// no model configured (`model: nil`) throws
/// `SelectionTierUnavailable` rather than silently retrieving instead;
/// `mode: .auto` (the default) silently prefers selection when a model is
/// configured, retrieval otherwise.
public struct Searcher: Sendable {
    /// Which tier `search(_:limit:)` answers a query with.
    public enum Mode: Sendable {
        /// `HybridRanker`'s fused BM25 + trigram + (optional cosine)
        /// ranking only -- no model, no tokens.
        case retrieval

        /// The agent selects among candidates (`SelectionTier`).
        ///
        /// Throws `SelectionTierUnavailable` when no model is configured
        /// (`model: nil`).
        case selection

        /// Selection when a model is configured, retrieval otherwise --
        /// the default.
        case auto
    }

    /// This facade's precomputed retrieval state and the knobs
    /// `search(_:limit:)`'s retrieval answer drives `HybridRanker` through.
    /// The selection tier never reads it: a selection runs no retrieval.
    private let engine: RetrievalEngine

    /// Which tier `search(_:limit:)` uses.
    private let mode: Mode

    /// This facade's selection tier, or `nil` when `model: nil` left
    /// selection unavailable.
    private let selectionTier: SelectionTier?

    /// Builds a searcher over `items`.
    ///
    /// - Parameters:
    ///   - items: the things to search: at minimum an id and the text that
    ///     describes it (`SearchItem`, or any `Searchable` conformer).
    ///     Duplicate ids keep the first occurrence; later ones are dropped.
    ///   - embedder: embeds every item's `text` once, here, at `init`, and
    ///     the query at every `search(_:limit:)` call -- adds the cosine
    ///     signal to retrieval. `nil` (the default) skips cosine entirely
    ///     and reports `.embeddingUnavailable` on every search that would
    ///     otherwise have used it (whenever `weights.cosine > 0.0`; a
    ///     caller who sets `weights.cosine` to `0.0` has already opted out
    ///     of the signal, so that combination reports nothing).
    ///   - model: the model that answers each selection prompt. The
    ///     selection tier makes a new `LanguageModelSession` on it for each
    ///     prompt. Defaults to `SystemLanguageModel.default`; pass `nil`
    ///     explicitly to leave selection unavailable (`mode: .selection`
    ///     then throws `SelectionTierUnavailable`; `.auto` degrades to
    ///     retrieval).
    ///   - weights: the per-signal fusion weights for retrieval. Defaults
    ///     to `1.0` for every signal.
    ///   - preamble: the selection guidance prepended to the assembled
    ///     prefix. Defaults to `.selectionDefault`.
    ///   - mode: which tier `search(_:limit:)` uses. Defaults to `.auto`.
    ///   - onDiagnostic: called for every diagnostic this facade or its
    ///     selection tier emits. Defaults to doing nothing.
    /// - Throws: whatever `embedder.embed(texts:)` throws while embedding
    ///   `items` at `init`.
    public init<Item: Searchable>(
        _ items: [Item],
        embedder: (any PooledEmbedding)? = nil,
        model: (any LanguageModel)? = SystemLanguageModel.default,
        weights: SignalWeights = SignalWeights(),
        preamble: String = .selectionDefault,
        mode: Mode = .auto,
        onDiagnostic: @escaping @Sendable (RankDiagnostic) -> Void = { _ in }
    ) async throws {
        let corpus = SearchCorpus(items: items)
        let itemEmbeddings: [[Float]]?
        if let embedder {
            itemEmbeddings = try await embedder.embed(texts: corpus.ids.map { corpus.block(forID: $0) ?? "" })
        } else {
            itemEmbeddings = nil
        }

        self.engine = RetrievalEngine(
            corpus: corpus,
            itemEmbeddings: itemEmbeddings,
            embedder: embedder,
            weights: weights,
            onDiagnostic: onDiagnostic
        )
        self.mode = mode
        self.selectionTier = model.map { model in
            SelectionTier(
                catalog: corpus,
                config: SelectionConfig(model: model, preamble: preamble),
                onDiagnostic: onDiagnostic
            )
        }
    }

    /// Searches this facade's catalog for `query`, answering through
    /// whichever tier `mode` selects.
    ///
    /// A selection-tier search asks the model and ranks nothing: it embeds
    /// no query, reads no retrieval signal, and reports no
    /// `.embeddingUnavailable`. Only a retrieval search runs `HybridRanker`.
    ///
    /// - Parameters:
    ///   - query: the search query.
    ///   - limit: the maximum number of results to return. Defaults to
    ///     `20`. `limit <= 0` yields an empty result rather than throwing
    ///     or crashing.
    /// - Returns: `.retrieval`'s fused, `[0, 1]`-normalized matches, each
    ///   carrying real per-signal `signals`; `.selection`'s verbatim
    ///   matches in the model's order, each scored by its position
    ///   (`1 / rank`) with no `signals`; `.auto`'s resolution of whichever
    ///   of those applies.
    /// - Throws: `SelectionTierUnavailable` when `mode == .selection` and no
    ///   model is configured (`model: nil`); otherwise whatever the
    ///   selection session of the model throws.
    public func search(_ query: String, limit: Int = 20) async throws -> [SelectionMatch] {
        switch mode {
        case .retrieval:
            return await engine.topMatches(query: query, limit: limit)
        case .selection:
            guard let selectionTier else { throw SelectionTierUnavailable() }
            return try await selectionTier.search(intent: query, limit: limit)
        case .auto:
            if let selectionTier {
                return try await selectionTier.search(intent: query, limit: limit)
            }
            return await engine.topMatches(query: query, limit: limit)
        }
    }
}

/// Thrown by `Searcher.search(_:limit:)` when `mode == .selection` and no
/// model is configured (`Searcher.init(..., model: nil, ...)`) --
/// requesting `.selection` explicitly without one fails loudly rather than
/// silently substituting retrieval.
public struct SelectionTierUnavailable: Error, Sendable, Equatable {
    /// Creates an error indicating that no selection model is configured.
    public init() {}
}

/// Bundles `Searcher`'s precomputed retrieval state (the corpus and its item
/// embeddings) and knobs (`embedder`, `weights`, `onDiagnostic`) behind the
/// one `HybridRanker` call `search(_:limit:)`'s retrieval answer makes.
private struct RetrievalEngine: Sendable {
    /// The corpus this engine ranks: its `ids`/`documents` are
    /// `HybridRanker`'s arguments, and its `block(forID:)` resolves every hit
    /// to a verbatim `SelectionMatch`.
    ///
    /// Fixed for this engine's lifetime -- `Searcher` builds it once at
    /// `init` and never mutates it, which is what keeps `itemEmbeddings`
    /// positionally aligned with `corpus.ids`.
    let corpus: SearchCorpus

    /// One embedding per `corpus.ids` entry, positionally aligned with
    /// `corpus.documents` -- `nil` when no `embedder` was configured.
    let itemEmbeddings: [[Float]]?

    /// Embeds the *query* at search time for the cosine signal. `nil` means
    /// no cosine signal, ever, regardless of `weights.cosine`.
    let embedder: (any PooledEmbedding)?

    /// The per-signal fusion weights `HybridRanker` uses.
    let weights: SignalWeights

    /// Called for every diagnostic this engine emits (currently only
    /// `.embeddingUnavailable`).
    let onDiagnostic: @Sendable (RankDiagnostic) -> Void

    /// Embeds `query` and scores it against every precomputed item
    /// embedding -- the cosine signal `HybridRanker` fuses in when
    /// non-`nil`.
    ///
    /// `weights.cosine <= 0.0` short-circuits to `nil` with **no**
    /// diagnostic: a caller who zeroed the weight has already opted out of
    /// the signal, not hit a degradation, so there's nothing to embed or
    /// warn about. Otherwise, degrades to `nil`
    /// (keyword-only) and *does* report `.embeddingUnavailable` whenever
    /// cosine was actually wanted but couldn't contribute: no
    /// `embedder`/`itemEmbeddings` available, embedding the query
    /// itself fails, or the query vector length is different from the
    /// length of an item vector. `CosineSignal.scores` does the embed, the
    /// checks, and the report, the same as for `StreamingSearchCorpus`.
    ///
    /// - Parameter query: the query to embed and score.
    /// - Returns: one cosine score per `corpus.documents` entry, positionally
    ///   aligned, or `nil` to skip the cosine signal for this search.
    func cosineScores(forQuery query: String) async -> [Double]? {
        guard weights.cosine > 0.0 else { return nil }
        return await CosineSignal.scores(
            forQuery: query, embedder: embedder, itemEmbeddings: itemEmbeddings, onDiagnostic: onDiagnostic
        )
    }

    /// `.retrieval` mode's answer: short-circuits an empty corpus, resolves
    /// the cosine signal once, ranks with `HybridRanker.topMatches(...)`, and
    /// maps the hits back through `corpus` to verbatim `SelectionMatch`es.
    ///
    /// - Parameters:
    ///   - query: the search query.
    ///   - limit: the maximum number of matches to return.
    /// - Returns: the fused, `[0, 1]`-normalized matches, best-first.
    func topMatches(query: String, limit: Int) async -> [SelectionMatch] {
        guard limit > 0, !corpus.isEmpty else { return [] }
        let hits = HybridRanker.topMatches(
            ids: corpus.ids,
            documents: corpus.documents,
            query: query,
            cosineScores: await cosineScores(forQuery: query),
            weights: weights,
            limit: limit
        )
        return hits.map { hit in
            SelectionMatch(id: hit.id, block: corpus.block(forID: hit.id) ?? "", score: hit.score, signals: hit.signals)
        }
    }
}
