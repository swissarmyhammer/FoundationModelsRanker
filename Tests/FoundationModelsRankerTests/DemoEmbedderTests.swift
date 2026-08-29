import Foundation
import FullMontyCore
import FoundationModelsRanker
import Testing

/// Tests for `DemoEmbedder`, the `FullMonty` example's GPU-free embedder.
///
/// The example needs an embedder to show the cosine signal at all, and it
/// must run with no GPU, no network, and no model. `DemoEmbedder` hashes
/// character trigrams into a fixed-length vector, so these tests hold it to
/// three things: the shape of what it returns, unit length, and
/// determinism.
///
/// Determinism is the sharp edge. Swift seeds `String.hashValue` and
/// `Hasher` for each process, so an embedder built on either would give a
/// different vector on each run. `theCheckedInExpectedVectorProvesTheHashIsProcessIndependent`
/// holds a vector computed outside this process, which only a stable hash
/// can reproduce.
@Suite("DemoEmbedder")
struct DemoEmbedderTests {
    // MARK: - Shape

    @Test("embed(_:) returns one vector per input, each of the configured dimension")
    func embedReturnsOneVectorPerInputOfTheConfiguredDimension() async throws {
        let embedder = DemoEmbedder(dimension: 16)

        let vectors = try await embedder.embed(["record staged changes", "list a branch", "watch a directory"])

        #expect(vectors.count == 3)
        for vector in vectors {
            #expect(vector.count == 16)
        }
    }

    @Test("embed(_:) returns the vectors in input order")
    func embedReturnsTheVectorsInInputOrder() async throws {
        let embedder = DemoEmbedder(dimension: 16)

        let batch = try await embedder.embed(["record staged changes", "watch a directory"])
        let first = try await embedder.embed(["record staged changes"])
        let second = try await embedder.embed(["watch a directory"])

        #expect(batch[0] == first[0])
        #expect(batch[1] == second[0])
        // A batch that returned its vectors in any other order would still
        // pass the two assertions above if both texts embedded alike, so
        // state that they do not.
        #expect(first[0] != second[0])
    }

    @Test("The default dimension is 256")
    func theDefaultDimensionIs256() {
        #expect(DemoEmbedder().dimension == 256)
    }

    // MARK: - Determinism

    @Test("Two calls in one process give the same vector for the same text")
    func twoCallsInOneProcessGiveTheSameVector() async throws {
        let embedder = DemoEmbedder()

        let first = try await embedder.embed(["record staged changes"])
        let second = try await embedder.embed(["record staged changes"])

        #expect(first == second)
    }

    // The vector below was computed outside this process, from the
    // documented algorithm: lowercase the text, take each sliding
    // 3-character window, add 1 at `FNV-1a(window) % dimension`, then
    // normalize. A `String.hashValue` or `Hasher` embedder is seeded for
    // each process and could not reproduce it twice, let alone here.
    @Test("The checked-in expected vector proves the hash is process-independent")
    func theCheckedInExpectedVectorProvesTheHashIsProcessIndependent() async throws {
        let embedder = DemoEmbedder(dimension: 8)
        let expected: [Float] = [
            0.18257418, 0.0, 0.18257418, 0.18257418, 0.54772252, 0.54772252, 0.54772252, 0.0,
        ]

        let vector = try #require(try await embedder.embed(["commit changes"]).first)

        #expect(vector.count == expected.count)
        for (component, expectedComponent) in zip(vector, expected) {
            #expect(abs(component - expectedComponent) < 0.000001)
        }
    }

    // MARK: - Unit length

    @Test("Every returned vector has a length of about 1.0")
    func everyReturnedVectorHasUnitLength() async throws {
        let embedder = DemoEmbedder()

        let vectors = try await embedder.embed(["record staged changes", "list a branch", "watch a directory"])

        for vector in vectors {
            let magnitude = sqrt(vector.reduce(Float(0)) { partial, component in partial + component * component })
            #expect(abs(magnitude - 1) < 0.00001)
        }
    }
}
