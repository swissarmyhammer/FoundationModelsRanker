import FoundationModelsExtras
import FoundationModelsRanker
import Testing

/// Proves that a `PooledEmbedder` of FoundationModelsExtras plugs into
/// `Searcher` with no consumer code: the pooled embedder runs each call as
/// one job in the queue of its model, and its vectors reach the fusion.
///
/// The test makes a `ModelPool(loader:)` with a ``StubModelLoader``, so the
/// pooled embedder loads a stub in place of an MLX model. The test needs no
/// GPU and no download.
///
/// This file imports `FoundationModelsRanker` without `@testable`, so the
/// embedder reaches the public surface only, the same surface that an
/// outside package gets.
@Suite("Pooled embedder")
struct PooledConformanceTests {
    /// The Hugging Face name of the stub embedding model.
    private static let embeddingModel: ModelRef = "org/stub-embedding"

    /// The query of the test.
    private static let query = "search file contents with a regular expression"

    /// The largest number of matches that one search returns.
    private static let matchLimit = 5

    @Test("A PooledEmbedder on a stub loader drives the cosine signal of the hybrid ranking")
    func aPooledEmbedderDrivesTheCosineSignal() async throws {
        let pool = ModelPool(loader: StubModelLoader(container: ConstantPooledEmbedding()))
        let recorder = DiagnosticRecorder()

        let searcher = try await Searcher(
            SearcherTests.toolItems,
            embedder: PooledEmbedder(ref: Self.embeddingModel, pool: pool),
            model: nil,
            mode: .retrieval,
            onDiagnostic: recorder.record
        )
        let matches = try await searcher.search(Self.query, limit: Self.matchLimit)

        #expect(recorder.diagnostics.isEmpty)
        let first = try #require(matches.first)
        let signals = try #require(first.signals)
        #expect(signals.cosine > 0.0)
    }
}

/// A stub embedding container for a `ModelPool`: it gives the same unit
/// vector for each text.
///
/// Equal vectors have a cosine similarity of one, so each item gets a cosine
/// score above zero. That is enough to show that the vectors of the pooled
/// embedder reached the fusion.
private struct ConstantPooledEmbedding: PooledEmbedding {
    /// The unit vector that each text gets.
    private static let unitVector: [Float] = [1, 0]

    /// Gives ``unitVector`` for each text.
    ///
    /// - Parameter texts: The texts.
    /// - Returns: One copy of ``unitVector`` for each text.
    func embed(texts: [String]) async throws -> [[Float]] {
        texts.map { _ in Self.unitVector }
    }
}
