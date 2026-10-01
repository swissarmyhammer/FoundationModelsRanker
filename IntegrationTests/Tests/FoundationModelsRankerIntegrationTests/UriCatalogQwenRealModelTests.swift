import FoundationModelsExtras
import FoundationModelsRanker
import Testing

/// The id of the one catalog entry that answers `needleQuery`: a URI, as in
/// the `BigCatalog` example of FoundationModelsMetadataRegistry.
private let needleID = "https://example.com/modules/quantum-flux-capacitor"

/// The query. Its words occur in the description of the needle entry only.
private let needleQuery = "quantum flux capacitor calibration"

/// The topics that the filler entries use in turn, to give the catalog some
/// variety of words.
private let fillerTopics = [
    "parser", "renderer", "scheduler", "cache", "logger",
    "validator", "compiler", "router", "indexer", "formatter",
]

/// The number of filler entries. With the needle, the catalog has 20 entries.
private let fillerCount = 19

/// A catalog whose ids are URIs: the filler entries, then the needle.
///
/// Each description is the one line of the entry, written in the style of
/// the `BigCatalog` example, so the prefix has the shape that made a real
/// model shorten the needle id before card `^knyvhkf`.
private let uriCatalog = LiveToolCatalog(
    (0..<fillerCount).map { index in
        let topic = fillerTopics[index % fillerTopics.count]
        return LiveToolCatalog.Entry(
            id: "https://example.com/modules/module-\(index)",
            description: "Module #\(index): a \(topic) component for \(topic)-related subsystem \(index) tasks."
        )
    } + [
        LiveToolCatalog.Entry(
            id: needleID,
            description: "Provides quantum flux capacitor calibration routines for temporal synchronization."
        )
    ]
)

/// The language model of this suite: Qwen3 4B, 4-bit, from the Hugging Face
/// hub, through `ModelPool.shared`. The first session loads the model, and
/// the first run downloads the weights (about 2.3 GB).
private let qwen = PooledModel(ref: "mlx-community/Qwen3-4B-4bit")

/// The number of times the suite asks the same question, each time on a new
/// tier. A live model can answer differently from one run to the next, and
/// the card requires each of five runs to give back the full URI.
private let roundCount = 5

/// Drives `SelectionTier` over a catalog whose ids are URIs against
/// `mlx-community/Qwen3-4B-4bit`.
///
/// Before card `^knyvhkf`, each candidate entry of the prefix was a
/// `## <id>` heading above its summary, and no text told the model to copy
/// the id. Qwen3-4B (and the on-device system model before it) then
/// answered `"quantum-flux-capacitor"` for the needle. The tier dropped that
/// answer as an unknown id and gave back no match. Each entry is now a
/// `<candidate>` block with an `id:` line, and the preamble, the prompt and
/// the `Selection.ids` guide each ask for the exact id.
///
/// The rounds run one after another (`.serialized`), because all of them
/// use the one model that `ModelPool.shared` holds.
@Suite("A URI-id catalog on Qwen3-4B", .serialized)
struct UriCatalogQwenRealModelTests {
    /// The needle must come back as its full URI id, and the tier must
    /// report no `.unknownSelectedId`.
    ///
    /// Each round makes a new tier, so each round prompts a new root session
    /// that has answered nothing yet.
    ///
    /// - Parameter round: the 1-based number of this round. Only the issue
    ///   text uses it.
    @Test("The needle comes back as its full URI id", arguments: 1...roundCount)
    func theNeedleComesBackAsItsFullUriId(round: Int) async throws {
        let tier = SelectionTier(
            catalog: uriCatalog,
            config: SelectionConfig(model: { instructions in try await qwen.session(instructions: instructions) }),
            onDiagnostic: { diagnostic in
                Issue.record("Round \(round): the selection tier reported \(diagnostic).")
            }
        )

        let matches = try await tier.search(intent: needleQuery, limit: uriCatalog.ids.count)

        #expect(matches.map(\.id).contains(needleID), "Round \(round) gave back \(matches.map(\.id)).")
    }
}
