@testable import FoundationModelsRanker
import Testing

/// The error `CosineSignalTests` gives to `FakeEmbedder` to make the query
/// embed fail.
private struct QueryEmbedFailure: Error {}

/// `CosineSignal.scores(forQuery:embedder:itemEmbeddings:onDiagnostic:)`
/// tests. `Searcher` and `StreamingSearchCorpus` both get their cosine
/// signal from this one function, so these tests hold each case where the
/// signal is skipped and each case where it is used.
struct CosineSignalTests {
    /// The length of each vector in these tests.
    private static let vectorLength = 8

    /// A length that is different from `vectorLength`.
    private static let otherVectorLength = 5

    /// The query that each test embeds.
    private static let query = "stream change events"

    /// Item vectors that have the length `vectorLength`.
    private static func itemEmbeddings() async throws -> [[Float]] {
        try await FakeEmbedder(vectorLength: vectorLength).embed(["read a file", "watch a directory"])
    }

    @Test
    func vectorsOfTheSameLengthGiveOneCosineScoreForEachItemAndNoDiagnostic() async throws {
        let embedder = FakeEmbedder(vectorLength: Self.vectorLength)
        let items = try await Self.itemEmbeddings()
        let queryVector = try #require(try await embedder.embed([Self.query]).first)
        let recorder = DiagnosticRecorder()

        let scores = await CosineSignal.scores(
            forQuery: Self.query, embedder: embedder, itemEmbeddings: items, onDiagnostic: recorder.record
        )

        #expect(scores == items.map { CosineScoring.cosineSimilarity(queryVector, $0) })
        #expect(recorder.diagnostics.isEmpty)
    }

    @Test
    func noEmbedderSkipsTheSignalAndReportsTheDiagnosticOneTime() async throws {
        let recorder = DiagnosticRecorder()

        let scores = await CosineSignal.scores(
            forQuery: Self.query, embedder: nil, itemEmbeddings: try await Self.itemEmbeddings(),
            onDiagnostic: recorder.record
        )

        #expect(scores == nil)
        #expect(recorder.diagnostics == [.embeddingUnavailable])
    }

    @Test
    func noItemEmbeddingsSkipsTheSignalAndReportsTheDiagnosticOneTime() async {
        let recorder = DiagnosticRecorder()

        let scores = await CosineSignal.scores(
            forQuery: Self.query, embedder: FakeEmbedder(vectorLength: Self.vectorLength), itemEmbeddings: nil,
            onDiagnostic: recorder.record
        )

        #expect(scores == nil)
        #expect(recorder.diagnostics == [.embeddingUnavailable])
    }

    @Test
    func aFailedQueryEmbedSkipsTheSignalAndReportsTheDiagnosticOneTime() async throws {
        let embedder = FakeEmbedder(vectorLength: Self.vectorLength, failure: QueryEmbedFailure())
        let recorder = DiagnosticRecorder()

        let scores = await CosineSignal.scores(
            forQuery: Self.query, embedder: embedder, itemEmbeddings: try await Self.itemEmbeddings(),
            onDiagnostic: recorder.record
        )

        #expect(scores == nil)
        #expect(recorder.diagnostics == [.embeddingUnavailable])
    }

    @Test
    func aQueryVectorOfADifferentLengthSkipsTheSignalAndReportsTheDiagnosticOneTime() async throws {
        let embedder = FakeEmbedder(vectorLength: Self.otherVectorLength)
        let recorder = DiagnosticRecorder()

        let scores = await CosineSignal.scores(
            forQuery: Self.query, embedder: embedder, itemEmbeddings: try await Self.itemEmbeddings(),
            onDiagnostic: recorder.record
        )

        #expect(scores == nil)
        #expect(recorder.diagnostics == [.embeddingUnavailable])
    }
}
