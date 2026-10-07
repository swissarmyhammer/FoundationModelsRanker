import FoundationModelsExtras

/// A `PooledModelLoader` that gives one fixed container for each key, and
/// loads nothing.
///
/// A unit test makes a `ModelPool(loader:)` with this loader, so a
/// `PooledEmbedder` of that pool gets a stub model in place of an MLX
/// model.
struct StubModelLoader: PooledModelLoader {
    /// The container that each load gives.
    let container: any Sendable

    /// Gives ``container``.
    ///
    /// - Parameter key: The model and its role. The stub gives the same
    ///   container for each key.
    /// - Returns: ``container``.
    func load(_ key: ModelPoolKey) async throws -> any Sendable {
        container
    }

    /// Does nothing: the stub container holds no memory to free.
    ///
    /// - Parameter container: The container that ``load(_:)`` gave.
    func evict(_ container: any Sendable) async {}
}
