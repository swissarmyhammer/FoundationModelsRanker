import Foundation
import Testing

@testable import FoundationModelsRanker

/// Tests for the selection tier's over-budget path: when the assembled
/// prefix (the preamble, and one `<candidate>` block with an `id:` line and
/// a `description:` line for each candidate's `summaryBlock(forID:)`) exceeds
/// `capacityCharacterLimit`, the tier splits the catalog ids, in catalog
/// order, into runs whose assembled prefix each fits the budget, and sends
/// one prompt for each run. Every id reaches one prompt. No retrieval
/// ranking picks the candidates, and no `.retrievalCut` is reported.
///
/// Driven directly against `SelectionTier` with a scripted FoundationModels
/// model (`Support/ScriptedLanguageModel.swift`) over a
/// `FixtureSelectionCatalog` -- zero GPU, no download, the same pattern
/// `SelectionTests` uses for the under-budget path.
struct OverBudgetTests {
    // MARK: - Fixtures

    /// Five items whose ids and summaries all have the same length, so the
    /// budget `twoCandidateLimit` fits exactly two entries in each prompt
    /// and the runs are `expectedRuns`.
    static let catalog = FixtureSelectionCatalog([
        .init(id: "alpha", block: "alpha handles alpha tasks", summary: "SUMMARY_alpha"),
        .init(id: "bravo", block: "second unrelated block text", summary: "SUMMARY_bravo"),
        .init(id: "delta", block: "third unrelated block text", summary: "SUMMARY_delta"),
        .init(id: "gamma", block: "fourth unrelated block text", summary: "SUMMARY_gamma"),
        .init(id: "kappa", block: "fifth unrelated block text", summary: "SUMMARY_kappa"),
    ])

    /// The runs `twoCandidateLimit` splits `catalog` into, in catalog order.
    static let expectedRuns = [["alpha", "bravo"], ["delta", "gamma"], ["kappa"]]

    /// A budget that holds exactly two of `catalog`'s equal-length entries:
    /// the assembled prefix of the first two ids, to the character.
    static let twoCandidateLimit = prefix(for: ["alpha", "bravo"]).count

    /// A `capacityCharacterLimit` of `1` is smaller than the preamble alone,
    /// so no entry fits beside another and every entry gets a prompt of its
    /// own.
    static let forcedOverBudgetLimit = 1

    /// The `limit` every search in this file asks for: more than the catalog
    /// holds, so no test truncates by accident.
    static let resultLimit = 5

    /// The answer that each prompt of the tests that do not read the answer
    /// gets.
    static let alphaAnswer = #"{"ids":["alpha"]}"#

    /// The prefix a prompt for `run` carries.
    ///
    /// - Parameter run: the candidate ids of one prompt, in order.
    /// - Returns: the assembled prefix for those ids.
    static func prefix(for run: [String]) -> String {
        SelectionTier.assemblePrefix(preamble: .selectionDefault, ids: run, catalog: catalog)
    }

    /// A scripted model that gives `alphaAnswer` to each of `count` prompts.
    ///
    /// - Parameter count: the number of prompts the model answers.
    /// - Returns: the model.
    static func alphaModel(count: Int) -> ScriptedLanguageModel {
        ScriptedLanguageModel(Array(repeating: alphaAnswer, count: count))
    }

    /// A tier over `catalog` that asks `model` within `limit`, and records
    /// every diagnostic in `recorder`.
    ///
    /// - Parameters:
    ///   - model: the scripted model that answers each prompt.
    ///   - limit: the capacity budget. Defaults to `twoCandidateLimit`.
    ///   - recorder: receives every diagnostic the tier reports.
    /// - Returns: the tier under test.
    static func makeTier(
        _ model: ScriptedLanguageModel,
        limit: Int = twoCandidateLimit,
        recorder: DiagnosticRecorder = DiagnosticRecorder()
    ) -> SelectionTier {
        SelectionTier(
            catalog: catalog,
            config: SelectionConfig(model: model, capacityCharacterLimit: limit),
            onDiagnostic: { recorder.record($0) }
        )
    }

    // MARK: - Every id reaches one prompt

    @Test
    func overBudgetSendsEveryCatalogIdToExactlyOnePrompt() async throws {
        let model = Self.alphaModel(count: Self.expectedRuns.count)
        let tier = Self.makeTier(model)

        _ = try await tier.search(intent: "alpha", limit: Self.resultLimit)

        // The `id:` line is matched whole, so an id that is a prefix of
        // another id cannot count twice.
        for id in Self.catalog.ids {
            let promptsCarryingID = model.calls.filter { $0.instructions?.contains("\nid: \(id)\n") == true }
            #expect(promptsCarryingID.count == 1, "\(id) must reach exactly one prompt")
        }
    }

    @Test
    func overBudgetPromptsKeepCatalogOrderAndEachFitsTheBudget() async throws {
        let model = Self.alphaModel(count: Self.expectedRuns.count)
        let tier = Self.makeTier(model)

        _ = try await tier.search(intent: "alpha", limit: Self.resultLimit)

        let instructions = model.calls.map(\.instructions)
        #expect(instructions == Self.expectedRuns.map(Self.prefix(for:)))
        for text in instructions.compactMap(\.self) {
            #expect(text.count <= Self.twoCandidateLimit)
        }
    }

    @Test
    func anEntryThatDoesNotFitTheBudgetAloneStillGetsAPromptOfItsOwn() async throws {
        let model = Self.alphaModel(count: Self.catalog.ids.count)
        let tier = Self.makeTier(model, limit: Self.forcedOverBudgetLimit)

        _ = try await tier.search(intent: "alpha", limit: Self.resultLimit)

        // The tier cannot make a prompt smaller than one entry, so an entry
        // over the budget is sent alone rather than dropped.
        #expect(model.calls.map(\.instructions) == Self.catalog.ids.map { Self.prefix(for: [$0]) })
    }

    @Test
    func eachOverBudgetPromptHasItsRunsPrefixAsInstructionsAndItsRunsRequestBlockAsItsPrompt() async throws {
        let model = Self.alphaModel(count: Self.expectedRuns.count)
        let tier = Self.makeTier(model)

        _ = try await tier.search(intent: "alpha", limit: Self.resultLimit)

        // Each run gets a new session with that run's prefix as its
        // instructions, so each prompt carries the same `<request>` block
        // and exact-id line as the under-budget prompt, with that run's ids
        // only.
        #expect(
            model.calls == Self.expectedRuns.map { run in
                ScriptedModelCall(
                    instructions: Self.prefix(for: run),
                    prompt: ExpectedSelectionPrompt.request(for: "alpha", ids: run)
                )
            }
        )
    }

    // MARK: - Merged answer: prompt order, then the model's order

    @Test
    func overBudgetMergesAnsweredIdsInPromptOrderThenInTheModelsOrder() async throws {
        // The model answers the prompts in turn, so the first prompt gets
        // the first answer, and so on down the list.
        let model = ScriptedLanguageModel([
            #"{"ids":["bravo","alpha"]}"#,
            #"{"ids":["gamma"]}"#,
            #"{"ids":[]}"#,
        ])
        let tier = Self.makeTier(model)

        let matches = try await tier.search(intent: "alpha", limit: Self.resultLimit)

        #expect(matches.map(\.id) == ["bravo", "alpha", "gamma"])
        #expect(matches.map(\.score) == [OrderScores.firstPick, OrderScores.secondPick, OrderScores.thirdPick])
        #expect(matches.allSatisfy { $0.signals == nil })
    }

    @Test
    func overBudgetResultsAreTruncatedToLimitAfterEveryPromptAnswered() async throws {
        let model = ScriptedLanguageModel([
            #"{"ids":["alpha"]}"#,
            #"{"ids":["delta"]}"#,
            #"{"ids":["kappa"]}"#,
        ])
        let tier = Self.makeTier(model)

        let matches = try await tier.search(intent: "alpha", limit: 2)

        // Every prompt is answered before the cut, so a later prompt's pick
        // is never lost to an early stop.
        #expect(model.calls.count == Self.expectedRuns.count)
        #expect(matches.map(\.id) == ["alpha", "delta"])
    }

    @Test
    func anIdAnsweredFromAnotherPromptsCandidatesStillResolvesOnce() async throws {
        // The catalog is the id set every prompt draws from, so an id the
        // model names in one prompt and again in its own prompt resolves,
        // and resolves one time only.
        let model = ScriptedLanguageModel([
            #"{"ids":["kappa"]}"#,
            #"{"ids":[]}"#,
            #"{"ids":["kappa"]}"#,
        ])
        let recorder = DiagnosticRecorder()
        let tier = Self.makeTier(model, recorder: recorder)

        let matches = try await tier.search(intent: "alpha", limit: Self.resultLimit)

        #expect(matches.map(\.id) == ["kappa"])
        #expect(recorder.diagnostics.isEmpty)
    }

    @Test
    func aModelErrorInALaterRunComesOutOfTheSearch() async throws {
        let model = ScriptedLanguageModel(answers: [.text(Self.alphaAnswer), .failure])
        let tier = Self.makeTier(model)

        await #expect(throws: ScriptedLanguageModelError.scriptedFailure) {
            try await tier.search(intent: "alpha", limit: Self.resultLimit)
        }
    }

    // MARK: - Diagnostics

    @Test
    func overBudgetReportsNoDiagnosticWhenEveryAnswerIsACatalogId() async throws {
        let recorder = DiagnosticRecorder()
        let tier = Self.makeTier(Self.alphaModel(count: Self.expectedRuns.count), recorder: recorder)

        _ = try await tier.search(intent: "alpha", limit: Self.resultLimit)

        // No retrieval cut picks the candidates, so nothing is reported.
        #expect(recorder.diagnostics.isEmpty)
    }

    @Test
    func overBudgetIdOutsideTheCatalogIsFilteredAndReportedAsUnknown() async throws {
        let recorder = DiagnosticRecorder()
        let model = ScriptedLanguageModel([
            #"{"ids":["alpha","zulu"]}"#,
            #"{"ids":[]}"#,
            #"{"ids":[]}"#,
        ])
        let tier = Self.makeTier(model, recorder: recorder)

        let matches = try await tier.search(intent: "alpha", limit: Self.resultLimit)

        #expect(matches.map(\.id) == ["alpha"])
        #expect(recorder.diagnostics == [.unknownSelectedId(id: "zulu")])
    }

    @Test
    func overBudgetWithAnEmptyCatalogReturnsNoMatchesWithoutAPrompt() async throws {
        let recorder = DiagnosticRecorder()
        let model = ScriptedLanguageModel([#"{"ids":[]}"#])
        let tier = SelectionTier(
            catalog: FixtureSelectionCatalog([]),
            config: SelectionConfig(model: model, capacityCharacterLimit: Self.forcedOverBudgetLimit),
            onDiagnostic: { recorder.record($0) }
        )

        let matches = try await tier.search(intent: "alpha", limit: Self.resultLimit)

        // No candidate, no prompt: there is nothing to ask a model to choose
        // among, and nothing to report.
        #expect(matches.isEmpty)
        #expect(model.calls.isEmpty)
        #expect(recorder.diagnostics.isEmpty)
    }

    // MARK: - Budget boundary

    @Test
    func prefixExactlyAtTheCapacityLimitSendsOnePromptWithTheWholeCatalog() async throws {
        let fullPrefix = Self.prefix(for: Self.catalog.ids)
        let model = Self.alphaModel(count: 1)
        let tier = Self.makeTier(model, limit: fullPrefix.count)

        _ = try await tier.search(intent: "alpha", limit: Self.resultLimit)

        // The boundary itself (`==`) still counts as "under budget",
        // matching `capacityCharacterLimit`'s own "at or under"
        // documentation.
        #expect(
            model.calls == [
                ScriptedModelCall(
                    instructions: fullPrefix,
                    prompt: ExpectedSelectionPrompt.request(for: "alpha", ids: Self.catalog.ids)
                )
            ]
        )
    }

    @Test
    func prefixOneCharacterOverTheCapacityLimitSplitsTheCatalogIntoTwoPrompts() async throws {
        let fullPrefix = Self.prefix(for: Self.catalog.ids)
        let model = Self.alphaModel(count: 2)
        let tier = Self.makeTier(model, limit: fullPrefix.count - 1)

        _ = try await tier.search(intent: "alpha", limit: Self.resultLimit)

        // One character short of the whole catalog: the first four
        // equal-length entries fit one prompt, and the last one gets its own.
        let expectedRuns = [["alpha", "bravo", "delta", "gamma"], ["kappa"]]
        #expect(model.calls.map(\.instructions) == expectedRuns.map(Self.prefix(for:)))
    }
}
