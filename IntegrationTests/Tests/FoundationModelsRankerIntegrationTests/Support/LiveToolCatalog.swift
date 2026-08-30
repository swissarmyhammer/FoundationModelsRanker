import FoundationModelsRanker

/// An in-memory `SelectionCatalog` of tool ids and one-line descriptions, for
/// the tests that drive a live model.
///
/// A bare `LanguageModelSession` carries no id-enum grammar, so nothing stops
/// the model from answering with text that is not an id. Every summary
/// therefore names its own id, and the model can then answer only with an id
/// it has read. This type renders that summary for every entry, so no test
/// has to remember the rule.
///
/// The root package answers its hermetic tests with `FixtureSelectionCatalog`
/// (`Tests/FoundationModelsRankerTests/Support/FixtureSelectionCatalog.swift`)
/// instead. That type lives in a test target, which no other package can
/// import, and it carries a per-entry optional summary that the rule above
/// leaves no room for.
struct LiveToolCatalog: SelectionCatalog {
    /// One entry: a tool id, and the one-line description the model reads.
    struct Entry {
        /// The id the model answers with.
        let id: String

        /// What the tool does, in one line.
        let description: String
    }

    let ids: [String]

    /// Each entry's description, keyed by id.
    private let descriptions: [String: String]

    /// The score `everyEntryRanked()` gives each entry.
    ///
    /// A live-model test reads which id the model chose, never how the
    /// retrieval signals ordered the catalog, so one score for every entry
    /// says all the ordering has to say.
    private static let uniformScore = 0.5

    /// Creates a catalog of `entries`, keeping their order as `ids`.
    ///
    /// - Parameter entries: this catalog's entries, in candidate order.
    init(_ entries: [Entry]) {
        self.ids = entries.map(\.id)
        self.descriptions = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0.description) })
    }

    func summaryBlock(forID id: String) -> String? {
        guard let description = descriptions[id] else { return nil }
        return "id: \(id) -- \(description)"
    }

    func block(forID id: String) -> String? {
        descriptions[id]
    }

    /// Ranks every entry, which keeps the whole catalog selectable.
    ///
    /// `SelectionTier` takes this as its `retrievalRanking`, and it resolves
    /// each id the model chose through the result. An entry left out here is
    /// an entry the tier cannot resolve.
    ///
    /// - Returns: one `SelectionMatch` per entry, in catalog order.
    func everyEntryRanked() -> [SelectionMatch] {
        ids.compactMap { id in
            guard let description = descriptions[id] else { return nil }
            return SelectionMatch(id: id, block: description, score: Self.uniformScore, signals: nil)
        }
    }
}
