import FoundationModels
import FoundationModelsRanker
import Testing

/// Drives `SelectionTier` against a live `SystemLanguageModel`, so a run
/// needs a Mac with Apple Intelligence turned on.
///
/// The root package holds the hermetic tests of the tier
/// (`Tests/FoundationModelsRankerTests/SelectionTests.swift`). Each one
/// scripts a FoundationModels model double and reaches no real model. This
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

    /// `SelectionTier` on `SystemLanguageModel.default` must get catalog ids
    /// back through the native guided generation of its sessions.
    ///
    /// The tier makes a `LanguageModelSession` on the model for each prompt
    /// and asks for a `Selection`. Only a real `SystemLanguageModel` has
    /// native guided generation to reach, so only this test can hold the
    /// claim that the answer decodes and names catalog ids.
    @Test("The system model answers a selection with catalog ids through guided generation")
    func theSystemModelAnswersASelectionWithCatalogIDs() async throws {
        let catalog = Self.catalog
        let config = SelectionConfig(model: SystemLanguageModel.default)
        let tier = SelectionTier(
            catalog: catalog,
            config: config,
            // A diagnostic on this path means the tier could not resolve
            // what the model answered. Record it where it happens, so the
            // failure names the diagnostic itself.
            onDiagnostic: { diagnostic in
                Issue.record("The selection tier reported \(diagnostic).")
            }
        )

        let matches = try await tier.search(intent: "read the contents of a file", limit: catalog.ids.count)

        #expect(!matches.isEmpty)
        #expect(matches.allSatisfy { catalog.ids.contains($0.id) })
    }
}
