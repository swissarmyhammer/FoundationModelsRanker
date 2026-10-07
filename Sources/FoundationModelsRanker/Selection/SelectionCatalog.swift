// The catalog seam for the selection tier. This protocol captures the
// three operations `SelectionTier` uses: the full candidate id set, each
// id's summary, and each id's verbatim block.

/// The catalog contract FoundationModelsRanker's selection tier drives its assembled prefix
/// and verbatim result lookup through.
///
/// The coupling is narrow: a selection tier only ever needs the full
/// candidate id set, a (typically shorter) summary per id to seed the
/// prefix it hands the model, and the full verbatim block per id to hand
/// back as a result payload once the model picks that id. Any index or
/// snapshot type -- this package's own `SearchCorpus`, or a consumer's
/// bespoke catalog -- conforms trivially by forwarding to its existing
/// lookups; nothing here requires adopting a particular storage shape.
public protocol SelectionCatalog: Sendable {
    /// The catalog's ids, in the order candidates should be considered --
    /// the full candidate set under budget, or the order a selection tier
    /// splits them into prompts over budget.
    var ids: [String] { get }

    /// A (typically shorter) summary of `id`'s item, used to seed the
    /// selection tier's assembled prefix instead of the full
    /// `block(forID:)`.
    ///
    /// - Parameter id: the id to look up.
    /// - Returns: the id's summary text, or `nil` if `id` isn't in this
    ///   catalog.
    func summaryBlock(forID id: String) -> String?

    /// `id`'s full, verbatim result payload -- what a model-selected id
    /// resolves to in the tier's returned results, never re-derived from
    /// the model's own output.
    ///
    /// - Parameter id: the id to look up.
    /// - Returns: the id's verbatim block, or `nil` if `id` isn't in this
    ///   catalog.
    func block(forID id: String) -> String?
}
