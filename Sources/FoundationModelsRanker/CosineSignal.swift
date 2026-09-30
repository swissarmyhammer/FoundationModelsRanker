/// The query side of the cosine signal that `Searcher` and
/// `StreamingSearchCorpus` fuse into a search.
///
/// Both types embed the query, score it against the stored item vectors,
/// and report `.embeddingUnavailable` when they cannot. This namespace holds
/// that one sequence, so the two types cannot drift apart.
enum CosineSignal {
    /// Embeds `query` and scores it against each vector in `itemEmbeddings`.
    ///
    /// Gives `nil` (keyword-only for this search) and reports
    /// `.embeddingUnavailable` one time through `onDiagnostic` in each of
    /// these cases:
    ///
    /// - `embedder` is `nil`.
    /// - `itemEmbeddings` is `nil`.
    /// - The query embed throws, or gives no vector.
    /// - The query vector length is different from the length of an item
    ///   vector.
    ///
    /// The `embedder` and `itemEmbeddings` checks run before the query embed,
    /// so a search that cannot use the cosine signal does not embed `query`.
    ///
    /// - Parameters:
    ///   - query: the query to embed and score.
    ///   - embedder: embeds `query`, or `nil` when no embedder is configured.
    ///   - itemEmbeddings: one vector for each item, in item order, or `nil`
    ///     when one or more items have no vector.
    ///   - onDiagnostic: receives `.embeddingUnavailable` when the cosine
    ///     signal cannot contribute.
    /// - Returns: one cosine score for each vector in `itemEmbeddings`, in
    ///   the same order, or `nil` to skip the cosine signal for this search.
    static func scores(
        forQuery query: String,
        embedder: (any TextEmbedding)?,
        itemEmbeddings: [[Float]]?,
        onDiagnostic: @Sendable (RankDiagnostic) -> Void
    ) async -> [Double]? {
        guard
            let embedder,
            let itemEmbeddings,
            let queryVector = try? await embedder.embed([query]).first,
            let scores = CosineScoring.similarities(of: queryVector, to: itemEmbeddings)
        else {
            onDiagnostic(.embeddingUnavailable)
            return nil
        }
        return scores
    }
}
