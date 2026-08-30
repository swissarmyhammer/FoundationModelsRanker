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
    /// The query the test asks.
    ///
    /// `FullMontyCore`'s `toolCatalog` holds one tool that searches file
    /// contents with regular expressions, `grep`, and the query repeats that
    /// tool's own wording, so the answer is not in doubt. The test still
    /// makes no claim about which id comes back: a live model can word a
    /// correct pick differently from one run to the next, and a claim about
    /// one id would fail on a rephrasing that is just as correct.
    ///
    /// The search runs on a session that has answered nothing yet, which is
    /// the state `Searcher(items)` starts every caller in. Not every demo
    /// query answers from that state: "record my staged changes as a new
    /// commit" gives the model no id at all on a cold session, and answers
    /// `commit` only after the same session has answered an earlier query.
    /// `FullMonty` runs four queries in a row on one session and so never
    /// meets that, but a test that asks one question does, and this query is
    /// one the model answers cold.
    private static let query = "search file contents for a pattern using a regular expression"

    /// How many matches the search asks for.
    ///
    /// The same limit `FullMonty` itself gives, which leaves the model room
    /// to name more than one tool.
    private static let matchLimit = 5

    /// `Searcher(items)` with no `session:` argument must answer through the
    /// on-device system model.
    ///
    /// The initializer takes `Searcher.defaultSessionFactory` for `session:`,
    /// and that factory makes a `LanguageModelSession` on the on-device
    /// system model. Only a real model can answer it, so only this target can
    /// hold the claim.
    ///
    /// The test guards the defect that commit `cbcee8c` corrected. The
    /// assembled candidate prefix showed the model no ids at all, so the
    /// model could answer only with words that named nothing in the candidate
    /// set. The tier reported `.unknownSelectedId` for each such answer,
    /// dropped it, and gave back no match for every query. A hermetic test
    /// could not see the defect, because a scripted session answers with an
    /// id whatever the prefix holds. A match together with no
    /// `.unknownSelectedId` is therefore the regression guard: the prefix
    /// showed the model the ids, and the model answered with one of them.
    ///
    /// `.embeddingUnavailable` does fire on this search, because no embedder
    /// is configured. That is the documented degradation, not a defect, so
    /// the test passes over it.
    @Test("Searcher(items) with no session argument answers through the on-device system model")
    func searcherWithNoSessionArgumentAnswersThroughTheOnDeviceSystemModel() async throws {
        let searcher = try await Searcher(
            toolCatalog,
            onDiagnostic: { diagnostic in
                guard case .unknownSelectedId = diagnostic else { return }
                Issue.record("The searcher reported \(diagnostic).")
            }
        )

        let matches = try await searcher.search(Self.query, limit: Self.matchLimit)

        #expect(!matches.isEmpty)
        #expect(matches.allSatisfy { match in toolCatalog.contains { $0.id == match.id } })
    }
}
