// A neutral diagnostics channel with no default logger: consumers map
// `RankDiagnostic` into their own diagnostics or logging. This package
// does not log on their behalf.
//
// `Searcher` reports `.embeddingUnavailable` whenever it degrades the
// cosine signal to keyword-only.
//
// This package never emits `.retrievalCut`: the selection tier splits an
// over-budget catalog into several prompts and cuts nothing. The case
// stays so a consumer's exhaustive `switch` over this enum still compiles.

/// FoundationModelsRanker's neutral diagnostics channel: graceful-degradation events a
/// selection tier or the `Searcher` facade reports, never silently.
///
/// Consumers map these into their own diagnostics or logging surface --
/// FoundationModelsRanker itself never logs on a caller's behalf.
public enum RankDiagnostic: Sendable, Equatable {
    /// An over-budget capacity fallback cut the candidate set from
    /// `considered` items down to `kept` before a selection prompt.
    ///
    /// Never emitted by this package. `SelectionTier` does not cut
    /// candidates with retrieval; over budget it splits the catalog into
    /// several prompts, and every id reaches one of them. The
    /// case stays so a consumer that switches over every case still
    /// compiles.
    case retrievalCut(considered: Int, kept: Int)

    /// The selection model returned an id absent from the current
    /// candidate set. Guided generation limits the answer to the shape of
    /// `Selection`, not to the candidate ids, so the tier filters such an
    /// id and reports it here.
    case unknownSelectedId(id: String)

    /// No embedder is configured for the cosine signal (or embedding the
    /// query itself failed, or the query vector length is different from
    /// the length of an item vector), so retrieval degraded to keyword-only
    /// (BM25 + trigram) for this search.
    case embeddingUnavailable
}
