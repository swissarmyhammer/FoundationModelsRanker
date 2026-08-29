import Foundation
import Testing

// MARK: - Shared id-enum JSON Schema extraction
//
// The schema tests in `SelectionTests` assert on what
// `SelectionTier.idEnumSchema(ids:)` constrains `Selection.ids` to. They read
// the constraints out of the parsed schema instead of comparing schema text,
// because `JSONSerialization` does not keep a stable key order: two equal
// schemas can have different text. The walk from the schema source down to
// the `ids` subschema lives once, here, and not in each test.

/// Reads the constraints that a `SelectionTier.idEnumSchema(ids:)` source
/// string puts on `Selection.ids`.
///
/// A test asserts on the parsed constraints, never on the schema text,
/// because `JSONSerialization` does not keep a stable key order.
enum SelectionSchemaTestSupport {
    /// Extracts the `properties.ids` subschema -- the object that carries the
    /// `items` subschema, the `uniqueItems` flag, and the `maxItems` cap.
    ///
    /// - Parameter source: a JSON Schema source string.
    /// - Returns: the `properties.ids` subschema.
    /// - Throws: an error if `source` is not JSON, or if it does not have a
    ///   `properties.ids` subschema.
    static func idsSchema(in source: String) throws -> [String: Any] {
        let data = try #require(source.data(using: .utf8))
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let properties = try #require(root["properties"] as? [String: Any])
        return try #require(properties["ids"] as? [String: Any])
    }

    /// Extracts the `properties.ids.items.enum` id set that the schema
    /// constrains each selected id to.
    ///
    /// - Parameter source: a JSON Schema source string.
    /// - Returns: the permitted ids.
    /// - Throws: an error if `source` is not JSON, or if it does not have a
    ///   `properties.ids.items.enum` id list.
    static func enumIds(in source: String) throws -> Set<String> {
        let idsSubschema = try idsSchema(in: source)
        let itemsSchema = try #require(idsSubschema["items"] as? [String: Any])
        let enumValues = try #require(itemsSchema["enum"] as? [String])
        return Set(enumValues)
    }
}
