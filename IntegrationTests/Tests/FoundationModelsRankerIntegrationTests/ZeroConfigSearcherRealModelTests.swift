import FoundationModelsRanker
import FullMontyCore
import Testing

/// Drives the `Searcher` facade with no `session:` argument at all against a
/// live `SystemLanguageModel`, so a run needs a Mac with Apple Intelligence
/// turned on.
///
/// Every hermetic test in the root package gives `Searcher.init` a scripted
/// `AgentSession`, so not one of them builds the session the facade builds on
/// its own. That session comes from `Searcher.defaultSessionFactory`, the
/// default value of the `session:` parameter, and it is what the README's
/// lead example and this package's front door both run on. This suite is the
/// only place the default runs.
///
/// Nothing selects between the hermetic tests and this one at run time. This
/// target lives only in the nested `IntegrationTests` package, so `swift
/// test` at the repository root cannot see it, and `swift test --package-path
/// IntegrationTests` runs it.
@Suite("The zero-config Searcher on the live system model")
struct ZeroConfigSearcherRealModelTests {
    /// How many matches each search asks for.
    ///
    /// The same limit `FullMonty` itself gives, which leaves the model room
    /// to name more than one tool.
    private static let matchLimit = 5

    /// `Searcher(items)` with no `session:` argument must answer every demo
    /// query from a session that has answered nothing yet.
    ///
    /// The initializer takes `Searcher.defaultSessionFactory` for `session:`,
    /// and that factory makes a `LanguageModelSession` on the on-device
    /// system model. Only a real model can answer it, so only this target can
    /// hold the claim.
    ///
    /// **Every query gets its own `Searcher`**, so every search runs on a
    /// cold session — the state `Searcher(items)` starts every caller in. A
    /// caller that asks one question is the common case, and one warm session
    /// answering four questions in a row hides what a cold one does. Task
    /// `^5pg59d2` measured that difference: with the intent sent bare, "record
    /// my staged changes as a new commit" answered 0 of 5 cold runs and "how
    /// do I list or delete a branch" answered 3 of 5, while the other two
    /// answered 5 of 5. Both failing queries read as an order to the model
    /// itself rather than as a task to select candidates for, and a cold
    /// session has no earlier turn to tell the two apart.
    /// `SelectionTier.prompt(prefix:intent:)` now puts every intent under a
    /// `# Task` heading, and all four queries answered 5 of 5 cold. Running
    /// every query, not just the one that failed, is what keeps a later
    /// wording change from trading one query's answer for another's.
    ///
    /// The test makes no claim about which id comes back. A live model can
    /// word a correct pick differently from one run to the next, and a claim
    /// about one id would fail on a rephrasing that is just as correct. It
    /// claims only that some catalog id came back, and that the tier reported
    /// no `.unknownSelectedId`.
    ///
    /// That pair is also the regression guard for the defect commit `cbcee8c`
    /// corrected. The assembled candidate prefix showed the model no ids at
    /// all, so the model could answer only with words that named nothing in
    /// the candidate set. The tier reported `.unknownSelectedId` for each such
    /// answer, dropped it, and gave back no match for every query. A hermetic
    /// test could not see that, because a scripted session answers with an id
    /// whatever the prefix holds.
    ///
    /// `.embeddingUnavailable` does fire on every search, because no embedder
    /// is configured. That is the documented degradation, not a defect, so
    /// the test passes over it.
    ///
    /// - Parameter query: the demo query this case asks, cold.
    @Test(
        "Searcher(items) with no session argument answers every demo query on a cold session",
        arguments: demoQueries
    )
    func searcherWithNoSessionArgumentAnswersEveryDemoQueryOnAColdSession(query: String) async throws {
        let searcher = try await Searcher(
            toolCatalog,
            onDiagnostic: { diagnostic in
                guard case .unknownSelectedId = diagnostic else { return }
                Issue.record("The searcher reported \(diagnostic).")
            }
        )

        let matches = try await searcher.search(query, limit: Self.matchLimit)

        #expect(!matches.isEmpty)
        #expect(matches.allSatisfy { match in toolCatalog.contains { $0.id == match.id } })
    }
}
