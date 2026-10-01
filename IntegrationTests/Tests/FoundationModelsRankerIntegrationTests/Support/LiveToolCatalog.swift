import FoundationModelsRanker

/// An in-memory `SelectionCatalog` of ids and one-line descriptions, for the
/// tests that drive a live model.
///
/// The summary of each entry is its description alone. The assembled prefix
/// already puts each id on the `id:` line of its `<candidate>` block, above a
/// `description:` line with this summary. Before card `^knyvhkf`, the
/// summary also named its own id, because the prefix showed each id only as a
/// heading. A summary that repeats the id now gives the model a second
/// `id:` text in the `description:` line, and that is not the format that a
/// real catalog gives.
///
/// The root package answers its hermetic tests with `FixtureSelectionCatalog`
/// (`Tests/FoundationModelsRankerTests/Support/FixtureSelectionCatalog.swift`)
/// instead. That type lives in a test target, which no other package can
/// import.
struct LiveToolCatalog: SelectionCatalog {
    /// One entry: an id, and the one-line description the model reads.
    struct Entry {
        /// The id the model answers with.
        let id: String

        /// What the entry does, in one line.
        let description: String
    }

    let ids: [String]

    /// Each entry's description, keyed by id.
    private let descriptions: [String: String]

    /// Creates a catalog of `entries`, keeping their order as `ids`.
    ///
    /// - Parameter entries: this catalog's entries, in candidate order.
    init(_ entries: [Entry]) {
        self.ids = entries.map(\.id)
        self.descriptions = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0.description) })
    }

    func summaryBlock(forID id: String) -> String? {
        descriptions[id]
    }

    func block(forID id: String) -> String? {
        descriptions[id]
    }
}
