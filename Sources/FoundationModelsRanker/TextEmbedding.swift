// Ported from CodeContextKit's
// `Sources/CodeContextKit/Embedding/TextEmbedding.swift`. Lineage: Rust
// `swissarmyhammer-search` crate -> CodeContextKit -> FoundationModelsRanker.
// One change from both older copies: this protocol has no `dimension`
// requirement. `embed(_:)` is byte-identical to both.

/// A seam for converting text into fixed-length embedding vectors.
///
/// Abstracts over the concrete embedding backend so callers depend on this
/// narrow protocol rather than a specific implementation: conformers embed
/// a batch of texts; tests substitute a deterministic double. The caller
/// supplies the conformer, and `embed(_:)` is the whole contract a caller
/// writes against. This package ships no embedding model of its own. It
/// supplies one conformance: the FoundationModelsExtras `PooledEmbedder`
/// (see `PooledEmbedderSupport.swift`).
///
/// The protocol declares no vector length. Each returned vector carries its
/// own length, so an embedder that loads its model at the first call does
/// not need to know that length before the call.
public protocol TextEmbedding: Sendable {
    /// Embeds each input string into a vector, in order.
    ///
    /// - Parameter texts: The strings to embed.
    /// - Returns: One vector per input, in the same order as `texts`. All
    ///   the vectors from one embedder have the same length.
    /// - Throws: If the underlying embedding computation fails.
    func embed(_ texts: [String]) async throws -> [[Float]]
}
