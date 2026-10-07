import Foundation
import FoundationModels
import Testing

@testable import FoundationModelsRanker

/// Tests for `Searcher`: the package's one-call facade --
/// "a list of things to search, then a query" -- composing `HybridRanker`
/// (retrieval) with `SelectionTier` (agent selection) over an in-memory
/// catalog built from the caller's items.
///
/// Driven entirely against a scripted FoundationModels model
/// (`Support/ScriptedLanguageModel.swift`) and `FakeEmbedder`
/// (`Support/FakeEmbedder.swift`) -- zero GPU, no live system model, no
/// download, matching every other selection-tier suite in this target. One
/// test gives `SystemLanguageModel.default` to show the `model:` argument
/// takes it, but answers in `.retrieval` mode, so no test here runs
/// inference.
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
    private static let embeddingVectorLength = 8

    /// A query vector length that differs from `embeddingVectorLength`.
    private static let mismatchedQueryVectorLength = 4

    /// The `limit` the async-closure searches in this suite ask for: more
    /// than the catalog holds, so no test truncates by accident.
    private static let resultLimit = 5

    // MARK: - `.retrieval` mode: no model touched, real signals attached

    @Test
    func retrievalModeRanksTheLexicallyClosestItemFirstWithRealSignals() async throws {
        let searcher = try await Searcher(Self.toolItems, model: nil, mode: .retrieval)

        let matches = try await searcher.search("search file contents with a regular expression", limit: 5)

        let first = try #require(matches.first)
        #expect(first.id == "grep")
        #expect(first.block == "Search file contents with regular expressions")
        #expect(first.score > 0.0)
        let signals = try #require(first.signals)
        #expect(signals.bm25 > 0.0)
    }

    @Test
    func retrievalModeNeverConsultsTheModelEvenWhenOneIsConfigured() async throws {
        let model = ScriptedLanguageModel([#"{"ids":["glob"]}"#])
        let searcher = try await Searcher(Self.toolItems, model: model, mode: .retrieval)

        _ = try await searcher.search("search file contents with a regular expression", limit: 5)

        #expect(model.calls.isEmpty)
    }

    // MARK: - `.selection` mode, under budget: one prompt

    @Test
    func selectionModeUnderBudgetAsksTheConfiguredModelAndScoresThePickByItsOrder() async throws {
        let model = ScriptedLanguageModel([#"{"ids":["glob"]}"#])
        let searcher = try await Searcher(Self.toolItems, model: model, mode: .selection)

        let matches = try await searcher.search("find files by name", limit: 5)

        #expect(matches.map(\.id) == ["glob"])
        #expect(matches.first?.block == "Find files by name pattern, sorted by mtime")
        // The one prompt picks, and nothing ranks the catalog after it: the
        // pick carries its order score and no retrieval signals.
        #expect(matches.first?.score == OrderScores.firstPick)
        #expect(matches.first?.signals == nil)
        // The prefix is the instructions of the session, and the prompt is
        // the request block alone.
        let catalog = SearchCorpus(items: Self.toolItems)
        #expect(
            model.calls == [
                ScriptedModelCall(
                    instructions: SelectionTier.assemblePrefix(preamble: .selectionDefault, catalog: catalog),
                    prompt: ExpectedSelectionPrompt.request(for: "find files by name", ids: catalog.ids)
                )
            ]
        )
    }

    @Test
    func selectionModeMakesOneModelCallAndNeverEmbedsTheQuery() async throws {
        // `init` embeds every item in one call. A selection search asks the
        // model once and embeds nothing, so the count stays at that one call.
        let embedder = CountingEmbedder(vectorLength: Self.embeddingVectorLength)
        let model = ScriptedLanguageModel([#"{"ids":["watch"]}"#])
        let recorder = DiagnosticRecorder()
        let searcher = try await Searcher(
            Self.toolItems,
            embedder: embedder,
            model: model,
            mode: .selection,
            onDiagnostic: { recorder.record($0) }
        )
        let embedCallsAfterInit = embedder.callCount

        let matches = try await searcher.search("qqqq")

        #expect(matches.map(\.id) == ["watch"])
        #expect(model.calls.count == 1)
        #expect(embedder.callCount == embedCallsAfterInit)
        #expect(recorder.diagnostics.isEmpty)
    }

    @Test
    func swappingTheModelSwapsWhichModelAnswersSelection() async throws {
        // Two different scripted models -- proving the model is a plain
        // argument, never hardcoded, by getting each configuration's own
        // scripted answer back verbatim.
        let searcherA = try await Searcher(
            Self.toolItems,
            model: ScriptedLanguageModel([#"{"ids":["grep"]}"#]),
            mode: .selection
        )
        let searcherB = try await Searcher(
            Self.toolItems,
            model: ScriptedLanguageModel([#"{"ids":["watch"]}"#]),
            mode: .selection
        )

        let matchesA = try await searcherA.search("anything", limit: 5)
        let matchesB = try await searcherB.search("anything", limit: 5)

        #expect(matchesA.map(\.id) == ["grep"])
        #expect(matchesB.map(\.id) == ["watch"])
    }

    @Test
    func aModelErrorComesOutOfSearch() async throws {
        let searcher = try await Searcher(
            Self.toolItems,
            model: ScriptedLanguageModel(answers: [.failure]),
            mode: .selection
        )

        await #expect(throws: ScriptedLanguageModelError.scriptedFailure) {
            try await searcher.search("find files by name", limit: Self.resultLimit)
        }
    }

    // MARK: - `.selection` mode, over budget: one prompt per run of items

    @Test
    func selectionModeOverBudgetSendsEveryItemIdToExactlyOnePrompt() async throws {
        // Each prompt after the first answers with no id, so the merged
        // answer is the first prompt's pick alone.
        let model = ScriptedLanguageModel([#"{"ids":["alpha"]}"#] + Array(repeating: #"{"ids":[]}"#, count: Self.bulkItems.count))
        let searcher = try await Searcher(Self.bulkItems, model: model, mode: .selection)

        let matches = try await searcher.search("urgent alpha task")

        #expect(matches.map(\.id) == ["alpha"])
        #expect(matches.first?.score == OrderScores.firstPick)
        #expect(matches.first?.signals == nil)
        // The catalog does not fit one prompt, so it is split into several,
        // and every item reaches exactly one of them. The `id:` line is
        // matched whole, because `id: filler3` is a prefix of `id: filler30`.
        let instructions = model.calls.compactMap(\.instructions)
        #expect(instructions.count > 1)
        for item in Self.bulkItems {
            let promptsCarryingID = instructions.filter { $0.contains("\nid: \(item.id)\n") }
            #expect(promptsCarryingID.count == 1, "\(item.id) must reach exactly one prompt")
        }
    }

    @Test
    func selectionModeOverBudgetNeverEmbedsTheQueryAndReportsNoDiagnostic() async throws {
        let embedder = CountingEmbedder(vectorLength: Self.embeddingVectorLength)
        let recorder = DiagnosticRecorder()
        let searcher = try await Searcher(
            Self.bulkItems,
            embedder: embedder,
            model: ScriptedLanguageModel(Array(repeating: #"{"ids":["alpha"]}"#, count: Self.bulkItems.count)),
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
    func autoModeResolvesToSelectionWhenAModelIsConfigured() async throws {
        // Retrieval alone would rank "grep" first for this query (lexical
        // overlap with "search"/"regular expression"); scripting the
        // model to hand back "watch" instead proves `.auto` actually
        // drove the selection tier, not a retrieval fallback.
        let searcher = try await Searcher(
            Self.toolItems,
            model: ScriptedLanguageModel([#"{"ids":["watch"]}"#]),
            mode: .auto
        )

        let matches = try await searcher.search("search file contents with a regular expression", limit: 5)

        #expect(matches.map(\.id) == ["watch"])
        // The pick carries its order score and no retrieval signals: `.auto`
        // with a model runs no retrieval at all.
        #expect(matches.first?.score == OrderScores.firstPick)
        #expect(matches.first?.signals == nil)
    }

    @Test
    func autoModeWithAModelNeverEmbedsTheQueryOrReportsEmbeddingUnavailable() async throws {
        let embedder = CountingEmbedder(vectorLength: Self.embeddingVectorLength)
        let recorder = DiagnosticRecorder()
        let searcher = try await Searcher(
            Self.toolItems,
            embedder: embedder,
            model: ScriptedLanguageModel([#"{"ids":["watch"]}"#]),
            mode: .auto,
            onDiagnostic: { recorder.record($0) }
        )
        let embedCallsAfterInit = embedder.callCount

        _ = try await searcher.search("search file contents with a regular expression")

        #expect(embedder.callCount == embedCallsAfterInit)
        #expect(recorder.diagnostics.isEmpty)
    }

    @Test
    func autoModeDegradesToRetrievalWhenNoModelIsConfigured() async throws {
        let searcher = try await Searcher(Self.toolItems, model: nil, mode: .auto)

        let matches = try await searcher.search("search file contents with a regular expression", limit: 5)

        let first = try #require(matches.first)
        #expect(first.id == "grep")
        // Retrieval's fused ranking put the lexically closest item first --
        // proves `.auto` actually fell back rather than silently returning
        // nothing.
        #expect(first.score > 0.0)
        #expect(first.signals != nil)
    }

    @Test
    func theSystemModelGoesStraightInAsTheModelArgument() async throws {
        // A caller gives a FoundationModels model with no closure and no
        // type annotation. `.retrieval` mode answers with no model call, so
        // this test runs no inference.
        let searcher = try await Searcher(Self.toolItems, model: SystemLanguageModel.default, mode: .retrieval)

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
            model: nil,
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
            model: ScriptedLanguageModel([#"{"ids":["glob"]}"#]),
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
            embedder: FakeEmbedder(vectorLength: 8),
            model: nil,
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
            embedder: CountingEmbedder(vectorLength: 8, failingFromCall: queryEmbedCallNumber),
            model: nil,
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

    // MARK: - Degradation: the query vector and the item vectors differ in length

    @Test
    func aQueryVectorOfADifferentLengthDegradesToKeywordOnlyRetrievalAndReportsTheDiagnosticOncePerSearch() async throws {
        // The protocol declares no vector length, so only the vectors that
        // `embed(texts:)` returns tell their length. When the query vector and
        // the item vectors do not agree, cosine cannot score the items. The
        // search skips the cosine signal, keeps keyword retrieval, and
        // reports `.embeddingUnavailable` one time.
        let recorder = DiagnosticRecorder()
        let searcher = try await Searcher(
            Self.toolItems,
            embedder: MismatchedLengthEmbedder(
                batchVectorLength: Self.embeddingVectorLength,
                singleTextVectorLength: Self.mismatchedQueryVectorLength
            ),
            model: nil,
            mode: .retrieval,
            onDiagnostic: { recorder.record($0) }
        )

        let matches = try await searcher.search("search file contents with a regular expression", limit: 5)

        let first = try #require(matches.first)
        #expect(first.id == "grep")
        let signals = try #require(first.signals)
        #expect(signals.bm25 > 0.0)
        #expect(matches.allSatisfy { $0.signals?.cosine == 0.0 })
        #expect(recorder.diagnostics == [.embeddingUnavailable])
    }

    // MARK: - Degradation: a zeroed cosine weight is an opt-out, not a failure

    @Test
    func zeroCosineWeightOptsOutOfTheSignalWithoutReportingADiagnosticEvenWithNoEmbedder() async throws {
        let recorder = DiagnosticRecorder()
        let searcher = try await Searcher(
            Self.toolItems,
            embedder: nil,
            model: nil,
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
        let searcher = try await Searcher(Self.toolItems, model: nil, mode: .retrieval)

        let matches = try await searcher.search("search file contents with a regular expression", limit: 0)

        #expect(matches.isEmpty)
    }

    @Test
    func nonPositiveLimitReturnsEmptyInSelectionModeWithoutAPrompt() async throws {
        let model = ScriptedLanguageModel([#"{"ids":["grep"]}"#])
        let searcher = try await Searcher(Self.toolItems, model: model, mode: .selection)

        let matches = try await searcher.search("anything", limit: -1)

        #expect(matches.isEmpty)
        #expect(model.calls.isEmpty)
    }

    @Test
    func nonPositiveLimitReturnsEmptyInAutoModeWithoutAPrompt() async throws {
        let model = ScriptedLanguageModel([#"{"ids":["grep"]}"#])
        let searcher = try await Searcher(Self.toolItems, model: model, mode: .auto)

        let matches = try await searcher.search("anything", limit: 0)

        #expect(matches.isEmpty)
        #expect(model.calls.isEmpty)
    }

    // MARK: - Duplicate ids: first occurrence wins, never a crash

    @Test
    func duplicateItemIdKeepsTheFirstOccurrenceAndDropsLaterOnes() async throws {
        let items = [
            SearchItem(id: "grep", text: "the first, real grep description mentioning regular expressions"),
            SearchItem(id: "grep", text: "a later duplicate that should never be indexed"),
        ]
        let searcher = try await Searcher(items, model: nil, mode: .retrieval)

        let matches = try await searcher.search("regular expressions", limit: 5)

        #expect(matches.map(\.id) == ["grep"])
        #expect(matches.first?.block == "the first, real grep description mentioning regular expressions")
    }

    // MARK: - Degradation: `.selection` requested with no model configured

    @Test
    func selectionModeWithNoModelConfiguredThrowsSelectionTierUnavailable() async throws {
        let searcher = try await Searcher(Self.toolItems, model: nil, mode: .selection)

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
        let searcher = try await Searcher(tools, model: nil, mode: .retrieval)

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
