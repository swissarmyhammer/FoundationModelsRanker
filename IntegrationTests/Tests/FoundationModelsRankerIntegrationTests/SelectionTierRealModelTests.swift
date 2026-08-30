import FoundationModels
import FoundationModelsRanker
import Testing

/// Drives `SelectionTier` against a live `SystemLanguageModel`, so a run
/// needs a Mac with Apple Intelligence turned on.
///
/// The root package holds the hermetic tests of the same seam
/// (`Tests/FoundationModelsRankerTests/AgentSessionDispatchTests.swift`).
/// Each one scripts an `AgentSession` double and reaches no model. This
/// target holds the tests that need the real model instead. Nothing selects
/// between the two at run time: this target lives only in the nested
/// `IntegrationTests` package, so `swift test` at the repository root cannot
/// see it, and `swift test --package-path IntegrationTests` runs it.
@Suite("Selection tier on the live system model")
struct SelectionTierRealModelTests {
    /// The tools the model chooses among.
    ///
    /// Three ids, each with a description that separates it clearly from the
    /// other two, so a correct answer is one id and a wrong answer is
    /// legible.
    private static let catalog = LiveToolCatalog([
        .init(id: "readFile", description: "reads the contents of a file at a path"),
        .init(id: "writeFile", description: "writes text to a file at a path"),
        .init(id: "listDirectory", description: "lists the entries of a directory"),
    ])

    /// A bare `LanguageModelSession` must reach its native guided generation
    /// through `SelectionTier`.
    ///
    /// `AgentSession` names `respond(to:generating:)` as a protocol
    /// requirement, so a call through `any AgentSession` reaches the
    /// session's own typed override. Without the requirement the call binds
    /// to the protocol extension's default, which asks the model for free
    /// text and then fails to decode that text as JSON. Only a real
    /// `SystemLanguageModel` has native guided generation to reach, so only
    /// this test can hold the claim.
    @Test("A bare LanguageModelSession reaches guided generation")
    func aBareLanguageModelSessionReachesGuidedGeneration() async throws {
        let catalog = Self.catalog
        let config = SelectionConfig(model: { instructions in
            LanguageModelSession(model: SystemLanguageModel.default, instructions: instructions)
        })
        let tier = SelectionTier(
            catalog: catalog,
            config: config,
            // A diagnostic on this path means the tier could not resolve
            // what the model answered, which is the failure the protocol
            // requirement removes. Record it where it happens, so the
            // failure names the diagnostic itself.
            onDiagnostic: { diagnostic in
                Issue.record("The selection tier reported \(diagnostic).")
            },
            retrievalRanking: { _ in catalog.everyEntryRanked() }
        )

        let matches = try await tier.search(intent: "read the contents of a file", limit: catalog.ids.count)

        #expect(!matches.isEmpty)
        #expect(matches.allSatisfy { catalog.ids.contains($0.id) })
    }
}
