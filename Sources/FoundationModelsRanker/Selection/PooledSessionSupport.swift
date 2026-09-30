import FoundationModelsExtras

/// The conformance of the FoundationModelsExtras `PooledSession` to
/// `AgentSession`. A caller that has a `PooledModel` gives its sessions to a
/// selection factory and writes no conformance code:
///
/// ```swift
/// let qwen = PooledModel(ref: "mlx-community/Qwen3-4B-4bit")
/// let config = SelectionConfig(model: { try await qwen.session(instructions: $0) })
/// ```
///
/// `PooledSession` already declares `respond(to:)` and
/// `respond(to:generating:)` with the signatures of the `AgentSession`
/// requirements, so those methods are the witnesses of the conformance. A
/// call through `any AgentSession` thus reaches the native guided generation
/// of the session, and not the default that decodes plain text. Only
/// `fork()` needs a forward, because `PooledSession.fork()` returns the
/// concrete type.
extension PooledSession: AgentSession {
    /// Forks this session for a new call.
    ///
    /// Forwards to the fork of `PooledSession`. The child continues the
    /// transcript of this session, with its own hold of the model. Thus the
    /// cached root of `SelectionTier` fills its prefix one time, and each
    /// call runs on a child that does not see the turns of the other calls.
    ///
    /// - Returns: the forked child session.
    /// - Throws: whatever `PooledSession.fork()` throws.
    public func fork() async throws -> any AgentSession {
        let child: PooledSession = try await fork()
        return child
    }
}
