import Foundation
import Testing

@testable import FoundationModelsRanker

/// Tests for the selection tier's over-budget path: when the assembled
/// prefix (the preamble, the `# Candidates` header, and one `## <id>`
/// heading above each candidate's `summaryBlock(forID:)`) exceeds
/// `capacityCharacterLimit`, the tier splits the catalog ids, in catalog
/// order, into runs whose assembled prefix each fits the budget, and sends
/// one prompt for each run. Every id reaches one prompt. No retrieval
/// ranking picks the candidates, and no `.retrievalCut` is reported.
///
/// Driven directly against `SelectionTier` with scripted `AgentSession`
/// fakes (`Support/ScriptedAgentSession.swift`) over a
/// `FixtureSelectionCatalog` -- zero GPU, no external dependency, the same
/// pattern `SelectionTests` uses for the under-budget path.
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

    /// The prefix a prompt for `run` carries.
    ///
    /// - Parameter run: the candidate ids of one prompt, in order.
    /// - Returns: the assembled prefix for those ids.
    static func prefix(for run: [String]) -> String {
        SelectionTier.assemblePrefix(preamble: .selectionDefault, ids: run, catalog: catalog)
    }

    /// A tier over `catalog` that answers with `config` and records every
    /// diagnostic in `recorder`.
    ///
    /// - Parameters:
    ///   - config: the tier's session source and budget.
    ///   - recorder: receives every diagnostic the tier reports.
    /// - Returns: the tier under test.
    static func makeTier(config: SelectionConfig, recorder: DiagnosticRecorder = DiagnosticRecorder()) -> SelectionTier {
        SelectionTier(catalog: catalog, config: config, onDiagnostic: { recorder.record($0) })
    }

    // MARK: - Every id reaches one prompt

    @Test
    func overBudgetSendsEveryCatalogIdToExactlyOnePrompt() async throws {
        let factory = RecordingSessionFactory(responses: [#"{"ids":["alpha"]}"#])
        let config = SelectionConfig(model: factory.makeSession, capacityCharacterLimit: Self.twoCandidateLimit)
        let tier = Self.makeTier(config: config)

        _ = try await tier.search(intent: "alpha", limit: Self.resultLimit)

        // The heading line is matched whole, so an id that is a prefix of
        // another id cannot count twice.
        for id in Self.catalog.ids {
            let promptsCarryingID = factory.receivedInstructions.filter { $0.contains("## \(id)\n") }
            #expect(promptsCarryingID.count == 1, "\(id) must reach exactly one prompt")
        }
    }

    @Test
    func overBudgetPromptsKeepCatalogOrderAndEachFitsTheBudget() async throws {
        let factory = RecordingSessionFactory(responses: [#"{"ids":["alpha"]}"#])
        let config = SelectionConfig(model: factory.makeSession, capacityCharacterLimit: Self.twoCandidateLimit)
        let tier = Self.makeTier(config: config)

        _ = try await tier.search(intent: "alpha", limit: Self.resultLimit)

        #expect(factory.receivedInstructions == Self.expectedRuns.map(Self.prefix(for:)))
        for instructions in factory.receivedInstructions {
            #expect(instructions.count <= Self.twoCandidateLimit)
        }
    }

    @Test
    func anEntryThatDoesNotFitTheBudgetAloneStillGetsAPromptOfItsOwn() async throws {
        let factory = RecordingSessionFactory(responses: [#"{"ids":["alpha"]}"#])
        let config = SelectionConfig(model: factory.makeSession, capacityCharacterLimit: Self.forcedOverBudgetLimit)
        let tier = Self.makeTier(config: config)

        _ = try await tier.search(intent: "alpha", limit: Self.resultLimit)

        // The tier cannot make a prompt smaller than one entry, so an entry
        // over the budget is sent alone rather than dropped.
        #expect(factory.receivedInstructions == Self.catalog.ids.map { Self.prefix(for: [$0]) })
    }

    // MARK: - Merged answer: prompt order, then the model's order

    @Test
    func overBudgetMergesAnsweredIdsInPromptOrderThenInTheModelsOrder() async throws {
        // One session answers every prompt in turn, so the first prompt gets
        // the first answer, and so on down the list.
        let session = ScriptedAgentSession([
            #"{"ids":["bravo","alpha"]}"#,
            #"{"ids":["gamma"]}"#,
            #"{"ids":[]}"#,
        ])
        let config = SelectionConfig(model: { _ in session }, capacityCharacterLimit: Self.twoCandidateLimit)
        let tier = Self.makeTier(config: config)

        let matches = try await tier.search(intent: "alpha", limit: Self.resultLimit)

        #expect(matches.map(\.id) == ["bravo", "alpha", "gamma"])
        #expect(matches.map(\.score) == [OrderScores.firstPick, OrderScores.secondPick, OrderScores.thirdPick])
        #expect(matches.allSatisfy { $0.signals == nil })
    }

    @Test
    func overBudgetResultsAreTruncatedToLimitAfterEveryPromptAnswered() async throws {
        let session = ScriptedAgentSession([
            #"{"ids":["alpha"]}"#,
            #"{"ids":["delta"]}"#,
            #"{"ids":["kappa"]}"#,
        ])
        let config = SelectionConfig(model: { _ in session }, capacityCharacterLimit: Self.twoCandidateLimit)
        let tier = Self.makeTier(config: config)

        let matches = try await tier.search(intent: "alpha", limit: 2)

        // Every prompt is answered before the cut, so a later prompt's pick
        // is never lost to an early stop.
        #expect(session.callCount == Self.expectedRuns.count)
        #expect(matches.map(\.id) == ["alpha", "delta"])
    }

    @Test
    func anIdAnsweredFromAnotherPromptsCandidatesStillResolvesOnce() async throws {
        // The catalog is the id set every prompt draws from, so an id the
        // model names in one prompt and again in its own prompt resolves,
        // and resolves one time only.
        let session = ScriptedAgentSession([
            #"{"ids":["kappa"]}"#,
            #"{"ids":[]}"#,
            #"{"ids":["kappa"]}"#,
        ])
        let recorder = DiagnosticRecorder()
        let config = SelectionConfig(model: { _ in session }, capacityCharacterLimit: Self.twoCandidateLimit)
        let tier = Self.makeTier(config: config, recorder: recorder)

        let matches = try await tier.search(intent: "alpha", limit: Self.resultLimit)

        #expect(matches.map(\.id) == ["kappa"])
        #expect(recorder.diagnostics.isEmpty)
    }

    // MARK: - Session source: one supplied session vs a session factory

    @Test
    func overBudgetSuppliedSessionIsForkedOncePerPromptWithThatPromptsCandidatesOnly() async throws {
        let session = ScriptedAgentSession(Self.expectedRuns.map { _ in #"{"ids":["alpha"]}"# })
        let config = SelectionConfig(session: session, capacityCharacterLimit: Self.twoCandidateLimit)
        let tier = Self.makeTier(config: config)

        _ = try await tier.search(intent: "alpha", limit: Self.resultLimit)

        #expect(session.forkCount == Self.expectedRuns.count)
        // A live session takes no new instructions, so each prompt carries
        // its own run's prefix above the intent, and no other run's.
        let expectedPrompts = Self.expectedRuns.map { "\(Self.prefix(for: $0))\n\n# Task\n\nalpha" }
        #expect(session.receivedPrompts == expectedPrompts)
    }

    @Test
    func overBudgetFactorySessionIsPromptedWithTheIntentUnderTheTaskHeading() async throws {
        let session = ScriptedAgentSession(Self.expectedRuns.map { _ in #"{"ids":["alpha"]}"# })
        let config = SelectionConfig(model: { _ in session }, capacityCharacterLimit: Self.twoCandidateLimit)
        let tier = Self.makeTier(config: config)

        _ = try await tier.search(intent: "alpha", limit: Self.resultLimit)

        // A factory session already holds its run's prefix as instructions,
        // so each prompt carries the same `# Task` heading and the intent,
        // exactly as the under-budget factory prompt does.
        #expect(session.receivedPrompts == Self.expectedRuns.map { _ in "# Task\n\nalpha" })
    }

    // MARK: - One-off sessions: no caching, no fork

    @Test
    func overBudgetCreatesAFreshSessionPerPromptWithoutCaching() async throws {
        let factoryCallCount = CallCounter()
        let config = SelectionConfig(
            model: { _ in
                factoryCallCount.increment()
                return ScriptedAgentSession([#"{"ids":["alpha"]}"#])
            },
            capacityCharacterLimit: Self.twoCandidateLimit
        )
        let tier = Self.makeTier(config: config)

        _ = try await tier.search(intent: "alpha", limit: Self.resultLimit)
        _ = try await tier.search(intent: "alpha", limit: Self.resultLimit)

        // Unlike the cached-root path, every prompt of every call gets a
        // fresh session.
        #expect(factoryCallCount.count == Self.expectedRuns.count * 2)
    }

    @Test
    func overBudgetFactorySessionIsNeverForked() async throws {
        let session = ScriptedAgentSession(Self.expectedRuns.map { _ in #"{"ids":["alpha"]}"# })
        let config = SelectionConfig(model: { _ in session }, capacityCharacterLimit: Self.twoCandidateLimit)
        let tier = Self.makeTier(config: config)

        _ = try await tier.search(intent: "alpha", limit: Self.resultLimit)

        #expect(session.forkCount == 0)
        #expect(session.callCount == Self.expectedRuns.count)
    }

    // MARK: - Diagnostics

    @Test
    func overBudgetReportsNoDiagnosticWhenEveryAnswerIsACatalogId() async throws {
        let recorder = DiagnosticRecorder()
        let factory = RecordingSessionFactory(responses: [#"{"ids":["alpha"]}"#])
        let config = SelectionConfig(model: factory.makeSession, capacityCharacterLimit: Self.twoCandidateLimit)
        let tier = Self.makeTier(config: config, recorder: recorder)

        _ = try await tier.search(intent: "alpha", limit: Self.resultLimit)

        // No retrieval cut picks the candidates, so nothing is reported.
        #expect(recorder.diagnostics.isEmpty)
    }

    @Test
    func overBudgetIdOutsideTheCatalogIsFilteredAndReportedAsUnknown() async throws {
        let recorder = DiagnosticRecorder()
        let session = ScriptedAgentSession([
            #"{"ids":["alpha","zulu"]}"#,
            #"{"ids":[]}"#,
            #"{"ids":[]}"#,
        ])
        let config = SelectionConfig(model: { _ in session }, capacityCharacterLimit: Self.twoCandidateLimit)
        let tier = Self.makeTier(config: config, recorder: recorder)

        let matches = try await tier.search(intent: "alpha", limit: Self.resultLimit)

        #expect(matches.map(\.id) == ["alpha"])
        #expect(recorder.diagnostics == [.unknownSelectedId(id: "zulu")])
    }

    @Test
    func overBudgetWithAnEmptyCatalogReturnsNoMatchesWithoutInvokingTheSessionFactory() async throws {
        let recorder = DiagnosticRecorder()
        let factoryCallCount = CallCounter()
        let config = SelectionConfig(
            model: { _ in
                factoryCallCount.increment()
                return ScriptedAgentSession([#"{"ids":[]}"#])
            },
            capacityCharacterLimit: Self.forcedOverBudgetLimit
        )
        let tier = SelectionTier(
            catalog: FixtureSelectionCatalog([]),
            config: config,
            onDiagnostic: { recorder.record($0) }
        )

        let matches = try await tier.search(intent: "alpha", limit: Self.resultLimit)

        // No candidate, no prompt: there is nothing to ask a model to choose
        // among, and nothing to report.
        #expect(matches.isEmpty)
        #expect(factoryCallCount.count == 0)
        #expect(recorder.diagnostics.isEmpty)
    }

    // MARK: - Budget boundary

    @Test
    func prefixExactlyAtTheCapacityLimitUsesTheCachedRootPath() async throws {
        let fullPrefix = Self.prefix(for: Self.catalog.ids)
        let factoryCallCount = CallCounter()
        let root = RootSessionRespondCalledDirectlySession(forkResponses: [
            #"{"ids":["alpha"]}"#,
            #"{"ids":["alpha"]}"#,
        ])
        let config = SelectionConfig(
            model: { _ in
                factoryCallCount.increment()
                return root
            },
            capacityCharacterLimit: fullPrefix.count
        )
        let tier = Self.makeTier(config: config)

        _ = try await tier.search(intent: "alpha", limit: Self.resultLimit)
        _ = try await tier.search(intent: "alpha", limit: Self.resultLimit)

        // Cached-root path: the factory runs exactly once, and every call
        // forks -- the boundary itself (`==`) still counts as "under
        // budget", matching `capacityCharacterLimit`'s own "at or under"
        // documentation.
        #expect(factoryCallCount.count == 1)
        #expect(root.forkCount == 2)
    }

    @Test
    func prefixOneCharacterOverTheCapacityLimitSplitsTheCatalogIntoTwoPrompts() async throws {
        let fullPrefix = Self.prefix(for: Self.catalog.ids)
        let factory = RecordingSessionFactory(responses: [#"{"ids":["alpha"]}"#])
        let config = SelectionConfig(model: factory.makeSession, capacityCharacterLimit: fullPrefix.count - 1)
        let tier = Self.makeTier(config: config)

        _ = try await tier.search(intent: "alpha", limit: Self.resultLimit)

        // One character short of the whole catalog: the first four
        // equal-length entries fit one prompt, and the last one gets its own.
        let expectedRuns = [["alpha", "bravo", "delta", "gamma"], ["kappa"]]
        #expect(factory.receivedInstructions == expectedRuns.map(Self.prefix(for:)))
    }
}
