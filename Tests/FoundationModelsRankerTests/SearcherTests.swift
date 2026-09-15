import Foundation
import FoundationModels
import Testing

@testable import FoundationModelsRanker

/// Tests for `Searcher`: the package's one-call facade --
/// "a list of things to search, then a query" -- composing `HybridRanker`
/// (retrieval) with `SelectionTier` (agent selection) over an in-memory
/// catalog built from the caller's items.
///
/// Driven entirely against scripted `AgentSession` fakes
/// (`Support/ScriptedAgentSession.swift`) and `FakeEmbedder`
/// (`Support/FakeEmbedder.swift`) -- zero GPU, no live system model, no
/// external dependency, matching every other selection-tier suite in this
/// target. One test makes a real `LanguageModelSession` to show the
/// instance front door takes it, but answers in `.retrieval` mode, so no
/// test here runs inference.
struct SearcherTests {
    // MARK: - Fixtures

    /// The README's "grep/glob/watch" example catalog: three tools, only
    /// one of which lexically/fuzzily overlaps with the queries this suite
    /// uses.
    static let toolItems = [
        SearchItem(id: "grep", text: "Search file contents with regular expressions"),
        SearchItem(id: "glob", text: "Find files by name pattern, sorted by mtime"),
        SearchItem(id: "watch", text: "Watch a directory and stream change events"),
    ]

    /// A large catalog whose assembled selection prefix exceeds
    /// `SelectionConfig.defaultCapacityCharacterLimit` (32,000 characters) --
    /// `Searcher` doesn't expose `capacityCharacterLimit` as a knob, so the
    /// over-budget path is forced here by bulk `summary` content instead of
    /// a tiny forced limit
    /// (`OverBudgetTests`'s approach against `SelectionTier` directly).
    /// `summary` (which pads the assembled prefix) is deliberately long
    /// filler for every entry so the budget is blown, and the catalog is
    /// split into several prompts.
    static let bulkItems: [SearchItem] = {
        let filler = String(repeating: "padding text that inflates the assembled selection prefix past budget. ", count: 12)
        return (0..<40).map { index in
            let id = index == 0 ? "alpha" : "filler\(index)"
            let text = index == 0 ? "alpha handles the urgent alpha task" : "unrelated filler content, no overlap"
            return SearchItem(id: id, text: text, summary: "SUMMARY_\(id) \(filler)")
        }
    }()

    /// The vector length every counting embedder in this suite produces.
    private static let embeddingDimension = 8

    // MARK: - `.retrieval` mode: no session touched, real signals attached

    @Test
    func retrievalModeRanksTheLexicallyClosestItemFirstWithRealSignals() async throws {
        let searcher = try await Searcher(Self.toolItems, session: nil, mode: .retrieval)

        let matches = try await searcher.search("search file contents with a regular expression", limit: 5)

        let first = try #require(matches.first)
        #expect(first.id == "grep")
        #expect(first.block == "Search file contents with regular expressions")
        #expect(first.score > 0.0)
        let signals = try #require(first.signals)
        #expect(signals.bm25 > 0.0)
    }

    @Test
    func retrievalModeNeverConsultsASessionEvenWhenOneIsConfigured() async throws {
        let session = ScriptedAgentSession([#"{"ids":["glob"]}"#])
        let searcher = try await Searcher(Self.toolItems, session: { _ in session }, mode: .retrieval)

        _ = try await searcher.search("search file contents with a regular expression", limit: 5)

        #expect(session.callCount == 0)
    }

    // MARK: - `.selection` mode, under budget: cached root + fork-per-call

    @Test
    func selectionModeUnderBudgetUsesTheConfiguredSessionAndScoresThePickByItsOrder() async throws {
        let root = RootSessionRespondCalledDirectlySession(forkResponses: [#"{"ids":["glob"]}"#])
        let factoryCallCount = CallCounter()
        let searcher = try await Searcher(
            Self.toolItems,
            session: { _ in
                factoryCallCount.increment()
                return root
            },
            mode: .selection
        )

        let matches = try await searcher.search("find files by name", limit: 5)

        #expect(matches.map(\.id) == ["glob"])
        #expect(matches.first?.block == "Find files by name pattern, sorted by mtime")
        // The one prompt picks, and nothing ranks the catalog after it: the
        // pick carries its order score and no retrieval signals.
        #expect(matches.first?.score == OrderScores.firstPick)
        #expect(matches.first?.signals == nil)
        // Cached-root + fork-per-call: the session factory ran exactly once.
        #expect(factoryCallCount.count == 1)
        #expect(root.forkCount == 1)
    }

    @Test
    func selectionModeMakesOneModelCallAndNeverEmbedsTheQuery() async throws {
        // `init` embeds every item in one call. A selection search asks the
        // model once and embeds nothing, so the count stays at that one call.
        let embedder = CountingEmbedder(dimension: Self.embeddingDimension)
        let session = ScriptedAgentSession([#"{"ids":["watch"]}"#])
        let recorder = DiagnosticRecorder()
        let searcher = try await Searcher(
            Self.toolItems,
            embedder: embedder,
            session: { _ in session },
            mode: .selection,
            onDiagnostic: { recorder.record($0) }
        )
        let embedCallsAfterInit = embedder.callCount

        let matches = try await searcher.search("qqqq")

        #expect(matches.map(\.id) == ["watch"])
        #expect(session.callCount == 1)
        #expect(embedder.callCount == embedCallsAfterInit)
        #expect(recorder.diagnostics.isEmpty)
    }

    @Test
    func swappingTheSessionFactorySwapsWhichModelAnswersSelection() async throws {
        // Two entirely different scripted sessions standing in for two
        // different models -- proving the model is a plain argument, never
        // hardcoded, by getting each configuration's own scripted answer
        // back verbatim.
        let searcherA = try await Searcher(
            Self.toolItems,
            session: { _ in ScriptedAgentSession([#"{"ids":["grep"]}"#]) },
            mode: .selection
        )
        let searcherB = try await Searcher(
            Self.toolItems,
            session: { _ in ScriptedAgentSession([#"{"ids":["watch"]}"#]) },
            mode: .selection
        )

        let matchesA = try await searcherA.search("anything", limit: 5)
        let matchesB = try await searcherB.search("anything", limit: 5)

        #expect(matchesA.map(\.id) == ["grep"])
        #expect(matchesB.map(\.id) == ["watch"])
    }

    // MARK: - `.selection` mode, over budget: one prompt per run of items

    @Test
    func selectionModeOverBudgetSendsEveryItemIdToExactlyOnePrompt() async throws {
        let factory = RecordingSessionFactory(responses: [#"{"ids":["alpha"]}"#])
        let searcher = try await Searcher(Self.bulkItems, session: factory.makeSession, mode: .selection)

        let matches = try await searcher.search("urgent alpha task")

        #expect(matches.map(\.id) == ["alpha"])
        #expect(matches.first?.score == OrderScores.firstPick)
        #expect(matches.first?.signals == nil)
        // The catalog does not fit one prompt, so it is split into several,
        // and every item reaches exactly one of them. The heading line is
        // matched whole, because `## filler3` is a prefix of `## filler30`.
        #expect(factory.receivedInstructions.count > 1)
        for item in Self.bulkItems {
            let promptsCarryingID = factory.receivedInstructions.filter { $0.contains("## \(item.id)\n") }
            #expect(promptsCarryingID.count == 1, "\(item.id) must reach exactly one prompt")
        }
    }

    @Test
    func selectionModeOverBudgetNeverEmbedsTheQueryAndReportsNoDiagnostic() async throws {
        let embedder = CountingEmbedder(dimension: Self.embeddingDimension)
        let recorder = DiagnosticRecorder()
        let searcher = try await Searcher(
            Self.bulkItems,
            embedder: embedder,
            session: { _ in ScriptedAgentSession([#"{"ids":["alpha"]}"#]) },
            mode: .selection,
            onDiagnostic: { recorder.record($0) }
        )
        let embedCallsAfterInit = embedder.callCount

        _ = try await searcher.search("urgent alpha task")

        // No retrieval cut picks the candidates, so no query is embedded and
        // nothing is reported.
        #expect(embedder.callCount == embedCallsAfterInit)
        #expect(recorder.diagnostics.isEmpty)
    }

    // MARK: - `.auto` mode resolution, both ways

    @Test
    func autoModeResolvesToSelectionWhenASessionIsConfigured() async throws {
        // Retrieval alone would rank "grep" first for this query (lexical
        // overlap with "search"/"regular expression"); scripting the
        // session to hand back "watch" instead proves `.auto` actually
        // drove the selection tier, not a retrieval fallback.
        let searcher = try await Searcher(
            Self.toolItems,
            session: { _ in ScriptedAgentSession([#"{"ids":["watch"]}"#]) },
            mode: .auto
        )

        let matches = try await searcher.search("search file contents with a regular expression", limit: 5)

        #expect(matches.map(\.id) == ["watch"])
        // The pick carries its order score and no retrieval signals: `.auto`
        // with a session runs no retrieval at all.
        #expect(matches.first?.score == OrderScores.firstPick)
        #expect(matches.first?.signals == nil)
    }

    @Test
    func autoModeWithASessionNeverEmbedsTheQueryOrReportsEmbeddingUnavailable() async throws {
        let embedder = CountingEmbedder(dimension: Self.embeddingDimension)
        let recorder = DiagnosticRecorder()
        let searcher = try await Searcher(
            Self.toolItems,
            embedder: embedder,
            session: { _ in ScriptedAgentSession([#"{"ids":["watch"]}"#]) },
            mode: .auto,
            onDiagnostic: { recorder.record($0) }
        )
        let embedCallsAfterInit = embedder.callCount

        _ = try await searcher.search("search file contents with a regular expression")

        #expect(embedder.callCount == embedCallsAfterInit)
        #expect(recorder.diagnostics.isEmpty)
    }

    @Test
    func autoModeDegradesToRetrievalWhenNoSessionIsConfigured() async throws {
        let searcher = try await Searcher(Self.toolItems, session: nil, mode: .auto)

        let matches = try await searcher.search("search file contents with a regular expression", limit: 5)

        let first = try #require(matches.first)
        #expect(first.id == "grep")
        // Retrieval's fused ranking put the lexically closest item first --
        // proves `.auto` actually fell back rather than silently returning
        // nothing.
        #expect(first.score > 0.0)
        #expect(first.signals != nil)
    }

    // MARK: - The `session:` front doors: one live session, or a factory

    @Test
    func aSuppliedSessionAnswersSelectionAndScoresThePickByItsOrder() async throws {
        // The instance front door: a caller that already holds a session
        // gives it directly, with no factory closure around it.
        let session = ScriptedAgentSession([#"{"ids":["glob"]}"#])
        let searcher = try await Searcher(Self.toolItems, session: session, mode: .selection)

        let matches = try await searcher.search("find files by name", limit: 5)

        #expect(matches.map(\.id) == ["glob"])
        #expect(matches.first?.block == "Find files by name pattern, sorted by mtime")
        // The supplied session answered: a `.session` source forks the very
        // session the caller gave, and makes no session of its own.
        #expect(session.forkCount == 1)
        // The pick carries its order score and no retrieval signals.
        #expect(matches.first?.score == OrderScores.firstPick)
        #expect(matches.first?.signals == nil)
    }

    @Test
    func aSuppliedSessionGetsTheAssembledPrefixInThePromptBecauseItTakesNoInstructions() async throws {
        // A live session cannot take new instructions, so the prompt must
        // carry the catalog. Without it the model sees no candidate and can
        // return no id.
        let session = ScriptedAgentSession([#"{"ids":["glob"]}"#])
        let searcher = try await Searcher(Self.toolItems, session: session, mode: .selection)

        _ = try await searcher.search("find files by name", limit: 5)

        let prompt = try #require(session.receivedPrompts.first)
        #expect(prompt.contains("# Candidates"))
        #expect(prompt.contains("## glob"))
        #expect(prompt.contains("find files by name"))
    }

    @Test
    func everySessionArgumentShapeResolvesWithNoTypeAnnotationAtTheCallSite() async throws {
        // One contract, three call shapes, each written the way a caller
        // writes it: with no type annotation. A closure takes the factory
        // front door, because a function type conforms to no protocol. A
        // live session takes the instance front door, because a session is
        // no function. `nil` stays on the factory front door, because the
        // instance front door takes a plain `any AgentSession`, which no
        // `nil` can fill. Each shape is here because only the three
        // together show the overloads stay unambiguous.
        let factory = RecordingSessionFactory(responses: [#"{"ids":["grep"]}"#])
        let closureSearcher = try await Searcher(
            Self.toolItems,
            session: { instructions in factory.makeSession(instructions: instructions) },
            mode: .selection
        )
        let suppliedSession = ScriptedAgentSession([#"{"ids":["grep"]}"#])
        let sessionSearcher = try await Searcher(Self.toolItems, session: suppliedSession, mode: .selection)
        let nilSearcher = try await Searcher(Self.toolItems, session: nil, mode: .selection)

        _ = try await closureSearcher.search("anything", limit: 5)
        _ = try await sessionSearcher.search("anything", limit: 5)

        // Only a `.factory` source calls the factory.
        #expect(factory.receivedInstructions.count == 1)
        // Only a `.session` source forks the session the caller supplied.
        #expect(suppliedSession.forkCount == 1)
        // Only the factory front door takes `nil`, which leaves selection
        // unavailable.
        await #expect(throws: SelectionTierUnavailable.self) {
            try await nilSearcher.search("anything", limit: 5)
        }
    }

    @Test
    func theInstanceFormAndTheFactoryFormGiveTheSameMatchesForTheSameScriptedAnswer() async throws {
        // Two front doors, one behavior: the same catalog and the same
        // answer must give the same matches, ids, blocks, scores, and
        // signals included.
        let answer = #"{"ids":["watch"]}"#
        let factorySearcher = try await Searcher(
            Self.toolItems,
            session: { _ in ScriptedAgentSession([answer]) },
            mode: .selection
        )
        let sessionSearcher = try await Searcher(
            Self.toolItems,
            session: ScriptedAgentSession([answer]),
            mode: .selection
        )

        let factoryMatches = try await factorySearcher.search("find files by name", limit: 5)
        let sessionMatches = try await sessionSearcher.search("find files by name", limit: 5)

        #expect(factoryMatches.map(\.id) == ["watch"])
        #expect(factoryMatches == sessionMatches)
    }

    @Test
    func aLiveLanguageModelSessionGoesStraightInAsTheSessionArgument() async throws {
        // The shape this front door exists for: a caller that already holds
        // a `LanguageModelSession` gives it, with no factory closure and no
        // type annotation. `.retrieval` mode answers with no model call, so
        // this test runs no inference.
        let session = LanguageModelSession(model: SystemLanguageModel.default, instructions: "selection guidance")
        let searcher = try await Searcher(Self.toolItems, session: session, mode: .retrieval)

        let matches = try await searcher.search("search file contents with a regular expression", limit: 5)

        #expect(matches.first?.id == "grep")
        #expect(matches.first?.block == "Search file contents with regular expressions")
    }

    // MARK: - Degradation: no embedder, reported never silently

    @Test
    func noEmbedderDegradesToKeywordOnlyRetrievalAndReportsADiagnostic() async throws {
        let recorder = DiagnosticRecorder()
        let searcher = try await Searcher(
            Self.toolItems,
            embedder: nil,
            session: nil,
            mode: .retrieval,
            onDiagnostic: { recorder.record($0) }
        )

        let matches = try await searcher.search("search file contents with a regular expression", limit: 5)

        #expect(matches.first?.id == "grep")
        #expect(matches.first?.signals?.cosine == 0.0)
        #expect(recorder.diagnostics.contains(.embeddingUnavailable))
    }

    @Test
    func selectionModeWithNoEmbedderReportsNoEmbeddingUnavailable() async throws {
        // A selection search runs no retrieval, so it wants no cosine signal
        // and has no degradation to report when no embedder is set.
        let recorder = DiagnosticRecorder()
        let searcher = try await Searcher(
            Self.toolItems,
            embedder: nil,
            session: { _ in ScriptedAgentSession([#"{"ids":["glob"]}"#]) },
            mode: .selection,
            onDiagnostic: { recorder.record($0) }
        )

        _ = try await searcher.search("find files by name", limit: 5)

        #expect(recorder.diagnostics.isEmpty)
    }

    @Test
    func configuringAnEmbedderSuppressesTheNoEmbedderDiagnostic() async throws {
        let recorder = DiagnosticRecorder()
        let searcher = try await Searcher(
            Self.toolItems,
            embedder: FakeEmbedder(dimension: 8),
            session: nil,
            mode: .retrieval,
            onDiagnostic: { recorder.record($0) }
        )

        _ = try await searcher.search("search file contents with a regular expression", limit: 5)

        #expect(!recorder.diagnostics.contains(.embeddingUnavailable))
    }

    // MARK: - Degradation: the query embed fails at search time

    @Test
    func aFailedQueryEmbedDegradesToKeywordOnlyRetrievalAndReportsTheDiagnosticOncePerSearch() async throws {
        // The README promises this: an embedder is configured and every item
        // carries an embedding, but the query embed throws at search time, so
        // retrieval drops to keyword only and says so. `init` embeds every
        // item in one call, and each retrieval search embeds the query in one
        // more call, so call 2 is the query embed.
        let queryEmbedCallNumber = 2
        let recorder = DiagnosticRecorder()
        let searcher = try await Searcher(
            Self.toolItems,
            embedder: CountingEmbedder(dimension: 8, failingFromCall: queryEmbedCallNumber),
            session: nil,
            mode: .retrieval,
            onDiagnostic: { recorder.record($0) }
        )

        let matches = try await searcher.search("search file contents with a regular expression", limit: 5)

        // Keyword retrieval still answers: the failed query embed degrades the
        // search, and does not throw it away or empty it.
        #expect(matches.first?.id == "grep")
        #expect((matches.first?.score ?? 0.0) > 0.0)
        #expect((matches.first?.signals?.bm25 ?? 0.0) > 0.0)
        // A zero cosine tells the caller the signal did not contribute.
        #expect(matches.first?.signals?.cosine == 0.0)
        // One search reports the degradation one time.
        #expect(recorder.diagnostics.filter { $0 == .embeddingUnavailable }.count == 1)
    }

    // MARK: - Degradation: a zeroed cosine weight is an opt-out, not a failure

    @Test
    func zeroCosineWeightOptsOutOfTheSignalWithoutReportingADiagnosticEvenWithNoEmbedder() async throws {
        let recorder = DiagnosticRecorder()
        let searcher = try await Searcher(
            Self.toolItems,
            embedder: nil,
            session: nil,
            weights: SignalWeights(cosine: 0.0),
            mode: .retrieval,
            onDiagnostic: { recorder.record($0) }
        )

        let matches = try await searcher.search("search file contents with a regular expression", limit: 5)

        #expect(matches.first?.id == "grep")
        // A deliberately zeroed weight is an opt-out, not a degradation --
        // unlike `noEmbedderDegradesToKeywordOnlyRetrievalAndReportsADiagnostic`
        // (default weights, `.embeddingUnavailable` fires every search),
        // this must report nothing.
        #expect(!recorder.diagnostics.contains(.embeddingUnavailable))
    }

    // MARK: - `limit <= 0` short-circuits to an empty result

    @Test
    func nonPositiveLimitReturnsEmptyInRetrievalMode() async throws {
        let searcher = try await Searcher(Self.toolItems, session: nil, mode: .retrieval)

        let matches = try await searcher.search("search file contents with a regular expression", limit: 0)

        #expect(matches.isEmpty)
    }

    @Test
    func nonPositiveLimitReturnsEmptyInSelectionModeWithoutCreatingASession() async throws {
        let factoryCallCount = CallCounter()
        let searcher = try await Searcher(
            Self.toolItems,
            session: { _ in
                factoryCallCount.increment()
                return ScriptedAgentSession([#"{"ids":["grep"]}"#])
            },
            mode: .selection
        )

        let matches = try await searcher.search("anything", limit: -1)

        #expect(matches.isEmpty)
        #expect(factoryCallCount.count == 0)
    }

    @Test
    func nonPositiveLimitReturnsEmptyInAutoModeWithoutCreatingASession() async throws {
        let factoryCallCount = CallCounter()
        let searcher = try await Searcher(
            Self.toolItems,
            session: { _ in
                factoryCallCount.increment()
                return ScriptedAgentSession([#"{"ids":["grep"]}"#])
            },
            mode: .auto
        )

        let matches = try await searcher.search("anything", limit: 0)

        #expect(matches.isEmpty)
        #expect(factoryCallCount.count == 0)
    }

    // MARK: - Duplicate ids: first occurrence wins, never a crash

    @Test
    func duplicateItemIdKeepsTheFirstOccurrenceAndDropsLaterOnes() async throws {
        let items = [
            SearchItem(id: "grep", text: "the first, real grep description mentioning regular expressions"),
            SearchItem(id: "grep", text: "a later duplicate that should never be indexed"),
        ]
        let searcher = try await Searcher(items, session: nil, mode: .retrieval)

        let matches = try await searcher.search("regular expressions", limit: 5)

        #expect(matches.map(\.id) == ["grep"])
        #expect(matches.first?.block == "the first, real grep description mentioning regular expressions")
    }

    // MARK: - Degradation: `.selection` requested with no session configured

    @Test
    func selectionModeWithNoSessionConfiguredThrowsSelectionTierUnavailable() async throws {
        let searcher = try await Searcher(Self.toolItems, session: nil, mode: .selection)

        await #expect(throws: SelectionTierUnavailable.self) {
            try await searcher.search("anything", limit: 5)
        }
    }

    // MARK: - A `Searchable` conformer, not wrapped in `SearchItem`

    /// A richer type participating directly through `Searchable`, proving
    /// the protocol -- not just `SearchItem` -- is the real seam `Searcher`
    /// drives. A richer type can take part without a `SearchItem` wrapper.
    private struct FixtureTool: Searchable {
        let id: String
        let text: String
        // `summary` uses `Searchable`'s default (`text`).
    }

    @Test
    func aSearchableConformerNotWrappedInSearchItemWorksEndToEnd() async throws {
        let tools = [
            FixtureTool(id: "deploy", text: "ships containers to a kubernetes cluster"),
            FixtureTool(id: "rollback", text: "reverts the last release"),
        ]
        let searcher = try await Searcher(tools, session: nil, mode: .retrieval)

        let matches = try await searcher.search("roll back the last release", limit: 5)

        #expect(matches.first?.id == "rollback")
        #expect(matches.first?.block == "reverts the last release")
    }

    // MARK: - `SearchItem.summary` defaults to `text`

    @Test
    func searchItemSummaryDefaultsToTextWhenOmitted() {
        let item = SearchItem(id: "id", text: "the text")
        #expect(item.summary == "the text")
    }

    @Test
    func searchItemSummaryUsesTheExplicitValueWhenProvided() {
        let item = SearchItem(id: "id", text: "the text", summary: "a short summary")
        #expect(item.summary == "a short summary")
    }
}
