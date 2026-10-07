import Foundation
import FoundationModelsExtras
import FoundationModelsRanker

// # The models, the report writer, and the match formatter of `FullMonty`.

/// The embedding model of the example: Qwen3 Embedding 0.6B, 4-bit, from the
/// Hugging Face hub.
///
/// The embedder loads nothing when you make it. The first embed loads the
/// model through `ModelPool.shared`, and the first run downloads the weights.
/// Both searchers of the example use this value, so they share the one
/// loaded model.
let exampleEmbedder = PooledEmbedder(ref: "mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ")

/// The language model of the example: Qwen3 4B, 4-bit, from the Hugging Face
/// hub.
///
/// The model loads nothing when you make it. The first prompt loads the
/// model through `ModelPool.shared`, and the first run downloads the weights.
let exampleSelectionModel = PooledModel(ref: "mlx-community/Qwen3-4B-4bit")

/// The report that the example writes: its whole output, one line at a time.
///
/// The report is the product of the example, not a debug log. Thus it goes to
/// standard output through this one explicit writer.
enum Report {
    /// Writes `line` and a line break to standard output.
    ///
    /// - Parameter line: the text of the line.
    static func write(_ line: String) {
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }
}

/// Formats matches, one line each, with the rank, the id, the score, and the
/// value of each signal.
///
/// A selection match has no retrieval signals, so its line says so.
///
/// - Parameter matches: the matches to format, in ranked or selected order.
/// - Returns: one line for each match, joined by line breaks, or one
///   placeholder line when `matches` is empty.
func formattedMatches(_ matches: [SelectionMatch]) -> String {
    guard !matches.isEmpty else { return "(no matches)" }
    return matches.enumerated().map { index, match in
        let breakdown =
            match.signals.map {
                String(format: "bm25=%.3f trigram=%.3f cosine=%.3f", $0.bm25, $0.trigram, $0.cosine)
            } ?? "selection (no retrieval signals)"
        return String(format: "%d. %@  score=%.3f  [%@]", index + 1, match.id, match.score, breakdown)
    }.joined(separator: "\n")
}
