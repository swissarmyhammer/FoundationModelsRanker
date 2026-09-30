import FoundationModelsExtras
import FoundationModelsRanker
import os
import Testing

/// Proves that the pooled types of FoundationModelsExtras plug into this
/// package with no consumer code: `PooledSession` is an `AgentSession`, and
/// `PooledEmbedder` is a `TextEmbedding`.
///
/// Each test makes a `ModelPool(loader:)` with a ``StubModelLoader``, so the
/// pooled types load a stub in place of an MLX model. The tests need no GPU
/// and no download.
///
/// This file imports `FoundationModelsRanker` without `@testable`, so the
/// conformances are reached through the public surface only, the same surface
/// that an outside package gets.
@Suite("Pooled conformances")
struct PooledConformanceTests {
    /// The Hugging Face name of the stub LLM.
    private static let chatModel: ModelRef = "org/stub-chat"

    /// The Hugging Face name of the stub embedding model.
    private static let embeddingModel: ModelRef = "org/stub-embedding"

    /// The id that the stub LLM selects.
    private static let selectedID = "grep"

    /// The answer of the stub LLM: a `Selection` as JSON.
    private static let selectionJSON = #"{"ids": ["\#(selectedID)"]}"#

    /// The two queries of the selection test. Two queries prove that the
    /// second query does not see the turn of the first.
    private static let queries = [
        "search file contents with a regular expression",
        "find a TODO comment in my code",
    ]

    /// The largest number of matches that one search returns.
    private static let matchLimit = 5

    /// The prompt that the cached-root path sends for `query`. The prefix is
    /// the instructions of the root session, so the prompt holds only the
    /// `# Task` heading and the query.
    ///
    /// - Parameter query: The search intent.
    /// - Returns: The prompt text.
    private static func taskPrompt(for query: String) -> String {
        "# Task\n\n\(query)"
    }

    @Test("A SelectionTier over a PooledModel factory selects ids and forks the pooled root for each query")
    func aSelectionTierOverAPooledModelForksTheRootForEachQuery() async throws {
        let script = StubLanguageModelScript(answer: Self.selectionJSON)
        let pool = ModelPool(loader: StubModelLoader(container: StubLanguageModel(script: script)))
        let model = PooledModel(ref: Self.chatModel, pool: pool)
        let factoryCalls = OSAllocatedUnfairLock(initialState: 0)
        let config = SelectionConfig(model: { instructions in
            factoryCalls.withLock { $0 += 1 }
            return try await model.session(instructions: instructions)
        })
        let tier = SelectionTier(
            catalog: SearchCorpus(items: SearcherTests.toolItems),
            config: config,
            onDiagnostic: { _ in }
        )

        var selectedIDs: [[String]] = []
        for query in Self.queries {
            selectedIDs.append(try await tier.search(intent: query, limit: Self.matchLimit).map(\.id))
        }

        #expect(selectedIDs == Self.queries.map { _ in [Self.selectedID] })
        // The factory made one root session, and the prefix went into it one
        // time, as its instructions.
        #expect(factoryCalls.withLock { $0 } == 1)
        // Each query ran on a fork of the root: its transcript holds its own
        // prompt and not the prompt of the query before it. Each call also
        // carried the schema, so `respond(to:generating:)` reached the native
        // guided generation of `PooledSession` through `any AgentSession`.
        #expect(
            script.calls == Self.queries.map { query in
                StubGenerationCall(prompts: [Self.taskPrompt(for: query)], isGuided: true)
            }
        )
    }

    @Test("A PooledEmbedder on a stub loader drives the cosine signal of the hybrid ranking")
    func aPooledEmbedderDrivesTheCosineSignal() async throws {
        let pool = ModelPool(loader: StubModelLoader(container: ConstantPooledEmbedding()))
        let embedder: any TextEmbedding = PooledEmbedder(ref: Self.embeddingModel, pool: pool)
        let recorder = DiagnosticRecorder()

        let searcher = try await Searcher(
            SearcherTests.toolItems,
            embedder: embedder,
            session: nil,
            mode: .retrieval,
            onDiagnostic: recorder.record
        )
        let matches = try await searcher.search(Self.queries[0], limit: Self.matchLimit)

        #expect(recorder.diagnostics.isEmpty)
        let first = try #require(matches.first)
        let signals = try #require(first.signals)
        #expect(signals.cosine > 0.0)
    }
}

/// A stub embedding container for a `ModelPool`: it gives the same unit
/// vector for each text.
///
/// Equal vectors have a cosine similarity of one, so each item gets a cosine
/// score above zero. That is enough to show that the vectors of the pooled
/// embedder reached the fusion.
private struct ConstantPooledEmbedding: PooledEmbedding {
    /// The unit vector that each text gets.
    private static let unitVector: [Float] = [1, 0]

    /// The length of each vector.
    var dimension: Int { Self.unitVector.count }

    /// Gives ``unitVector`` for each text.
    ///
    /// - Parameter texts: The texts.
    /// - Returns: One copy of ``unitVector`` for each text.
    func embed(texts: [String]) async throws -> [[Float]] {
        texts.map { _ in Self.unitVector }
    }
}
