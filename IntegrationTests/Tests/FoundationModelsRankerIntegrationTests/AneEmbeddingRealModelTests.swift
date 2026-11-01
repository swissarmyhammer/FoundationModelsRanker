import FoundationModelsExtras
import FoundationModelsRanker
import Testing

/// The Hugging Face name of the embedding model of this suite. It is a Core ML
/// package that runs on the Apple Neural Engine. The first run downloads the
/// package and compiles it, and each later run reads the compiled model from
/// the cache.
private let aneModelRef: ModelRef = "erjigit17/embeddinggemma-300m-ane-coreml"

/// The pool of this suite. It uses `CoreMLModelLoader`, because the default
/// loader of `ModelPool.shared` loads MLX models only.
private let anePool = ModelPool(loader: CoreMLModelLoader())

/// The embedder of this suite. It loads nothing until the first call.
private let aneEmbedder = PooledEmbedder(ref: aneModelRef, pool: anePool)

/// The cosine similarity of two vectors.
///
/// - Parameters:
///   - lhs: the first vector.
///   - rhs: the second vector. It has the length of `lhs`.
/// - Returns: the dot product divided by the product of the two norms.
private func cosine(_ lhs: [Float], _ rhs: [Float]) -> Double {
    var dot = 0.0
    var lhsNorm = 0.0
    var rhsNorm = 0.0
    for (left, right) in zip(lhs, rhs) {
        dot += Double(left) * Double(right)
        lhsNorm += Double(left) * Double(left)
        rhsNorm += Double(right) * Double(right)
    }
    return dot / (lhsNorm.squareRoot() * rhsNorm.squareRoot())
}

/// Drives the Core ML embedding model on the Apple Neural Engine, first alone
/// and then through the `Searcher` facade.
///
/// No hermetic test can run a Core ML model, so this suite is the only place
/// where the ANE path of `CoreMLModelLoader` and `PooledEmbedder` runs under
/// this package. It makes no claim about exact vector values, because the
/// compute units can give small differences from one run to the next. Each
/// claim is about shape or about order.
///
/// The rounds run one after another (`.serialized`), because all of them use
/// the one model that `anePool` holds.
@Suite("The ANE embedding model", .serialized)
struct AneEmbeddingRealModelTests {
    /// Each text must give one vector, and all vectors must have one length.
    ///
    /// The vectors must have values that are finite and not all zero. A model
    /// that did not run, or that gave `NaN`, would break this claim.
    @Test("Each text gives one finite vector of the same length")
    func eachTextGivesOneFiniteVectorOfTheSameLength() async throws {
        let texts = [
            "Search file contents with regular expressions",
            "Record staged changes as a new snapshot in the repository history",
            "Report free and used disk space by filesystem",
        ]

        let vectors = try await aneEmbedder.embed(texts: texts)

        #expect(vectors.count == texts.count)
        let length = try #require(vectors.first?.count)
        #expect(length > 0)
        for vector in vectors {
            #expect(vector.count == length)
            #expect(vector.allSatisfy { $0.isFinite })
            #expect(vector.contains { $0 != 0 })
        }
    }

    /// A text must give the same vector direction when it is embedded again.
    ///
    /// The claim is a cosine of at least `0.99`, not equality, because the
    /// Neural Engine computes in half precision.
    @Test("The same text gives the same direction twice")
    func theSameTextGivesTheSameDirectionTwice() async throws {
        let text = "Temporarily set aside uncommitted edits to switch tasks"

        let first = try await aneEmbedder.embed(texts: [text])
        let second = try await aneEmbedder.embed(texts: [text])

        let firstVector = try #require(first.first)
        let secondVector = try #require(second.first)
        #expect(cosine(firstVector, secondVector) > 0.99)
    }

    /// A text must be nearer to a text of the same meaning than to a text of
    /// another meaning, with no word in common.
    ///
    /// This is the claim that the model gives meaning, not only a vector. A
    /// lexical signal cannot hold it, because the two close texts share no
    /// word.
    @Test("A paraphrase is nearer than an unrelated text")
    func aParaphraseIsNearerThanAnUnrelatedText() async throws {
        let anchor = "Temporarily set aside uncommitted edits to switch tasks"
        let paraphrase = "Put my work in progress on a shelf so I can do something else"
        let unrelated = "Report free and used disk space by filesystem"

        let vectors = try await aneEmbedder.embed(texts: [anchor, paraphrase, unrelated])

        let anchorVector = vectors[0]
        #expect(cosine(anchorVector, vectors[1]) > cosine(anchorVector, vectors[2]))
    }

    /// A `Searcher` with an ANE embedder and no language model must run the
    /// cosine signal on every search, and must report no
    /// `.embeddingUnavailable`.
    ///
    /// The searcher embeds the catalog at `init` and the query at each
    /// search. `mode: .retrieval` and `model: nil` keep the system language
    /// model out of this test, thus a Mac without Apple Intelligence can run
    /// it. The weights keep only the cosine signal, because the filler words
    /// of the query ("so", "on", "do") match many items in BM25 and in
    /// trigrams, and they push the right item out of the top five. The
    /// query shares no content word with the `stash` item. The claim is that
    /// the item is in the top five, and that its cosine is positive.
    @Test("A retrieval Searcher with the ANE embedder runs the cosine signal")
    func aRetrievalSearcherWithTheAneEmbedderRunsTheCosineSignal() async throws {
        let searcher = try await Searcher(
            developerToolCatalog,
            embedder: aneEmbedder,
            model: nil,
            weights: SignalWeights(bm25: 0, trigram: 0, cosine: 1),
            mode: .retrieval,
            onDiagnostic: { diagnostic in
                Issue.record("The searcher reported \(diagnostic).")
            }
        )

        let matches = try await searcher.search(
            "put my work in progress on a shelf so I can do something else", limit: 5)

        let stash = try #require(matches.first { $0.id == "stash" }, "The top five were \(matches.map(\.id)).")
        let signals = try #require(stash.signals)
        #expect(signals.cosine > 0)
        #expect(matches.contains { ($0.signals?.cosine ?? 0) != 0 })
    }
}
