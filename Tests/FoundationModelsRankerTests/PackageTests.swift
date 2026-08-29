import Foundation
import FoundationModelsRanker
import Testing

/// Proves the `FoundationModelsRanker` library target builds, links, and is
/// importable from a Swift Testing test target (plan.md §3).
@Test func moduleImportsAndBuilds() {
    #expect(Bool(true))
}

/// Proves `Package.swift` declares no external package dependency.
///
/// This package builds against the macOS SDK alone. Each `.package(` call in
/// the manifest adds a remote checkout, and two of the checkouts this package
/// once declared were private repositories that only members of one
/// organization could read. The test reads the manifest text, so a dependency
/// cannot come back without notice.
@Test func theManifestDeclaresNoPackageDependency() throws {
    let manifest = try String(contentsOf: manifestURL, encoding: .utf8)

    #expect(!manifest.contains(".package("))
}

/// Proves `TextEmbedding` is a complete seam on its own: a caller writes a
/// conformer against the public protocol and hands it to `Searcher`, with no
/// embedder adapter shipped by this package.
///
/// This file imports `FoundationModelsRanker` without `@testable`, so
/// `VowelCountEmbedder` reaches the public surface only -- the same surface
/// an outside package gets. A cosine signal above zero, together with no
/// `.embeddingUnavailable` diagnostic, shows the vectors reached
/// `HybridRanker` and were actually fused in.
@Test func aCallerSuppliedTextEmbeddingConformerDrivesTheCosineSignal() async throws {
    let items = [
        SearchItem(id: "grep", text: "Search file contents with regular expressions"),
        SearchItem(id: "glob", text: "Find files by name pattern, sorted by mtime"),
    ]
    let recorder = DiagnosticRecorder()

    let searcher = try await Searcher(
        items,
        embedder: VowelCountEmbedder(),
        session: nil,
        mode: .retrieval,
        onDiagnostic: recorder.record
    )
    let matches = try await searcher.search("search file contents with a regular expression")

    #expect(recorder.diagnostics.isEmpty)
    let first = try #require(matches.first)
    #expect(first.id == "grep")
    let signals = try #require(first.signals)
    #expect(signals.cosine > 0.0)
}

/// A `TextEmbedding` conformer written the way a caller writes one: against
/// the public protocol, with nothing but `dimension` and `embed(_:)`.
///
/// Deliberately not `FakeEmbedder` (`Support/FakeEmbedder.swift`). That
/// double exists to give other suites deterministic vectors; this type
/// exists to prove the protocol's two members are the whole contract, so it
/// stands beside the test that makes that claim and stays as small as the
/// claim allows.
///
/// Each component counts one vowel of the text, and the vector is then
/// normalized to unit length. That makes the vectors deterministic, free of
/// any model or GPU, and different for texts that differ in their vowels --
/// enough for a cosine score above zero.
private struct VowelCountEmbedder: TextEmbedding {
    /// The vowels each vector component counts, one component per vowel.
    private static let countedVowels: [Character] = ["a", "e", "i", "o", "u"]

    var dimension: Int { Self.countedVowels.count }

    func embed(_ texts: [String]) async throws -> [[Float]] {
        texts.map(Self.vector(forText:))
    }

    /// Counts each of `countedVowels` in `text` and normalizes the counts to
    /// unit length.
    ///
    /// - Parameter text: the text to embed.
    /// - Returns: a `dimension`-length vector, of unit length unless `text`
    ///   holds no counted vowel at all, in which case every component is
    ///   zero.
    private static func vector(forText text: String) -> [Float] {
        let lowercased = text.lowercased()
        let counts = countedVowels.map { vowel in
            Float(lowercased.count { character in character == vowel })
        }
        let magnitude = sqrt(counts.reduce(Float(0)) { total, count in total + count * count })
        guard magnitude > 0 else { return counts }
        return counts.map { count in count / magnitude }
    }
}
