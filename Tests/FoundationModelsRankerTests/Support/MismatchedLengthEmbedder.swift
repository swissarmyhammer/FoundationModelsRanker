import Foundation
import FoundationModelsRanker

/// A `TextEmbedding` test double that gives a batch of texts vectors of one
/// length, and a single text a vector of a different length.
///
/// `Searcher` embeds all its items in one batched call at `init`, and
/// `StreamingSearchCorpus` embeds the items of one `add(items:)` call in one
/// batched call. Both embed each query as a single text. Thus this double
/// makes the query vector and the item vectors differ in length, when more
/// than one item is embedded in each batch. The protocol declares no
/// vector length, so the length that `embed(_:)` returns is the only length
/// a caller can see. This double lets a test show what the cosine signal
/// does when those lengths do not agree.
struct MismatchedLengthEmbedder: TextEmbedding {
    /// Embeds each call of more than one text.
    private let batchEmbedder: FakeEmbedder

    /// Embeds each call of one text.
    private let singleTextEmbedder: FakeEmbedder

    /// Creates an embedder whose batched vectors and single-text vectors
    /// have different lengths.
    ///
    /// - Parameters:
    ///   - batchVectorLength: the length of each vector in a call of more
    ///     than one text.
    ///   - singleTextVectorLength: the length of the vector in a call of one
    ///     text.
    init(batchVectorLength: Int, singleTextVectorLength: Int) {
        batchEmbedder = FakeEmbedder(vectorLength: batchVectorLength)
        singleTextEmbedder = FakeEmbedder(vectorLength: singleTextVectorLength)
    }

    /// Embeds `texts` with `singleTextEmbedder` when `texts` holds one text,
    /// and with `batchEmbedder` in all other cases.
    func embed(_ texts: [String]) async throws -> [[Float]] {
        let embedder = texts.count == 1 ? singleTextEmbedder : batchEmbedder
        return try await embedder.embed(texts)
    }
}
