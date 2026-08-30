import FoundationModels
import FoundationModelsRanker
import Testing

/// Drives the `LanguageModelSession: AgentSession` conformance against a live
/// `SystemLanguageModel`, so a run needs a Mac with Apple Intelligence turned
/// on.
///
/// `SelectionTierRealModelTests` drives the same conformance through
/// `SelectionTier`, which asks for a `Generable` type and thus reaches the
/// typed override, `respond(to:generating:)`. This suite drives the plain
/// text method, `respond(to:)`, which no other test reaches.
///
/// The two methods do different work. `respond(to:generating:)` uses the
/// session's own guided generation. `respond(to:)` returns free text, and it
/// is also the method that `AgentSession`'s default
/// `respond(to:generating:)` calls for each conformer that supplies no
/// override. A defect in the plain text method is thus a defect in two paths.
///
/// Nothing selects between the hermetic tests and these tests at run time.
/// This target lives only in the nested `IntegrationTests` package, so
/// `swift test` at the repository root cannot see it, and
/// `swift test --package-path IntegrationTests` runs it.
@Suite("LanguageModelSession as an AgentSession on the live system model")
struct LanguageModelSessionRealModelTests {
    /// The instructions the session gets when it is made.
    ///
    /// The instructions ask for plain prose and for a short answer. A short
    /// answer keeps the run quick, and plain prose keeps the model away from
    /// the guided generation path this suite must not use.
    private static let instructions = "You answer with one short sentence of plain prose."

    /// The prompt the test sends.
    ///
    /// The question is simple and has no risk, so the model answers it
    /// instead of refusing it.
    private static let prompt = "What color is the sky on a clear day?"

    /// A `LanguageModelSession` held as `any AgentSession` must answer a
    /// prompt with plain text.
    ///
    /// The test holds the session as `any AgentSession`, so the call goes
    /// through the protocol witness and reaches the conformance's own
    /// `respond(to:)`. A direct call on a `LanguageModelSession` value
    /// reaches the session's native method instead, and it would leave the
    /// conformance unexercised.
    ///
    /// The prompt asks for prose and names no `Generable` type, so the plain
    /// text method is the method that runs. Only a real
    /// `SystemLanguageModel` can answer, so only this target can hold the
    /// claim.
    ///
    /// A real model does not use the same words two times, so the test makes
    /// no claim about which words come back. It claims only that the answer
    /// holds text.
    @Test("A LanguageModelSession held as any AgentSession answers with plain text")
    func aLanguageModelSessionHeldAsAnyAgentSessionAnswersWithPlainText() async throws {
        let session: any AgentSession = LanguageModelSession(
            model: SystemLanguageModel.default,
            instructions: Self.instructions
        )

        let answer = try await session.respond(to: Self.prompt)

        #expect(answer.contains { !$0.isWhitespace })
    }
}
