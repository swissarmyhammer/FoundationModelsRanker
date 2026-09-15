// New to FoundationModelsRanker -- generalizes
// FoundationModelsMetadataRegistry's own
// `Sources/FoundationModelsMetadataRegistry/Catalog/Match.swift`
// (`Match<Item>`) by dropping the generic catalog item: a `SelectionTier`
// only ever needs a matched id, its verbatim catalog block, and the score/
// signals that produced the match -- never the catalog's own item type,
// which FoundationModelsRanker's narrow `SelectionCatalog` protocol never exposes.
// Consumers wrap `SelectionMatch` into their own richer result types when
// they need the original item back.

/// One retrieval or selection result over a `SelectionCatalog`:
/// the catalog's own id and verbatim block, plus a score in `[0, 1]` and,
/// for a retrieval result, the raw per-signal scores that produced it.
public struct SelectionMatch: Sendable, Equatable {
    /// The matched id.
    public let id: String

    /// The matched id's block, **verbatim from the catalog** --
    /// `SelectionCatalog.block(forID:)`'s output, never re-derived and never
    /// model output. The code, not the prompt, keeps the block verbatim.
    public let block: String

    /// A score in `[0, 1]`, whose meaning follows the tier that made the
    /// match. A retrieval match carries the fused retrieval score, `0.0`
    /// for an id every signal missed (the zero-scored tail of a
    /// full-catalog ordering). A selection match carries the model's order
    /// as a reciprocal rank: the first pick scores `1.0`, the n-th pick
    /// `1 / n`. No retrieval signal enters a selection.
    public let score: Double

    /// The raw per-signal scores that produced `score`, or `nil` when no
    /// per-signal breakdown accompanies the match. A selection match always
    /// carries `nil`: the selection tier ranks nothing.
    public let signals: Signals?

    /// Creates one retrieval or selection result.
    ///
    /// - Parameters:
    ///   - id: the matched id.
    ///   - block: the matched id's block, verbatim from the catalog.
    ///   - score: the fused score, in `[0, 1]`.
    ///   - signals: the raw per-signal scores, or `nil` when no per-signal
    ///     breakdown accompanies the match.
    public init(id: String, block: String, score: Double, signals: Signals?) {
        self.id = id
        self.block = block
        self.score = score
        self.signals = signals
    }
}
