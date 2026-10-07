import Foundation
import FoundationModels
import Testing

@testable import FoundationModelsRanker

/// Tests for the selection tier's under-budget path: one new session for
/// each search, with the assembled prefix as its instructions and the
/// request block as its prompt, one model call and no retrieval pass per
/// search, the summary-vs-full block separation (`summaryBlock(forID:)`
/// seeds the prefix; `block(forID:)` is what a `SelectionMatch` carries back
/// verbatim), ids-only decoding, verbatim lookup by id, order scores, and
/// unknown-id filtering + diagnostic.
///
/// The tests drive `SelectionTier` directly over a scripted FoundationModels
/// model (`Support/ScriptedLanguageModel.swift`) and a
/// `FixtureSelectionCatalog` (`Support/FixtureSelectionCatalog.swift`) —
/// zero GPU, no download. The over-budget path is covered in
/// `OverBudgetTests`.
struct SelectionTests {
    // MARK: - Fixtures

    static let catalog = FixtureSelectionCatalog([
        .init(id: "deploy", block: "ships containers to a kubernetes cluster"),
        .init(id: "rollback", block: "reverts the last release"),
    ])

    /// Three items whose summaries share no text with their ids, so a
    /// prefix assertion that finds an id proves the prefix renders the id
    /// itself -- not a summary that happens to spell it.
    static let threeItemCatalog = FixtureSelectionCatalog([
        .init(id: "deploy", block: "the full deploy block", summary: "ships containers to a cluster"),
        .init(id: "rollback", block: "the full rollback block", summary: "reverts the last release"),
        .init(id: "status", block: "the full status block", summary: "reports the current release state"),
    ])

    /// The `limit` the searches in this file ask for: more than the catalog
    /// holds, so no test truncates by accident.
    static let resultLimit = 5

    /// Makes a tier over `catalog` that asks `model`, with the default
    /// preamble and budget.
    ///
    /// - Parameters:
    ///   - model: the scripted model that answers each prompt.
    ///   - catalog: the catalog of the tier. Defaults to `catalog`.
    ///   - onDiagnostic: called for every diagnostic the tier emits.
    ///     Defaults to doing nothing.
    /// - Returns: the tier.
    private static func tier(
        _ model: ScriptedLanguageModel,
        catalog: any SelectionCatalog = Self.catalog,
        onDiagnostic: @escaping @Sendable (RankDiagnostic) -> Void = { _ in }
    ) -> SelectionTier {
        SelectionTier(catalog: catalog, config: SelectionConfig(model: model), onDiagnostic: onDiagnostic)
    }

    // MARK: - One new session for each prompt

    @Test
    func eachPromptHasThePrefixAsInstructionsAndTheRequestBlockAsItsPrompt() async throws {
        // The prefix is the instructions of the session, so the prompt
        // carries no prefix: only the `<request>` block and the exact-id
        // line. The block says the message is a request to select for, not
        // a task to do, and a session that has answered nothing yet has
        // nothing else to tell it from an order.
        let model = ScriptedLanguageModel([#"{"ids":["deploy"]}"#])
        let tier = Self.tier(model)

        _ = try await tier.search(intent: "roll back the last deploy", limit: Self.resultLimit)

        let prefix = SelectionTier.assemblePrefix(preamble: .selectionDefault, catalog: Self.catalog)
        let request = ExpectedSelectionPrompt.request(for: "roll back the last deploy", ids: Self.catalog.ids)
        #expect(model.calls == [ScriptedModelCall(instructions: prefix, prompt: request)])
    }

    @Test
    func eachSearchPromptsANewSessionThatSeesNoEarlierTurn() async throws {
        // Each search makes its own session, so the second prompt's
        // transcript holds its own request and not the turn of the first.
        let model = ScriptedLanguageModel([#"{"ids":["deploy"]}"#, #"{"ids":["rollback"]}"#])
        let tier = Self.tier(model)

        let first = try await tier.search(intent: "first task", limit: Self.resultLimit)
        let second = try await tier.search(intent: "second task", limit: Self.resultLimit)

        let prefix = SelectionTier.assemblePrefix(preamble: .selectionDefault, catalog: Self.catalog)
        #expect(
            model.calls == ["first task", "second task"].map { intent in
                ScriptedModelCall(
                    instructions: prefix,
                    prompt: ExpectedSelectionPrompt.request(for: intent, ids: Self.catalog.ids)
                )
            }
        )
        #expect(first.map(\.id) == ["deploy"])
        #expect(second.map(\.id) == ["rollback"])
    }

    @Test
    func aModelErrorComesOutOfSearch() async throws {
        let tier = Self.tier(ScriptedLanguageModel(answers: [.failure]))

        await #expect(throws: ScriptedLanguageModelError.scriptedFailure) {
            try await tier.search(intent: "ship the release", limit: Self.resultLimit)
        }
    }

    // MARK: - One prompt that picks

    @Test
    func underBudgetSearchMakesExactlyOneModelCall() async throws {
        // The one prompt is the whole search: the answer is the result, and
        // nothing ranks the catalog after it.
        let model = ScriptedLanguageModel([#"{"ids":["deploy"]}"#])
        let tier = Self.tier(model)

        let matches = try await tier.search(intent: "ship the release", limit: Self.resultLimit)

        #expect(model.calls.count == 1)
        #expect(matches.map(\.id) == ["deploy"])
    }

    @Test
    func selectionScoresFollowTheModelsOrder() async throws {
        // The model's order is the result's order, and each pick's score is
        // the reciprocal of its rank: no retrieval signal enters a selection.
        let model = ScriptedLanguageModel([#"{"ids":["status","deploy","rollback"]}"#])
        let tier = Self.tier(model, catalog: Self.threeItemCatalog)

        let matches = try await tier.search(intent: "task", limit: Self.resultLimit)

        #expect(matches.map(\.id) == ["status", "deploy", "rollback"])
        #expect(matches.map(\.score) == [OrderScores.firstPick, OrderScores.secondPick, OrderScores.thirdPick])
        #expect(matches.allSatisfy { $0.signals == nil })
    }

    @Test
    func thePromptNamesOnlyTheIdsThatThePrefixShows() async throws {
        // The prefix leaves out an id that has no summary block, so the list
        // of id choices must leave it out too: the model must not read an id
        // that it has no description for.
        let model = ScriptedLanguageModel([#"{"ids":["deploy"]}"#])
        let tier = Self.tier(model, catalog: CatalogWithAnUnsummarizedID())

        _ = try await tier.search(intent: "ship the release", limit: Self.resultLimit)

        let request = ExpectedSelectionPrompt.request(for: "ship the release", ids: ["deploy"])
        #expect(model.calls.map(\.prompt) == [request])
    }

    // MARK: - Summary vs full block separation

    @Test
    func sessionPrefixUsesSummaryBlockWhileMatchesCarryTheFullBlock() async throws {
        let catalog = FixtureSelectionCatalog([
            .init(id: "deploy", block: "the full, long rendered block text", summary: "short summary")
        ])
        let model = ScriptedLanguageModel([#"{"ids":["deploy"]}"#])
        let tier = Self.tier(model, catalog: catalog)

        let matches = try await tier.search(intent: "task", limit: Self.resultLimit)

        let instructions = try #require(model.calls.first?.instructions)
        #expect(instructions.contains("short summary"))
        #expect(!instructions.contains("the full, long rendered block text"))

        let match = try #require(matches.first)
        #expect(match.block == "the full, long rendered block text")
        // A selection pick carries its order score and no retrieval signals.
        #expect(match.score == OrderScores.firstPick)
        #expect(match.signals == nil)
    }

    // MARK: - Candidate ids in the assembled prefix

    @Test
    func assemblePrefixRendersEveryCandidateIdWithItsSummary() throws {
        let catalog = Self.threeItemCatalog

        let prefix = SelectionTier.assemblePrefix(preamble: .selectionDefault, catalog: catalog)

        for id in catalog.ids {
            #expect(prefix.contains(id))
            let summary = try #require(catalog.summaryBlock(forID: id))
            #expect(prefix.contains(summary))
        }
    }

    @Test
    func aUriIdRendersAsACandidateBlockWithLabeledIdAndDescriptionLines() {
        // A real model shortened a URI id to its last path part when the id
        // was a `## <id>` heading, because a heading reads like a title. The
        // id now stands on its own `id:` line, with nothing else on it.
        let id = "https://example.com/modules/quantum-flux-capacitor"
        let summary = "Provides quantum flux capacitor calibration routines."
        let catalog = FixtureSelectionCatalog([.init(id: id, block: "the full block", summary: summary)])

        let prefix = SelectionTier.assemblePrefix(preamble: "PREAMBLE", catalog: catalog)

        #expect(prefix == "PREAMBLE\n\n<candidate>\nid: \(id)\ndescription: \(summary)\n</candidate>")
    }

    @Test
    func candidateBlocksAreSeparatedByOneBlankLine() {
        let prefix = SelectionTier.assemblePrefix(preamble: "PREAMBLE", catalog: Self.threeItemCatalog)

        let expected = """
            PREAMBLE

            <candidate>
            id: deploy
            description: ships containers to a cluster
            </candidate>

            <candidate>
            id: rollback
            description: reverts the last release
            </candidate>

            <candidate>
            id: status
            description: reports the current release state
            </candidate>
            """
        #expect(prefix == expected)
    }

    @Test
    func theIdsGuideAsksForTheExactIdCopiedFromItsIdLine() throws {
        // A guided-generation backend shows the model this text beside the
        // `ids` field, so it must repeat the exact-id rule of the preamble.
        let data = try JSONEncoder().encode(Selection.generationSchema)
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let properties = try #require(root["properties"] as? [String: Any])
        let idsSchema = try #require(properties["ids"] as? [String: Any])

        #expect(
            idsSchema["description"] as? String
                == "the exact id of each chosen candidate, copied character for character from its id: line; "
                + "empty only when no candidate is related to the request"
        )
    }

    @Test
    func theSessionInstructionsCarryEveryCatalogId() async throws {
        let model = ScriptedLanguageModel([#"{"ids":["deploy"]}"#])
        let tier = Self.tier(model)

        _ = try await tier.search(intent: "task", limit: Self.resultLimit)

        // The preamble tells the model to copy each id exactly and not to
        // make one up, so the prefix must show it the ids it can return.
        let instructions = try #require(model.calls.first?.instructions)
        for id in Self.catalog.ids {
            #expect(instructions.contains(id))
        }
    }

    // MARK: - Ids-only decode + verbatim lookup identity

    @Test
    func selectionDecodesIdsOnlyAndMatchesCarryVerbatimCatalogBlocks() async throws {
        let tier = Self.tier(ScriptedLanguageModel([#"{"ids":["rollback","deploy"]}"#]))

        let matches = try await tier.search(intent: "roll back the last deploy", limit: Self.resultLimit)

        #expect(matches.map(\.id) == ["rollback", "deploy"])
        #expect(matches.map(\.block) == ["reverts the last release", "ships containers to a kubernetes cluster"])
        // Every match is scored by its place in the model's own call order.
        #expect(matches.map(\.score) == [OrderScores.firstPick, OrderScores.secondPick])
        #expect(matches.allSatisfy { $0.signals == nil })
    }

    @Test
    func selectionResultsAreTruncatedToLimit() async throws {
        let tier = Self.tier(ScriptedLanguageModel([#"{"ids":["rollback","deploy"]}"#]))

        let matches = try await tier.search(intent: "roll back the last deploy", limit: 1)

        #expect(matches.map(\.id) == ["rollback"])
    }

    // MARK: - Duplicate id handling: first occurrence wins, no diagnostic

    @Test
    func duplicateIdFromAMisbehavingModelIsDeduplicatedWithoutADiagnostic() async throws {
        let recorder = DiagnosticRecorder()
        let tier = Self.tier(
            ScriptedLanguageModel([#"{"ids":["deploy","deploy","rollback"]}"#]),
            onDiagnostic: { recorder.record($0) }
        )

        let matches = try await tier.search(intent: "task", limit: Self.resultLimit)

        #expect(matches.map(\.id) == ["deploy", "rollback"])
        #expect(recorder.diagnostics.isEmpty)
    }

    @Test
    func duplicateIdDoesNotConsumeALimitSlotAndCrowdOutALaterLegitimateMatch() async throws {
        // A tight `limit` of 2 against 3 model-returned ids (one a repeat):
        // if the duplicate consumed a slot the way an unfiltered append
        // would, this would truncate to just ["deploy"]. Deduplication must
        // let "rollback" through instead.
        let tier = Self.tier(ScriptedLanguageModel([#"{"ids":["deploy","deploy","rollback"]}"#]))

        let matches = try await tier.search(intent: "task", limit: 2)

        #expect(matches.map(\.id) == ["deploy", "rollback"])
    }

    // MARK: - Zero-ids model response ("nothing fits")

    @Test
    func emptyIdsModelResponseReturnsEmptyMatchesWithNoDiagnostic() async throws {
        let recorder = DiagnosticRecorder()
        let tier = Self.tier(ScriptedLanguageModel([#"{"ids":[]}"#]), onDiagnostic: { recorder.record($0) })

        let matches = try await tier.search(intent: "nothing matches this", limit: Self.resultLimit)

        #expect(matches.isEmpty)
        #expect(recorder.diagnostics.isEmpty)
    }

    // MARK: - Empty catalog

    @Test
    func emptyCatalogSearchReturnsNoMatchesAndSendsNoPrompt() async throws {
        // A catalog of zero items has no id to select. A prompt over it is
        // the preamble and no candidate block, and a real model answers that
        // prompt with prose that does not decode. Thus the tier must not
        // call the model at all.
        let model = ScriptedLanguageModel([#"{"ids":[]}"#])
        let tier = Self.tier(model, catalog: FixtureSelectionCatalog([]))

        let matches = try await tier.search(intent: "anything", limit: Self.resultLimit)

        #expect(matches.isEmpty)
        #expect(model.calls.isEmpty)
    }

    // MARK: - Unknown id filtering + diagnostic

    @Test
    func unknownIdFromAMisbehavingModelIsFilteredAndReportedAsADiagnostic() async throws {
        // Guided generation limits the answer to the shape of `Selection`,
        // not to the candidate ids, so nothing stops a model from answering
        // with an id the catalog does not hold. This filter is the
        // backstop. Two unknown ids sit between two real ones, so the test
        // proves the filter drops each unknown id, reports it, and still
        // keeps every real id that follows.
        let recorder = DiagnosticRecorder()
        let tier = Self.tier(
            ScriptedLanguageModel([#"{"ids":["deploy","not-a-real-id","rollback","also-not-a-real-id"]}"#]),
            onDiagnostic: { recorder.record($0) }
        )

        let matches = try await tier.search(intent: "task", limit: Self.resultLimit)

        #expect(matches.map(\.id) == ["deploy", "rollback"])
        #expect(
            recorder.diagnostics == [
                .unknownSelectedId(id: "not-a-real-id"),
                .unknownSelectedId(id: "also-not-a-real-id"),
            ]
        )
    }

    @Test
    func anItemSummaryAnsweredInPlaceOfItsIdIsFilteredAndReportedAsUnknown() async throws {
        // A failure mode measured on a real model: a model that answers with
        // an item's summary text instead of its id. Nothing resolves that
        // text, so no match comes back and the tier reports it. This pins
        // the backstop for that case.
        let recorder = DiagnosticRecorder()
        let summary = try #require(Self.catalog.summaryBlock(forID: "deploy"))
        let tier = Self.tier(ScriptedLanguageModel([#"{"ids":["\#(summary)"]}"#]), onDiagnostic: { recorder.record($0) })

        let matches = try await tier.search(intent: "task", limit: Self.resultLimit)

        #expect(matches.isEmpty)
        #expect(recorder.diagnostics == [.unknownSelectedId(id: summary)])
    }

    // MARK: - `limit <= 0` short-circuits without a prompt

    @Test
    func nonPositiveLimitReturnsEmptyWithoutAPrompt() async throws {
        let model = ScriptedLanguageModel([#"{"ids":["deploy"]}"#])
        let tier = Self.tier(model)

        let matches = try await tier.search(intent: "task", limit: 0)

        #expect(matches.isEmpty)
        #expect(model.calls.isEmpty)
    }
}

/// A catalog with two ids. The id `deploy` has a summary block. The id
/// `archived` has a block but no summary block, so the assembled prefix
/// leaves it out.
private struct CatalogWithAnUnsummarizedID: SelectionCatalog {
    let ids = ["deploy", "archived"]

    func summaryBlock(forID id: String) -> String? {
        id == "deploy" ? "ships containers to a cluster" : nil
    }

    func block(forID id: String) -> String? {
        ids.contains(id) ? "the full \(id) block" : nil
    }
}
