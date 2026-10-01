// Ported from FoundationModelsMetadataRegistry's
// `Sources/FoundationModelsMetadataRegistry/Selection/Selection.swift`.
// No behavior or shape changes -- the same
// `@Generable`, ids-only output. Doc comment updated to reference
// `SelectionConfig.selectionDefault` (this package's neutral rename of
// `.librarianDefault`) and to drop the FoundationModelsMetadataRegistry-
// specific `MetadataSearcher`/`Match` cross-references. Card ^knyvhkf
// changed the `@Guide` text to ask for the exact id.

import FoundationModels

/// The selection tier's guided-generation output: **ids only, never
/// blocks** -- the model picks from the current candidate id enum (a
/// grammar the selection tier constrains structurally), and the tier maps
/// the returned ids back through its catalog to verbatim results
/// afterward. The model is never asked to reproduce a block, only to
/// choose among ids.
@Generable
public struct Selection: Sendable, Equatable {
    /// The selected ids: the exact id of each chosen candidate, copied from
    /// the `id:` line of its `<candidate>` block in the assembled prefix.
    /// Empty only when no candidate is related to the request.
    ///
    /// The guide text repeats the exact-id rule of
    /// `SelectionConfig.selectionDefault`, because a guided-generation
    /// backend shows the model this text beside the `ids` field. A real
    /// model shortened a URI id to its last path part when neither text
    /// told it to copy the id whole (card `^knyvhkf`).
    @Guide(
        description: "the exact id of each chosen candidate, copied character for character from its id: line; "
            + "empty only when no candidate is related to the request"
    )
    public var ids: [String]

    /// Creates a selection result.
    ///
    /// Explicit for the same reason as this package's other public struct
    /// initializers: a `public` struct's synthesized memberwise initializer
    /// is only `internal`-accessible.
    ///
    /// - Parameter ids: the selected ids.
    public init(ids: [String]) {
        self.ids = ids
    }
}
