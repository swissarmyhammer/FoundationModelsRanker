// This tier runs no retrieval step. It makes one prompt that picks, and
// nothing else: a pick is scored by its position in the answer, and an
// over-budget catalog is split into several prompts, not cut.

import FoundationModels

/// The selection tier's dynamic session over any narrow `SelectionCatalog`
/// conformer.
///
/// Assembles a prefix from `SelectionConfig.preamble` and one
/// `<candidate>` block for each catalog id. The block holds an `id:` line
/// with the id and a `description:` line with that id's
/// **`summaryBlock(forID:)`** (the summary seeds the selection prefix; the
/// full `block(forID:)` is the result payload). The tier assembles the
/// prefix once at `init`, since the catalog never changes for this tier's
/// lifetime — a reload replaces the whole tier rather than mutating one in
/// place.
///
/// **One prompt picks.** A search sends the intent to the model and returns
/// the ids the model answered, in the model's order. No retrieval signal
/// enters a selection: the tier needs no embedder and no BM25 index, and a
/// `SelectionMatch` it returns carries an order score (`1 / rank`) and no
/// `signals`.
///
/// **One session for each prompt.** Each prompt goes to a new
/// `LanguageModelSession` on `SelectionConfig.model`. The assembled prefix
/// is the instructions of the session, and the prompt is the request part
/// only: the intent in a `<request>` block, and a line that asks for the
/// exact ids and names the ids of the prompt's candidates as the only
/// choices (`prompt(intent:ids:)`). No prompt sees the turns of another
/// prompt.
///
/// **Under budget** (assembled prefix ≤ `capacityCharacterLimit`): one
/// prompt shows the whole catalog.
///
/// **Over budget**: the catalog ids are split, in catalog order, into runs
/// whose assembled prefix each fits the budget, and every run gets one
/// prompt. Every id reaches exactly one prompt. The answers are merged in
/// run order, then in the model's order inside each run.
/// `search(intent:limit:)` documents the design.
///
/// **IDs only**: the guided output is `Selection { ids: [String] }`, through
/// the native guided generation of the session. The assembled prefix shows
/// every candidate id on its own `id:` line, so the model can read and copy
/// the ids it may return. Returned ids map back through the catalog to
/// verbatim `SelectionMatch`es; an id the catalog does not hold is filtered
/// and reported via `RankDiagnostic.unknownSelectedId(id:)`.
public actor SelectionTier {
    /// The candidates of one prompt: their ids, in catalog order, and the
    /// assembled prefix that shows them.
    private struct CandidateRun: Sendable {
        /// The candidate ids that `prefix` shows, in prefix order. The
        /// prompt names these ids as the only choices.
        let ids: [String]

        /// The instructions of the session that this run's prompt goes to.
        let prefix: String
    }

    /// The full catalog this tier answers `search(intent:limit:)` calls
    /// over.
    private let catalog: any SelectionCatalog

    /// This tier's model, preamble, and capacity budget.
    private let config: SelectionConfig

    /// The runs that each search prompts, one prompt per run: one run with
    /// the whole catalog under budget, or the runs of
    /// `candidateRuns(preamble:catalog:limit:)` over budget. Precomputed once
    /// at `init`, since `catalog` never changes for this tier's lifetime.
    private let runs: [CandidateRun]

    /// Called for every diagnostic this tier emits (currently
    /// `.unknownSelectedId`).
    private let onDiagnostic: @Sendable (RankDiagnostic) -> Void

    /// One blank line: the text between the preamble and the first
    /// candidate entry, and between two candidate entries.
    private static let partSeparator = "\n\n"

    /// The start of the last line of each prompt, below the `<request>`
    /// block. It repeats the exact-id rule of
    /// `SelectionConfig.selectionDefault` beside the intent, where the model
    /// reads it last.
    private static let exactIDsLine = "Answer with the exact ids of the chosen candidates."

    /// The text after `exactIDsLine` that comes before the list of the ids
    /// of the prompt's candidates (`idChoices(_:)`).
    private static let idChoicesLead = "Choose only from these ids: "

    /// The text between two ids in the list of `idChoices(_:)`.
    private static let idChoicesSeparator = ", "

    /// Creates a selection tier over `catalog`, using `config`'s model,
    /// preamble, and budget.
    ///
    /// - Parameters:
    ///   - catalog: the catalog to answer `search(intent:limit:)` calls over.
    ///   - config: this tier's model, preamble, and budget.
    ///   - onDiagnostic: called for every diagnostic this tier emits.
    public init(
        catalog: any SelectionCatalog,
        config: SelectionConfig,
        onDiagnostic: @escaping @Sendable (RankDiagnostic) -> Void
    ) {
        self.catalog = catalog
        self.config = config
        self.runs = Self.runs(preamble: config.preamble, catalog: catalog, limit: config.capacityCharacterLimit)
        self.onDiagnostic = onDiagnostic
    }

    /// Answers one `search(intent:limit:)` call with one prompt per run of
    /// candidates, and no retrieval pass.
    ///
    /// Under budget, one prompt goes out, and its answer is the result.
    ///
    /// Over budget, the tier splits the catalog rather than cutting it. The
    /// catalog ids are divided, in catalog order, into runs whose assembled
    /// prefix each fits `capacityCharacterLimit` (`candidateRuns`). An entry
    /// that does not fit the budget alone still gets a run of its own,
    /// because the tier cannot make a prompt smaller than one entry. Every
    /// run is prompted before the result is cut to `limit`, so a later run's
    /// pick is never lost to an early stop. The answers are merged in run
    /// order, then in the model's order inside each run. The cost is one
    /// prompt per run per search, and no retrieval ranking picks which ids
    /// the model sees: every id reaches exactly one prompt.
    ///
    /// The runs are prompted one after another, not concurrently, because
    /// the merged order is the run order.
    ///
    /// - Parameters:
    ///   - intent: the plain-language search intent.
    ///   - limit: the maximum number of matches to return. `limit <= 0`
    ///     yields an empty result without a prompt.
    /// - Returns: the selected ids' verbatim `SelectionMatch`es, in the
    ///   model's order, each scored by its position (`1 / rank`) and
    ///   carrying no `signals`, at most `limit`. A catalog with no ids
    ///   yields an empty result without a prompt: it has no id to select,
    ///   and a model that gets a prompt with no candidates answers with text
    ///   that does not decode.
    /// - Throws: whatever `LanguageModelSession.respond(to:generating:)`
    ///   throws.
    public func search(intent: String, limit: Int) async throws -> [SelectionMatch] {
        guard limit > 0, !catalog.ids.isEmpty else { return [] }
        var selectedIDs: [String] = []
        for run in runs {
            let session = LanguageModelSession(model: config.model, instructions: run.prefix)
            let selection = try await session.respond(
                to: Self.prompt(intent: intent, ids: run.ids),
                generating: Selection.self
            ).content
            selectedIDs.append(contentsOf: selection.ids)
        }
        return matches(forIDs: selectedIDs, limit: limit)
    }

    /// Assembles the prompt for one model call.
    ///
    /// Every prompt has the same shape: the intent between a `<request>`
    /// line and a `</request>` line, then one line with `exactIDsLine` and
    /// `idChoices(_:)`. The prefix is never in the prompt: it is the
    /// instructions of the session.
    ///
    /// The `<request>` block tells the model that the message is a request
    /// to *select candidates for*, not a task to *do*. Many search intents
    /// read as an order to the model itself -- "record my staged changes as
    /// a new commit", "how do I list or delete a branch" -- and a session
    /// that has answered nothing yet has nothing but the prompt to tell the
    /// two apart. A `# Task` heading can also do this job.
    /// Measured on the on-device system model over the four queries of
    /// `ZeroConfigSearcherRealModelTests`, five cold runs each on a new
    /// `Searcher`: without the heading the two order-shaped queries
    /// answered 0 of 5 and 3 of 5; with it, every query answered 5 of 5.
    ///
    /// `exactIDsLine` comes last, so the last text the model reads before
    /// it answers asks for the exact ids. A real model shortened a URI id to
    /// its last path part when no text asked for the exact id.
    ///
    /// `idChoices(_:)` follows it on the same line and names the ids of the
    /// prompt's candidates as the only choices. Without
    /// the list, the on-device system model made up ids from a verb of the
    /// request and the form of the catalog ids. Over the nine-function
    /// catalog of `FunctionCatalogRealModelTests`, one cold session for each
    /// search, "write file, edit file, create file" answered the made-up id
    /// `files.create` in 3 of 20 searches, and "file operations: create,
    /// write, append, delete, move" answered `files.delete` in 1 of 20.
    /// Five changes to the preamble and the `Selection.ids` guide each moved
    /// the made-up id to a different query: "how do I list or delete a
    /// branch" over the catalog of `ZeroConfigSearcherRealModelTests`
    /// answered the made-up id `delete` in up to 20 of 20 searches. With the
    /// list, these three queries answered no made-up id in 20 searches each.
    ///
    /// - Parameters:
    ///   - intent: the plain-language search intent.
    ///   - ids: the candidate ids of the prompt's prefix, in prefix order.
    /// - Returns: the prompt text to send.
    private static func prompt(intent: String, ids: [String]) -> String {
        "<request>\n\(intent)\n</request>\n\(exactIDsLine) \(idChoices(ids))"
    }

    /// The sentence that names `ids` as the only ids the model can answer
    /// with: `idChoicesLead`, then `ids` with `idChoicesSeparator` between
    /// two ids, then a full stop.
    ///
    /// - Parameter ids: the candidate ids of one prompt, in prefix order.
    /// - Returns: the sentence.
    private static func idChoices(_ ids: [String]) -> String {
        "\(idChoicesLead)\(ids.joined(separator: idChoicesSeparator))."
    }

    // MARK: - Runs of candidates

    /// Makes the runs that each search prompts.
    ///
    /// When the whole assembled prefix fits `limit`, there is one run: each
    /// catalog id that has a summary block, under the whole prefix.
    /// Otherwise the runs are those of `candidateRuns(preamble:catalog:limit:)`,
    /// each with its own assembled prefix.
    ///
    /// - Parameters:
    ///   - preamble: the selection guidance every run's prefix starts with.
    ///   - catalog: the catalog whose ids are split.
    ///   - limit: the character budget.
    /// - Returns: the runs, in catalog order.
    private static func runs(preamble: String, catalog: any SelectionCatalog, limit: Int) -> [CandidateRun] {
        let wholePrefix = assemblePrefix(preamble: preamble, catalog: catalog)
        guard wholePrefix.count > limit else {
            let ids = catalog.ids.filter { catalog.summaryBlock(forID: $0) != nil }
            return [CandidateRun(ids: ids, prefix: wholePrefix)]
        }
        return candidateRuns(preamble: preamble, catalog: catalog, limit: limit).map { ids in
            CandidateRun(ids: ids, prefix: assemblePrefix(preamble: preamble, ids: ids, catalog: catalog))
        }
    }

    /// Splits `catalog.ids`, in catalog order, into runs whose assembled
    /// prefix (`assemblePrefix(preamble:ids:catalog:)`) each fits `limit`
    /// characters.
    ///
    /// The split is greedy: an id joins the current run while the run's
    /// prefix stays at or under `limit`, and starts a new run otherwise. An
    /// entry that does not fit the budget alone still makes a run of its
    /// own, so no id is dropped. An id the catalog has no summary for is
    /// left out, exactly as `assemblePrefix` leaves it out. The whole
    /// catalog fits one run when its full prefix fits the budget.
    ///
    /// The count is kept incrementally from the parts' own counts. A
    /// grapheme cluster can only merge across a join, never split, so the
    /// sum of the parts is never less than the joined prefix's count and a
    /// run that passes here fits in fact.
    ///
    /// - Parameters:
    ///   - preamble: the selection guidance every run's prefix starts with.
    ///   - catalog: the catalog whose ids are split.
    ///   - limit: the character budget one run's prefix must fit.
    /// - Returns: the runs, in catalog order; empty for a catalog with no
    ///   summarized id.
    static func candidateRuns(preamble: String, catalog: any SelectionCatalog, limit: Int) -> [[String]] {
        let headerCount = assemblePrefix(preamble: preamble, ids: [], catalog: catalog).count
        var runs: [[String]] = []
        var run: [String] = []
        var runCount = headerCount
        for id in catalog.ids {
            guard let entry = candidateEntry(forID: id, catalog: catalog) else { continue }
            if !run.isEmpty, runCount + partSeparator.count + entry.count > limit {
                runs.append(run)
                run = []
                runCount = headerCount
            }
            runCount += (run.isEmpty ? 0 : partSeparator.count) + entry.count
            run.append(id)
        }
        if !run.isEmpty {
            runs.append(run)
        }
        return runs
    }

    // MARK: - Verbatim lookup and order scores

    /// Maps model-selected `ids` back through the catalog to verbatim
    /// `SelectionMatch`es, filtering any id
    /// the catalog does not hold and reporting it via `.unknownSelectedId`
    /// — the backstop against a model that answers with text that is not an
    /// id — deduplicating repeats (first occurrence wins, which keeps the
    /// model's own call-order intent) without reporting a diagnostic for
    /// them, and truncating to `limit`.
    ///
    /// Each match is scored by its position among the kept ids
    /// (`orderScore(rank:)`) and carries no `signals`: no retrieval signal
    /// enters a selection.
    ///
    /// - Parameters:
    ///   - ids: the model-selected ids, in the order the model returned them.
    ///   - limit: the maximum number of matches to return.
    /// - Returns: the verbatim `SelectionMatch`es for every known, first-seen
    ///   id, in order, at most `limit`.
    private func matches(forIDs ids: [String], limit: Int) -> [SelectionMatch] {
        var results: [SelectionMatch] = []
        results.reserveCapacity(min(ids.count, limit))
        var seenIDs: Set<String> = []
        for id in ids {
            guard results.count < limit else { break }
            guard seenIDs.insert(id).inserted else { continue }
            guard let block = catalog.block(forID: id) else {
                onDiagnostic(.unknownSelectedId(id: id))
                continue
            }
            results.append(
                SelectionMatch(
                    id: id,
                    block: block,
                    score: Self.orderScore(rank: results.count + 1),
                    signals: nil
                )
            )
        }
        return results
    }

    /// The score of the pick at 1-based `rank` in the model's answer: the
    /// reciprocal of the rank, so the first pick scores `1.0`, the second
    /// `0.5`, the n-th `1 / n`. Monotonic in the model's order and
    /// independent of how many picks follow, so the same pick order gives
    /// the same scores whatever the answer's length.
    ///
    /// - Parameter rank: the pick's 1-based position among the kept ids.
    /// - Returns: `1 / rank`.
    static func orderScore(rank: Int) -> Double {
        1.0 / Double(rank)
    }

    // MARK: - Prefix assembly

    /// Assembles this tier's instruction prefix: `preamble`, one blank
    /// line, and one entry per catalog id, in catalog order. Each entry is a
    /// `<candidate>` block that holds the id on an `id:` line and the id's
    /// **`summaryBlock(forID:)`** on a `description:` line — never
    /// `block(forID:)`, which stays reserved for the verbatim
    /// `SelectionMatch.block` a selected id looks up afterward.
    ///
    /// - Parameters:
    ///   - preamble: the selection guidance to prepend.
    ///   - catalog: the catalog to assemble a prefix for.
    /// - Returns: the assembled prefix text.
    public static func assemblePrefix(preamble: String, catalog: any SelectionCatalog) -> String {
        assemblePrefix(preamble: preamble, ids: catalog.ids, catalog: catalog)
    }

    /// Assembles an instruction prefix for an arbitrary candidate id
    /// set: `preamble`, one blank line, and one
    /// `candidateEntry(forID:catalog:)` per id, in `ids`' order, with one
    /// blank line between two entries —
    /// `assemblePrefix(preamble:catalog:)`'s whole-catalog case is
    /// `ids: catalog.ids`; the over-budget path passes one run of ids
    /// instead. An id the catalog has no summary for is left out, exactly
    /// as the catalog itself reports it absent.
    ///
    /// - Parameters:
    ///   - preamble: the selection guidance to prepend.
    ///   - ids: the candidate ids to render, in the order they should appear.
    ///   - catalog: the catalog to look candidate summaries up in.
    /// - Returns: the assembled prefix text.
    public static func assemblePrefix(preamble: String, ids: [String], catalog: any SelectionCatalog) -> String {
        let entries = ids.compactMap { candidateEntry(forID: $0, catalog: catalog) }
        return "\(preamble)\(partSeparator)\(entries.joined(separator: partSeparator))"
    }

    /// Renders one candidate's prefix entry: a `<candidate>` block with the
    /// id on an `id:` line and the id's `summaryBlock(forID:)` on a
    /// `description:` line.
    ///
    /// The entry makes the id visible to the model, and it labels the id as
    /// an id. The preamble tells the model to copy each id exactly as it is
    /// written after `id:`, so the id stands alone on that line. A prefix
    /// of bare summaries makes the model answer with a summary, and a
    /// `## <id>` heading makes the id read like a title: a real model
    /// shortened the URI id `https://example.com/modules/quantum-flux-capacitor`
    /// under such a heading to `quantum-flux-capacitor`. Either answer
    /// resolves to nothing and reports `.unknownSelectedId`. Both
    /// `assemblePrefix` overloads and `candidateRuns` render through this
    /// one function, so the paths cannot drift apart.
    ///
    /// - Parameters:
    ///   - id: the candidate id to render.
    ///   - catalog: the catalog to look the candidate summary up in.
    /// - Returns: the rendered entry, or `nil` if `id` isn't in `catalog`.
    private static func candidateEntry(forID id: String, catalog: any SelectionCatalog) -> String? {
        guard let summary = catalog.summaryBlock(forID: id) else { return nil }
        return "<candidate>\nid: \(id)\ndescription: \(summary)\n</candidate>"
    }
}
