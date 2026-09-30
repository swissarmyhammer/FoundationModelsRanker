import FoundationModelsExtras

/// The conformance of the FoundationModelsExtras `PooledEmbedder` to
/// `TextEmbedding`. A caller that has a pooled embedding model gives it to
/// `Searcher` and writes no conformance code:
///
/// ```swift
/// let embedder = PooledEmbedder(ref: "mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ")
/// let searcher = try await Searcher(items, embedder: embedder)
/// ```
extension PooledEmbedder: TextEmbedding {
    /// Embeds each input string into a vector, in order.
    ///
    /// Forwards to `PooledEmbedder.embed(texts:)`. The first call of an
    /// embedder made from a name loads the model into its pool.
    ///
    /// - Parameter texts: The strings to embed.
    /// - Returns: One vector per input, in the same order as `texts`.
    /// - Throws: whatever `PooledEmbedder.embed(texts:)` throws.
    public func embed(_ texts: [String]) async throws -> [[Float]] {
        try await embed(texts: texts)
    }
}
