// New to FoundationModelsRanker -- generalizes the two selection-tier
// cases of FoundationModelsMetadataRegistry's own
// `Sources/FoundationModelsMetadataRegistry/Catalog/Diagnostics.swift`
// (`MetadataDiagnostic`) into a neutral channel with no default logger:
// unlike `MetadataDiagnostic.log(_:)`, consumers map `RankDiagnostic` into
// their own diagnostics or logging rather than FoundationModelsRanker logging on their
// behalf.
//
// `.embeddingUnavailable` is added by the `Searcher` facade task: the
// retrieval-tier counterpart to `MetadataDiagnostic
// .embeddingUnavailable`, reported whenever `Searcher` degrades the cosine
// signal to keyword-only.
//
// `.retrievalCut` is kept and never emitted since task ^kqp9e5e: the
// selection tier splits an over-budget catalog into several prompts and cuts
// nothing. The case stays so a consumer's exhaustive `switch` over this enum
// (`FoundationModelsMetadataRegistry`'s `MetadataDiagnostic`) still compiles.

/// FoundationModelsRanker's neutral diagnostics channel: graceful-degradation events a
/// selection tier or the `Searcher` facade reports, never silently.
///
/// Consumers map these into their own diagnostics or logging surface --
/// FoundationModelsRanker itself never logs on a caller's behalf.
public enum RankDiagnostic: Sendable, Equatable {
    /// An over-budget capacity fallback cut the candidate set from
    /// `considered` items down to `kept` before seeding a one-off
    /// selection session.
    ///
    /// Never emitted by this package. `SelectionTier` stopped cutting
    /// candidates with retrieval in task ^kqp9e5e; over budget it splits the
    /// catalog into several prompts, and every id reaches one of them. The
    /// case stays so a consumer that switches over every case still
    /// compiles.
    case retrievalCut(considered: Int, kept: Int)

    /// The selection model returned an id absent from the current
    /// candidate set. Structurally unreachable given grammar-constrained
    /// output, but defended against anyway.
    case unknownSelectedId(id: String)

    /// No embedder is configured for the cosine signal (or embedding the
    /// query itself failed), so retrieval degraded to keyword-only (BM25 +
    /// trigram) for this search.
    case embeddingUnavailable
}
