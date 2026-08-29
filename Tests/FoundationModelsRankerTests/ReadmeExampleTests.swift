import Foundation
import Testing

@testable import FoundationModelsRanker

/// Exercises the exact shape of `README.md`'s code examples -- the trivial
/// `SearchItem` list, the zero-config `Searcher(items)` call, the one live
/// session, the session factory, the caller-written embedder, and the guided
/// output schema -- against scripted `AgentSession`/`TextEmbedding` fakes
/// (never a live on-device model), so a change to `Searcher`'s public surface
/// breaks this test before it breaks a reader pasting the README into their
/// own project. One test stands for each Swift block of the README, in the
/// order the README gives them; the `## Install` block is the one block no
/// test can compile, and its own test states why. A last test holds the
/// prose itself to the package's dependency-free shape.
///
/// Reuses `SearcherTests.toolItems`'s grep/glob/watch fixture -- the same
/// three-item list `README.md`'s lead example itself lists -- and the same
/// `ScriptedAgentSession`/`FakeEmbedder` doubles every other suite in this
/// target substitutes for the real model (`Support/ScriptedAgentSession.swift`,
/// `Support/FakeEmbedder.swift`).
@Suite("README example")
struct ReadmeExampleTests {
    /// README's lead example: a `SearchItem` list, `Searcher(items)`, one
    /// `search(...)` call.
    ///
    /// The README's own zero-config call omits `session:`, which defaults
    /// to `Searcher.defaultSessionFactory` (a real on-device model session)
    /// -- unusable here without Apple Intelligence, so this test supplies a
    /// scripted fake in its place, exercising the identical initializer and
    /// `search(_:limit:)` call shape the README documents.
    ///
    /// A session is configured and `mode` is left at its `.auto` default
    /// (as the README's own call does), so this resolves to `.selection`;
    /// this three-item list stays comfortably under
    /// `SelectionConfig.defaultCapacityCharacterLimit`, so it's an
    /// under-budget pick that carries the real fused `score` and per-signal
    /// `signals` retrieval reports for the query (the same behavior
    /// `SearcherTests
    /// .selectionModeUnderBudgetUsesTheConfiguredSessionAndAttachesRealRetrievalScoreAndSignals`
    /// pins), matching plan.md §3a's ".score and per-signal .signals
    /// attached" promise. Pinned here so the README's "Modes" section,
    /// which documents this exact shape, can't drift.
    @Test("The lead example's SearchItem list and Searcher(items).search(...) call find grep first")
    func leadExampleFindsGrepForATodoCommentsQuery() async throws {
        let items = SearcherTests.toolItems

        let searcher = try await Searcher(items, session: { _ in ScriptedAgentSession([#"{"ids":["grep"]}"#]) })

        let hits = try await searcher.search("how do I find TODO comments in my code")

        let first = try #require(hits.first)
        #expect(first.id == "grep")
        // The pick carries the same real fused score and per-signal
        // breakdown `.retrieval` mode reports for it -- never a fixed
        // sentinel.
        let retrievalSearcher = try await Searcher(items, session: nil, mode: .retrieval)
        let retrievalHits = try await retrievalSearcher.search("how do I find TODO comments in my code")
        let expected = try #require(retrievalHits.first { $0.id == "grep" })
        #expect(first.score == expected.score)
        #expect(first.signals == expected.signals)
    }

    /// README's one-live-session example -- a caller that already holds a
    /// session gives that session itself, with no factory closure around it.
    ///
    /// The README block gives a `LanguageModelSession`, which needs Apple
    /// Intelligence; this test gives a scripted fake in its place. Both are
    /// `any AgentSession`, so the initializer under test is the one the
    /// README documents.
    ///
    /// The fork count pins the tradeoff the README states beside the block:
    /// the tier forks the one session the caller gave, and
    /// `ScriptedAgentSession.fork()` gives back `self` exactly as
    /// `LanguageModelSession.fork()` does, so every call adds turns to that
    /// one transcript.
    @Test("A live session given to Searcher answers selection through a fork of itself")
    func oneLiveSessionAnswersSelectionAndSharesItsTranscript() async throws {
        let items = SearcherTests.toolItems
        let session = ScriptedAgentSession([#"{"ids":["glob"]}"#])

        let searcher = try await Searcher(items, session: session)

        let hits = try await searcher.search("find files by name pattern")

        #expect(hits.first?.id == "glob")
        #expect(session.forkCount == 1)
    }

    /// README's session factory example -- "any `LanguageModelSession`
    /// works, the model is never hardcoded" -- proves the `session:` seam
    /// accepts a plain `(String) -> any AgentSession` closure and that
    /// swapping it swaps which session answers `search(_:limit:)`.
    @Test("An explicit session: closure swaps which session answers selection")
    func explicitSessionClosureSwapsTheAnsweringSession() async throws {
        let items = [
            SearchItem(id: "grep", text: "Search file contents with regular expressions"),
            SearchItem(id: "glob", text: "Find files by name pattern, sorted by mtime"),
        ]

        let searcher = try await Searcher(items, session: { _ in ScriptedAgentSession([#"{"ids":["glob"]}"#]) })

        let hits = try await searcher.search("find files by name")

        #expect(hits.first?.id == "glob")
    }

    /// README's "Bring your own embedder" block: a caller-written
    /// `TextEmbedding` conformer, given to `Searcher` as `embedder:`.
    ///
    /// `MyEmbedder` below is the README's own struct, and `myBackend` is the
    /// embedding backend the README's prose tells the reader to put there.
    /// The README's own call leaves `session:` at its on-device default, so
    /// this test names `session: nil` and `mode: .retrieval` to keep the
    /// live model out of the run; the `embedder:` argument under test is
    /// unchanged.
    ///
    /// No `.embeddingUnavailable` diagnostic proves the conformer's vectors
    /// really reached `HybridRanker` and were fused in, which is the claim
    /// the section makes.
    @Test("A caller-written TextEmbedding conformer adds the cosine signal with no degradation diagnostic")
    func theCallerWrittenEmbedderThreadsThroughWithoutDegrading() async throws {
        let items = [
            SearchItem(id: "grep", text: "Search file contents with regular expressions"),
            SearchItem(id: "glob", text: "Find files by name pattern, sorted by mtime"),
        ]
        let recorder = DiagnosticRecorder()

        let searcher = try await Searcher(
            items,
            embedder: MyEmbedder(),
            session: nil,
            mode: .retrieval,
            onDiagnostic: { recorder.record($0) }
        )

        let hits = try await searcher.search("search file contents with a regular expression")

        #expect(hits.first?.id == "grep")
        #expect(!recorder.diagnostics.contains(.embeddingUnavailable))
    }

    /// README's "Guided output" block: `SelectionTier.idEnumSchema(ids:)`
    /// gives back JSON Schema source text that limits the answer to the ids
    /// the caller passes.
    ///
    /// Asserts on the parsed constraint rather than on the schema text,
    /// because `JSONSerialization` keeps no stable key order
    /// (`Support/SelectionSchemaTestSupport.swift`).
    @Test("idEnumSchema(ids:) limits the answer to the ids the caller gives it")
    func theGuidedOutputSchemaLimitsTheAnswerToTheGivenIds() throws {
        let items = SearcherTests.toolItems

        let schema = try SelectionTier.idEnumSchema(ids: items.map(\.id))

        let permittedIDs = try SelectionSchemaTestSupport.enumIds(in: schema)
        #expect(permittedIDs == Set(items.map(\.id)))
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

    /// Holds `README.md` to the package's dependency-free shape.
    ///
    /// The package once depended on a router package and on an MLX/Hugging
    /// Face embedding stack, and the README named all three. It depends on
    /// nothing now, and `Package.swift` declares no package dependency
    /// (`PackageTests.theManifestDeclaresNoPackageDependency`). This test
    /// keeps the document from drifting back to the old story: it reads the
    /// README text and fails on any of the three names, in any letter case.
    @Test("README.md names no removed dependency")
    func theReadmeNamesNoRemovedDependency() throws {
        let readme = try String(contentsOf: readmeURL, encoding: .utf8)

        for name in ["Router", "MLX", "HuggingFace"] {
            #expect(
                readme.range(of: name, options: .caseInsensitive) == nil,
                "README.md still names \(name), which this package no longer depends on."
            )
        }
    }
}

/// The embedder `README.md`'s "Bring your own embedder" section declares,
/// kept here verbatim so the section is compiled and run, not just read.
///
/// `dimension` and `embed(_:)` are the whole `TextEmbedding` contract, and
/// the body gives the texts to the caller's own backend.
private struct MyEmbedder: TextEmbedding {
    /// The length of every vector `myBackend` makes.
    let dimension = 768

    /// Gives the texts to your own embedding backend.
    func embed(_ texts: [String]) async throws -> [[Float]] {
        try await myBackend.embed(texts)
    }
}

/// The embedding backend `MyEmbedder` forwards to.
///
/// A reader puts their own model or service here. This suite puts
/// `FakeEmbedder` here instead, because a real backend needs a model, a GPU,
/// or a network call, and none of the three belongs in a unit test. Its
/// length reads off `MyEmbedder` itself, so the README's declared
/// `dimension` and the vectors this backend really makes cannot disagree.
private let myBackend = FakeEmbedder(dimension: MyEmbedder().dimension)
