import FoundationModelsRanker
import Testing

/// Drives the `Searcher` facade with no `model:` argument at all against a
/// live `SystemLanguageModel`, so a run needs a Mac with Apple Intelligence
/// turned on.
///
/// Every hermetic test in the root package gives `Searcher.init` a scripted
/// model, so not one of them runs the model the facade uses on its own. That
/// model is `SystemLanguageModel.default`, the default value of the `model:`
/// parameter, and it is what the README's lead example and this package's
/// front door both run on. This suite is the only place the default runs.
///
/// Nothing selects between the hermetic tests and this one at run time. This
/// target lives only in the nested `IntegrationTests` package, so `swift
/// test` at the repository root cannot see it, and `swift test --package-path
/// IntegrationTests` runs it.
@Suite("The zero-config Searcher on the live system model")
struct ZeroConfigSearcherRealModelTests {
    /// How many matches each search asks for.
    ///
    /// This limit leaves the model room to name more than one tool.
    private static let matchLimit = 5

    /// `Searcher(items)` with no `model:` argument must answer every query
    /// in `developerToolQueries` from a session that has answered nothing yet.
    ///
    /// The initializer takes `SystemLanguageModel.default` for `model:`, and
    /// the selection tier makes a `LanguageModelSession` on that model for
    /// each prompt. Only a real model can answer it, so only this target can
    /// hold the claim.
    ///
    /// **Every query gets its own `Searcher`**, so every search runs on a
    /// cold session — the state `Searcher(items)` starts every caller in. A
    /// caller that asks one question is the common case, and one warm session
    /// answering four questions in a row hides what a cold one does. In a
    /// measurement with the intent sent bare, "record my staged changes as a
    /// new commit" answered 0 of 5 cold runs and "how do I list or delete a
    /// branch" answered 3 of 5, while the other two answered 5 of 5. Both
    /// failing queries read as an order to the model itself rather than as a
    /// task to select candidates for, and a cold session has no earlier turn
    /// to tell the two apart. For this reason
    /// `SelectionTier.prompt(intent:ids:)` puts the intent in a `<request>`
    /// block. The test runs every query, not only one, so that a change to
    /// the wording cannot fix one query's answer and break another's.
    ///
    /// The test makes no claim about which id comes back. A live model can
    /// word a correct pick differently from one run to the next, and a claim
    /// about one id would fail on a rephrasing that is just as correct. It
    /// claims only that some catalog id came back, and that the tier reported
    /// no `.unknownSelectedId`.
    ///
    /// That pair also guards against a candidate prefix that shows the model
    /// no ids. With no ids, the model can answer only with words that name
    /// nothing in the candidate set. The tier then reports `.unknownSelectedId`
    /// for each such answer, drops it, and gives back no match for every
    /// query. A hermetic test cannot see that, because a scripted model
    /// answers with an id whatever the prefix holds.
    ///
    /// `.embeddingUnavailable` does fire on every search, because no embedder
    /// is configured. That is the documented degradation, not a defect, so
    /// the test passes over it.
    ///
    /// - Parameter query: the catalog query this case asks, cold.
    @Test(
        "Searcher(items) with no model argument answers every catalog query on a cold session",
        arguments: developerToolQueries
    )
    func searcherWithNoModelArgumentAnswersEveryCatalogQueryOnAColdSession(query: String) async throws {
        let searcher = try await Searcher(
            developerToolCatalog,
            onDiagnostic: { diagnostic in
                guard case .unknownSelectedId = diagnostic else { return }
                Issue.record("The searcher reported \(diagnostic).")
            }
        )

        let matches = try await searcher.search(query, limit: Self.matchLimit)

        #expect(!matches.isEmpty)
        #expect(matches.allSatisfy { match in developerToolCatalog.contains { $0.id == match.id } })
    }
}
