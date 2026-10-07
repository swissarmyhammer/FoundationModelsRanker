import Foundation
import FoundationModelsRanker
import Testing

/// Tests for the embedding seam: `FakeEmbedder`'s determinism, vector
/// shape, and failure injection.
struct EmbeddingSeamTests {
    private struct SampleError: Error {}

    @Test
    func fakeEmbedderProducesTheSameVectorForTheSameTextEveryCall() async throws {
        let embedder = FakeEmbedder(vectorLength: 16)

        let first = try await embedder.embed(texts: ["func add() {}"])
        let second = try await embedder.embed(texts: ["func add() {}"])

        #expect(first == second)
    }

    @Test
    func fakeEmbedderProducesDifferentVectorsForDifferentText() async throws {
        let embedder = FakeEmbedder(vectorLength: 16)

        let vectors = try await embedder.embed(texts: ["func add() {}", "func subtract() {}"])

        #expect(vectors[0] != vectors[1])
    }

    @Test
    func fakeEmbedderProducesL2NormalizedVectorsOfTheConfiguredLength() async throws {
        let embedder = FakeEmbedder(vectorLength: 12)

        let vectors = try await embedder.embed(texts: ["func add() {}", "struct Sample {}"])

        for vector in vectors {
            #expect(vector.count == 12)
            let magnitude = sqrt(vector.reduce(Float(0)) { $0 + $1 * $1 })
            #expect(abs(magnitude - 1) < 0.0001)
        }
    }

    @Test
    func fakeEmbedderThrowsTheInjectedFailureInsteadOfProducingVectors() async throws {
        let embedder = FakeEmbedder(vectorLength: 8, failure: SampleError())

        await #expect(throws: SampleError.self) {
            _ = try await embedder.embed(texts: ["func add() {}"])
        }
    }
}
