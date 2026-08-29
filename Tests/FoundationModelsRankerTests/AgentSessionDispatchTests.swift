import FoundationModels
import FullMontyCore
import Testing

@testable import FoundationModelsRanker

/// Tests that `AgentSession.respond(to:generating:)` dispatches through
/// `any AgentSession` to a conformer's own override.
///
/// `SelectionTier` holds each session as `any AgentSession`. When the typed
/// method is only an extension method, Swift binds the call to the extension
/// default and never reaches a conformer's override. The protocol must name
/// the typed method as a requirement so the existential dispatches it.
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

    /// One live-model fixture entry whose summary names its own id, so a
    /// session with no id-enum grammar can still answer with that id.
    static func liveItem(id: String, description: String) -> FixtureSelectionCatalog.Item {
        .init(id: id, block: description, summary: "id: \(id) -- \(description)")
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

    // MARK: - Live on-device model, gated

    /// A bare `LanguageModelSession` must reach its native guided generation
    /// through `SelectionTier`. Without the protocol requirement the default
    /// path asks the model for free text and fails to decode it as JSON.
    ///
    /// A bare session carries no id-enum grammar, so each summary names its
    /// own id: the model can only return an id it has seen.
    @Test(.enabled(if: isFoundationModelsRankerIntegrationEnabled))
    func selectionTierWithABareLanguageModelSessionReachesGuidedGeneration() async throws {
        let catalog = FixtureSelectionCatalog([
            Self.liveItem(id: "readFile", description: "reads the contents of a file at a path"),
            Self.liveItem(id: "writeFile", description: "writes text to a file at a path"),
            Self.liveItem(id: "listDirectory", description: "lists the entries of a directory"),
        ])
        let config = SelectionConfig(model: { instructions in
            LanguageModelSession(model: SystemLanguageModel.default, instructions: instructions)
        })
        let recorder = DiagnosticRecorder()
        let tier = SelectionTier(
            catalog: catalog,
            config: config,
            onDiagnostic: recorder.record,
            retrievalRanking: { _ in
                catalog.ids.map { id in
                    SelectionMatch(id: id, block: catalog.block(forID: id) ?? "", score: 0.5, signals: nil)
                }
            }
        )

        let matches = try await tier.search(intent: "read the contents of a file", limit: 3)

        #expect(recorder.diagnostics.isEmpty)
        #expect(!matches.isEmpty)
        #expect(matches.allSatisfy { catalog.ids.contains($0.id) })
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
