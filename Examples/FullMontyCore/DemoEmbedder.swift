// `FullMonty`'s embedder (plan.md §3a): the example must show the cosine
// signal, and the package itself ships no embedder -- `TextEmbedding.swift`'s
// header states that the caller supplies one. Every real embedder needs a
// model, a GPU, or a network call, so the example supplies a hashed
// bag-of-trigrams embedder instead: it needs none of the three, it runs in
// microseconds, and it gives a query and a near-verbatim catalog item a
// genuinely high cosine, which is the whole point of the demonstration.
//
// New to FoundationModelsRanker -- no source file to port. The nearest
// relative is `Tests/FoundationModelsRankerTests/Support/FakeEmbedder.swift`,
// a test double that hashes a whole text into a pseudo-random vector. That
// vector carries no meaning: two texts about the same subject are as far
// apart as two texts about different ones. This embedder hashes character
// TRIGRAMS into buckets instead, so two texts that share words share
// components, and the cosine the example prints is a real similarity.

import FoundationModelsRanker

/// The `FullMonty` example's deterministic, GPU-free embedder.
///
/// Embeds a text as a hashed bag of character trigrams: each of the text's
/// sliding 3-character windows (`Tokenizer.charTrigrams(text:)`) adds 1 to
/// one component, chosen by a stable hash of the window, and the vector is
/// then normalized to unit length. Two texts that share words share
/// components, so `CosineScoring.cosineSimilarity(_:_:)` reports a real
/// similarity rather than noise.
///
/// **Deterministic across processes.** The bucket comes from an FNV-1a hash
/// of the trigram's own UTF-8 bytes, never from `String.hashValue` or
/// `Hasher`: Swift seeds both of those for each process, so a vector built
/// on either would differ between two runs of the same program on the same
/// machine. The same text therefore always gives the same vector here, on
/// any machine and in any process, which is what lets
/// `DemoEmbedderTests` hold this type to a checked-in expected vector.
///
/// This is a demonstration embedder, not a semantic one. It knows nothing
/// about meaning: it rescues spelling and word overlap, and two texts that
/// say the same thing in different words score near zero. A consumer
/// wanting real semantics supplies its own `TextEmbedding` conformer, which
/// is the seam this example exists to show.
public struct DemoEmbedder: TextEmbedding {
    /// The vector length `init(dimension:)` uses when the caller names none.
    ///
    /// Large enough that the ~50-item `toolCatalog` and its queries collide
    /// in few buckets, small enough that embedding the whole catalog stays
    /// instant.
    public static let defaultDimension = 256

    /// The length of every vector this embedder produces.
    ///
    /// Never negative: `init(dimension:)` clamps, mirroring
    /// `SelectionConfig`'s own treatment of its budgets.
    public let dimension: Int

    /// Creates an embedder that hashes trigrams into `dimension` buckets.
    ///
    /// - Parameter dimension: the length of every vector this embedder
    ///   produces. Defaults to `defaultDimension`. A negative value is
    ///   clamped to `0`, which makes every vector empty.
    public init(dimension: Int = DemoEmbedder.defaultDimension) {
        self.dimension = max(0, dimension)
    }

    /// Embeds each text as a unit-length hashed bag of its character
    /// trigrams.
    ///
    /// - Parameter texts: the texts to embed.
    /// - Returns: one `dimension`-length vector per text, in the same order
    ///   as `texts`.
    public func embed(_ texts: [String]) async throws -> [[Float]] {
        texts.map(vector(forText:))
    }

    /// Builds one text's vector: one `+1` for each trigram, at the bucket
    /// its stable hash names, then normalized to unit length.
    ///
    /// A text of fewer than 3 characters has no trigram, so its vector
    /// stays all zeros -- `dimension` long, like every other, and scoring
    /// zero against everything.
    private func vector(forText text: String) -> [Float] {
        guard dimension > 0 else { return [] }

        var components = [Float](repeating: 0, count: dimension)
        for trigram in Tokenizer.charTrigrams(text: text) {
            components[Self.bucket(forTrigram: trigram, dimension: dimension)] += 1
        }
        return Self.normalized(components)
    }

    /// The component `trigram` adds to: its stable hash, folded into
    /// `0..<dimension`.
    ///
    /// - Parameters:
    ///   - trigram: the trigram to place.
    ///   - dimension: the number of buckets. Must be greater than `0`.
    /// - Returns: the index of `trigram`'s component.
    private static func bucket(forTrigram trigram: String, dimension: Int) -> Int {
        Int(fnv1aHash(ofText: trigram) % UInt64(dimension))
    }

    /// Scales `components` to unit length, or returns them unchanged when
    /// they are all zero and there is no length to scale.
    ///
    /// - Parameter components: the raw trigram counts.
    /// - Returns: the same components at a length of `1.0`, or the zero
    ///   vector.
    private static func normalized(_ components: [Float]) -> [Float] {
        let magnitude = (components.reduce(Float(0)) { partial, component in partial + component * component })
            .squareRoot()
        guard magnitude > 0 else { return components }
        return components.map { $0 / magnitude }
    }

    /// A stable 64-bit FNV-1a hash of `text`'s UTF-8 bytes.
    ///
    /// Stable means the same bytes give the same hash in every process on
    /// every machine, which `String.hashValue` and `Hasher` do not: Swift
    /// seeds those for each process. `FakeEmbedder`
    /// (`Tests/FoundationModelsRankerTests/Support/FakeEmbedder.swift`)
    /// carries the same standard hash for the same reason. The two are not
    /// shared because a test target cannot be imported, in either
    /// direction, and the library itself ships no hashing API to host it.
    ///
    /// - Parameter text: the text to hash.
    /// - Returns: the FNV-1a hash of its UTF-8 bytes.
    private static func fnv1aHash(ofText text: String) -> UInt64 {
        let offsetBasis: UInt64 = 0xCBF2_9CE4_8422_2325
        let prime: UInt64 = 0x0000_0100_0000_01B3
        var hash = offsetBasis
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }
        return hash
    }
}
