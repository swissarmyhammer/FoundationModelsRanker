import FoundationModels
import Testing

@testable import FoundationModelsRanker

/// Tests that `AgentSession.respond(to:generating:)` dispatches through
/// `any AgentSession` to a conformer's own override.
///
/// `SelectionTier` holds each session as `any AgentSession`. When the typed
/// method is only an extension method, Swift binds the call to the extension
/// default and never reaches a conformer's override. The protocol must name
/// the typed method as a requirement so the existential dispatches it.
///
/// Every session here is a double, so the suite reaches no model. The same
/// claim against a live `SystemLanguageModel` is a real-model test, and it
/// lives in the nested integration package
/// (`IntegrationTests/Tests/FoundationModelsRankerIntegrationTests/SelectionTierRealModelTests.swift`).
struct AgentSessionDispatchTests {
    // MARK: - Fixtures

    /// A catalog that holds one id for each response path of
    /// `PathMarkingAgentSession`, so either path yields a legal selection.
    static let catalog = FixtureSelectionCatalog([
        .init(id: PathMarkingAgentSession.typedPathID, block: "answered by the typed override"),
        .init(id: PathMarkingAgentSession.plainPathID, block: "answered by the plain-text default"),
    ])

    /// Scripted full-catalog ranking for `Self.catalog`.
    static func rankEntireCatalog(intent: String) async -> [SelectionMatch] {
        catalog.ids.map { id in
            SelectionMatch(id: id, block: catalog.block(forID: id) ?? "", score: 0.5, signals: nil)
        }
    }

    // MARK: - Dispatch through the existential

    @Test
    func typedOverrideIsReachedThroughTheExistential() async throws {
        let session: any AgentSession = PathMarkingAgentSession()

        let selection = try await session.respond(to: "prompt", generating: Selection.self)

        #expect(selection.ids == [PathMarkingAgentSession.typedPathID])
    }

    @Test
    func selectionTierReachesTheTypedOverride() async throws {
        let config = SelectionConfig(model: { _ in PathMarkingAgentSession() })
        let tier = SelectionTier(
            catalog: Self.catalog,
            config: config,
            onDiagnostic: { _ in },
            retrievalRanking: Self.rankEntireCatalog
        )

        let matches = try await tier.search(intent: "any intent", limit: 5)

        #expect(matches.map(\.id) == [PathMarkingAgentSession.typedPathID])
    }

    // MARK: - The protocol defaults a minimal conformer inherits

    @Test
    func aConformerWithOnlyRespondToInheritsTheDefaultFork() async throws {
        let session: any AgentSession = PlainTextOnlyAgentSession()

        let forked = try await session.fork()

        let answer = try await forked.respond(to: "prompt")
        #expect(answer == PlainTextOnlyAgentSession.answer)
    }

    @Test
    func aConformerWithOnlyRespondToInheritsTheDefaultTypedRespond() async throws {
        let session: any AgentSession = PlainTextOnlyAgentSession()

        let selection = try await session.respond(to: "prompt", generating: Selection.self)

        #expect(selection.ids == [PlainTextOnlyAgentSession.selectedID])
    }
}

/// An `AgentSession` double whose two response paths answer with different
/// ids, so a test can read which path a call reached from the decoded
/// result. `respond(to:)` answers with `plainPathID`; the typed override
/// answers with `typedPathID`.
///
/// A `struct` with no state: the returned id is the whole record.
private struct PathMarkingAgentSession: AgentSession {
    /// The id the typed override answers with.
    static let typedPathID = "typed"

    /// The id the plain-text `respond(to:)` answers with.
    static let plainPathID = "plain"

    /// Answers with a JSON selection of `plainPathID`.
    func respond(to prompt: String) async throws -> String {
        #"{"ids":["\#(Self.plainPathID)"]}"#
    }

    /// Answers with a decoded selection of `typedPathID`.
    func respond<T: Generable>(to prompt: String, generating type: T.Type) async throws -> T {
        try T(GeneratedContent(json: #"{"ids":["\#(Self.typedPathID)"]}"#))
    }
}

/// An `AgentSession` conformer that implements `respond(to:)` and nothing
/// else, so a test can read what the protocol's own defaults do.
///
/// Every other double in this target overrides `fork()`, and
/// `PathMarkingAgentSession` above overrides the typed `respond` as well, so
/// none of them can answer this question. This one is the smallest conformer
/// the protocol admits, which is what a caller writes against
/// `AgentSession` when it has no KV cache to fork and no native guided
/// generation to reach.
private struct PlainTextOnlyAgentSession: AgentSession {
    /// The id `answer` selects.
    static let selectedID = "plain-only"

    /// The whole text `respond(to:)` returns, verbatim: a JSON selection of
    /// `selectedID`, which is what the default `respond(to:generating:)`
    /// decodes.
    static let answer = #"{"ids":["\#(Self.selectedID)"]}"#

    func respond(to prompt: String) async throws -> String {
        Self.answer
    }
}
