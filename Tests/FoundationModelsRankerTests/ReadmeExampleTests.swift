import Foundation
import FoundationModelsExtras
import Testing

@testable import FoundationModelsRanker

/// Exercises the exact shape of the code examples in `README.md` and
/// `docs/GUIDE.md` against doubles (never a live model or a download), so a
/// change to `Searcher`'s public surface breaks this test before it breaks a
/// reader who pastes an example into their own project.
///
/// One test stands for each Swift block of the README, in the order the
/// README gives them, and then one test for each Swift block of the guide,
/// in the order the guide gives them. The `## Install` block is the one block
/// no test can compile, and its own test states why.
///
/// Reuses `SearcherTests.toolItems`'s grep/glob/watch fixture -- the same
/// three-item list the README's lead example itself lists. A pooled block
/// runs its `PooledModel` or `PooledEmbedder` on a `ModelPool` with a
/// `StubModelLoader`, so the pool gives a double in place of an MLX model.
@Suite("README and guide examples")
struct ReadmeExampleTests {
    /// The Hugging Face name of the LLM in the README and the guide.
    private static let chatModel: ModelRef = "mlx-community/Qwen3-4B-4bit"

    /// The Hugging Face name of the embedding model in the README and the
    /// guide.
    private static let embeddingModel: ModelRef = "mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ"

    /// The length of each vector of the stub embedding model.
    private static let stubVectorLength = 8

    /// README's lead example: a `SearchItem` list, `Searcher(items)`, one
    /// `search(...)` call.
    ///
    /// The README's own zero-config call omits `model:`, which defaults to
    /// `SystemLanguageModel.default` -- unusable here without Apple
    /// Intelligence, so this test gives a scripted model in its place, with
    /// the identical initializer and `search(_:limit:)` call shape the README
    /// documents.
    ///
    /// `mode` is left at its `.auto` default (as the README's own call
    /// does), so this resolves to `.selection`. This three-item list stays
    /// under `SelectionConfig.defaultCapacityCharacterLimit`, so one prompt
    /// picks and the pick carries its order `score` and no retrieval
    /// `signals`.
    @Test("The lead example's SearchItem list and Searcher(items).search(...) call find grep first")
    func leadExampleFindsGrepForATodoCommentsQuery() async throws {
        let items = SearcherTests.toolItems

        let searcher = try await Searcher(items, model: ScriptedLanguageModel([#"{"ids":["grep"]}"#]))

        let hits = try await searcher.search("how do I find TODO comments in my code")

        let first = try #require(hits.first)
        #expect(first.id == "grep")
        // The pick is the model's first, so it carries the first order
        // score and no retrieval signals.
        #expect(first.score == OrderScores.firstPick)
        #expect(first.signals == nil)
    }

    /// README's `## Install` block: the `.package(url:)` line a consumer
    /// adds to their own `Package.swift`.
    ///
    /// This is the one Swift block the suite cannot compile. The block is a
    /// manifest fragment, and SwiftPM gives no target the
    /// `PackageDescription` module the fragment needs, so there is nothing
    /// to compile it against here. The test pins what the block can really
    /// get wrong instead: the repository its URL names, held against the
    /// package name `Package.swift` itself declares.
    @Test("The install snippet names this package's own repository")
    func theInstallSnippetNamesThisPackagesRepository() throws {
        let manifest = try String(contentsOf: manifestURL, encoding: .utf8)
        let readme = try String(contentsOf: readmeURL, encoding: .utf8)

        let declaration = try #require(manifest.firstMatch(of: /let packageName = "(?<name>\w+)"/))
        #expect(readme.contains(".package(url: \"https://github.com/swissarmyhammer/\(declaration.name)\""))
    }

    /// The guide's "Models" block: a `PooledModel` given to `Searcher` as
    /// `model:`.
    ///
    /// The pool of the model gives a scripted model in place of the MLX
    /// model, so the search runs through the `PooledModel` and its queue
    /// with no download.
    @Test("A PooledModel given as model: answers selection")
    func aPooledModelAnswersSelection() async throws {
        let items = SearcherTests.toolItems
        let scripted = ScriptedLanguageModel([#"{"ids":["glob"]}"#])
        let pool = ModelPool(loader: StubModelLoader(container: scripted))

        let searcher = try await Searcher(items, model: PooledModel(ref: Self.chatModel, pool: pool))

        let hits = try await searcher.search("find files by name")

        #expect(hits.map(\.id) == ["glob"])
        #expect(scripted.calls.count == 1)
    }

    /// The guide's "Embedders" block: a `PooledEmbedder` given to `Searcher`
    /// as `embedder:`.
    ///
    /// The guide's own call leaves `model:` at its on-device default, so this
    /// test names `model: nil` and `mode: .retrieval` to keep the live model
    /// out of the run; the `embedder:` argument under test is unchanged. No
    /// `.embeddingUnavailable` diagnostic proves the vectors really reached
    /// `HybridRanker` and were fused in.
    @Test("A PooledEmbedder given as embedder: adds the cosine signal with no degradation diagnostic")
    func aPooledEmbedderAddsTheCosineSignal() async throws {
        let items = SearcherTests.toolItems
        let pool = ModelPool(loader: StubModelLoader(container: FakeEmbedder(vectorLength: Self.stubVectorLength)))
        let recorder = DiagnosticRecorder()

        let searcher = try await Searcher(
            items,
            embedder: PooledEmbedder(ref: Self.embeddingModel, pool: pool),
            model: nil,
            mode: .retrieval,
            onDiagnostic: { recorder.record($0) }
        )

        let hits = try await searcher.search("search file contents with a regular expression")

        #expect(hits.first?.id == "grep")
        #expect(!recorder.diagnostics.contains(.embeddingUnavailable))
    }
}
