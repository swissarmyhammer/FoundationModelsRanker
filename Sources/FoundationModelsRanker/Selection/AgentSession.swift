// Ported from FoundationModelsMetadataRegistry's
// `Sources/FoundationModelsMetadataRegistry/Session/AgentSession.swift`
// (itself lifted as-is from Multitool's own
// `Sources/FoundationModelsMultitool/Agent/AgentSession.swift`). Lineage:
// Multitool -> FoundationModelsMetadataRegistry -> FoundationModelsRanker (plan.md §6
// phase 3). No behavior changes; doc comments generalized to FoundationModelsRanker's own
// consumers rather than naming FoundationModelsMetadataRegistry/Multitool
// specifics.

import FoundationModels

/// The minimal seam a selection-tier agent uses for each turn: send a
/// prompt, and get text back. The seam also has the `fork()` primitive that
/// a prefix-cached root session needs.
///
/// The seam is small on purpose. A conformer answers a prompt with plain
/// text, and that is all a selection call needs from a model. A conformer
/// that constrains its own output returns its answer through the same
/// method, so one shape is sufficient for both.
///
/// `fork()` is the second part. A prefix-rooted session fills its prefix one
/// time. Then it forks a child for each call, so it does not send the prefix
/// again. A conformer whose model can copy a filled KV cache makes `fork()`
/// do that copy. Every other conformer uses the default below, which returns
/// `self`.
///
/// Callers use this seam and nothing else. Thus a unit test can drive a
/// selection tier against a scripted fake that conforms to this protocol,
/// with no GPU. A caller that has its own model writes its own conformer.
/// This package supplies the conformance for `LanguageModelSession` (see
/// `LanguageModelSessionSupport.swift`), and no other.
public protocol AgentSession: Sendable {
    /// Sends `prompt` to the session and returns its complete text response.
    ///
    /// - Parameter prompt: the prompt to respond to -- the running
    ///   transcript for this turn, or a one-shot task prompt, depending on
    ///   the caller.
    /// - Returns: the session's complete text response.
    /// - Throws: whatever the underlying session throws.
    func respond(to prompt: String) async throws -> String

    /// Forks a child session. The child continues this session's
    /// conversation and gets its accumulated context, which includes the
    /// filled prefix. The child then diverges on its own.
    ///
    /// This is the primitive that a prefix-rooted session forks for each
    /// call, so the session fills its prefix one time instead of sending it
    /// again on every call.
    ///
    /// - Returns: the forked child session.
    /// - Throws: whatever the underlying session throws while forking.
    func fork() async throws -> any AgentSession

    /// Sends `prompt` to the session and decodes its response as a
    /// `Generable` type -- the seam a selection call uses to get
    /// well-formed structured output back.
    ///
    /// A protocol requirement, not only an extension method, so a call
    /// through `any AgentSession` reaches a conformer's own override.
    /// `SelectionTier` holds every session as `any AgentSession`; an
    /// extension method alone binds that call to the extension default and
    /// a conformer with native guided generation (`LanguageModelSession`)
    /// never gets to answer. The extension below supplies the default, so a
    /// conformer that only returns plain text implements `respond(to:)`
    /// and nothing more.
    ///
    /// - Parameters:
    ///   - prompt: the prompt to respond to.
    ///   - type: the `Generable` type to decode the response into.
    /// - Returns: the decoded value.
    /// - Throws: whatever the underlying session throws, or a decoding
    ///   error if the response isn't valid, schema-conforming JSON for `T`.
    func respond<T: Generable>(to prompt: String, generating type: T.Type) async throws -> T
}

extension AgentSession {
    /// Default `fork()`: returns `self`, with no change.
    ///
    /// A conformer with no real KV cache to fork does not need to override
    /// this. A scripted test double that stands in for a session whose
    /// caller never calls `fork()` is the usual example. Two kinds of
    /// conformer supply their own `fork()`: one whose model can copy a
    /// filled KV cache, and a test double that counts fork calls.
    public func fork() async throws -> any AgentSession { self }

    /// Default `respond(to:generating:)`: decodes `respond(to:)`'s plain text
    /// as JSON for `T`.
    ///
    /// The decode runs over this session's own `respond(to:)`. Thus it runs
    /// on the session that already holds the filled prefix. A model whose
    /// typed API constrains a new, one-shot session to `T`'s schema would
    /// fill the prefix again on every call, which removes the whole
    /// advantage of a prefix-rooted session. A conformer that has such an
    /// API overrides this method and keeps its own session.
    ///
    /// The text this method decodes is already grammar-constrained when the
    /// caller made the session with a grammar for `T`'s schema, and a
    /// `fork()` of such a session inherits that grammar.
    ///
    /// - Parameters:
    ///   - prompt: the prompt to respond to.
    ///   - type: the `Generable` type to decode the response into.
    /// - Returns: the decoded value.
    /// - Throws: whatever `respond(to:)` throws, or a decoding error if the
    ///   raw response isn't valid, schema-conforming JSON for `T` --
    ///   expected only if this session's underlying grammar doesn't
    ///   actually match `T`'s schema, a caller error, not a runtime
    ///   condition a correctly configured caller can trigger.
    public func respond<T: Generable>(to prompt: String, generating type: T.Type) async throws -> T {
        let raw = try await respond(to: prompt)
        return try T(GeneratedContent(json: raw))
    }
}
