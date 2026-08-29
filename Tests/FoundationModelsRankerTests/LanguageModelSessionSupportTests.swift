import FoundationModels
import Testing

@testable import FoundationModelsRanker

/// Tests for the retroactive `LanguageModelSession: AgentSession`
/// conformance (plan.md §3a, §6 phase 3): compile-level proofs that any
/// FoundationModels model constructs a valid `AgentSession` factory. Both
/// seams now take the same shape, `@Sendable (String) -> any AgentSession`
/// -- `SelectionConfig.init(model:)` and the `Searcher` facade's `session:` -- so
/// one test reads the bare closure type and the other reads the closure
/// through a `SelectionConfig`. A fork-semantics test stands beside them.
/// Every test here runs without live inference (construction and `fork()`
/// only; no `respond(to:)` call, so no GPU/model needed), per this task's
/// Tests scope.
///
/// SDK note (plan.md §7 risk): the installed macOS 27 SDK's
/// `FoundationModels.swiftinterface` exposes only `SystemLanguageModel
/// .default` -- no `.fast` static member -- so these tests use `.default`.
/// Nothing here assumes `.fast` exists; this conformance is generic over
/// `some LanguageModel`, not tied to a specific static member.
struct LanguageModelSessionSupportTests {
    // MARK: - Compile-level conformance

    @Test
    func languageModelSessionFactoryClosureTypeChecksAsAnAgentSessionFactory() {
        let factory: @Sendable (String) -> any AgentSession = { instructions in
            LanguageModelSession(model: SystemLanguageModel.default, instructions: instructions)
        }

        let session = factory("selection guidance")

        #expect(session is LanguageModelSession)
    }

    @Test
    func languageModelSessionFactoryClosureTypeChecksAsASelectionConfigModelFactory() {
        // `SelectionConfig.init(model:)` takes only the instructions text and
        // stores it as a `.factory` session source. A plain
        // `LanguageModelSession` factory applies no grammar of its own: it
        // relies on the session's native guided generation through
        // `respond(to:generating:)` instead.
        let config = SelectionConfig(model: { instructions in
            LanguageModelSession(model: SystemLanguageModel.default, instructions: instructions)
        })

        guard case .factory(let makeSession) = config.sessionSource else {
            Issue.record("the model: initializer must store a `.factory` source")
            return
        }
        let session = makeSession("selection guidance")

        #expect(session is LanguageModelSession)
    }

    // MARK: - `fork()` semantics: returns `self`, unchanged (transcript accumulates)

    @Test
    func forkReturnsTheSameSessionInstanceUnchanged() async throws {
        let session = LanguageModelSession(model: SystemLanguageModel.default, instructions: "instructions")

        let forked = try await session.fork()

        #expect((forked as? LanguageModelSession) === session)
    }
}
