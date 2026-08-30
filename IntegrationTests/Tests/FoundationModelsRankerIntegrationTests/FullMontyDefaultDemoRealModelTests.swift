import FullMontyCore
import Testing

/// Drives `FullMonty`'s default path against a live `SystemLanguageModel`, so
/// a run needs a Mac with Apple Intelligence turned on.
///
/// The root package's `ExamplesSmokeTests` drives every other path of the
/// same demo: `--no-model`, `--embedder`, and the selection tier with a
/// scripted `AgentSession`. Not one of them reaches a model. `runDefaultDemo`
/// is the path that has no flag, and it gives `Searcher` the on-device system
/// model through `Searcher.defaultSessionFactory`, so it belongs here.
///
/// Nothing selects between the two suites at run time. This target lives only
/// in the nested `IntegrationTests` package, so `swift test` at the
/// repository root cannot see it, and `swift test --package-path
/// IntegrationTests` runs it.
@Suite("The FullMonty default path on the live system model")
struct FullMontyDefaultDemoRealModelTests {
    /// `runDefaultDemo` must answer every demo query, in order.
    ///
    /// The claim is about the shape of the run, not about what the model
    /// picked: one `FullMontyResult` per `demoQueries` entry, each result
    /// carrying the query it answers. A live model words a correct pick
    /// differently from one run to the next, so a claim about the ids in
    /// those results could fail on an answer that is just as correct.
    ///
    /// The call gives no `onDiagnostic` argument, so the demo's own default
    /// handler takes every diagnostic the run reports -- and this path
    /// reports one, `.embeddingUnavailable`, on each query, because it
    /// configures no embedder.
    @Test("runDefaultDemo answers every demo query on the on-device system model")
    func runDefaultDemoAnswersEveryDemoQuery() async throws {
        let results = try await runDefaultDemo()

        #expect(results.map(\.query) == demoQueries)
    }
}
