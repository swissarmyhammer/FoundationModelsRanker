// Ported from FoundationModelsMetadataRegistry's
// `Sources/FoundationModelsMetadataRegistry/Selection/SelectionTier.swift`
// (plan.md §6 phase 3), generalized over `any SelectionCatalog` instead of
// `MetadataIndex<Item>`: `index.ids`/`item(forID:)`/`block(forID:)`/
// `renderSummaryBlock()` map onto `catalog.ids`/`summaryBlock(forID:)`/
// `block(forID:)`; `Match<Item>` becomes `SelectionMatch` (no catalog item to
// carry); `MetadataDiagnostic` becomes `RankDiagnostic`.
//
// Task ^kqp9e5e removed every retrieval step from this tier. The source tier
// ranked the whole catalog with BM25, trigram, and cosine after the model
// answered (to score the picks) and before the prompt over budget (to cut the
// candidates to the top M). This tier makes one prompt that picks, and
// nothing else: a pick is scored by its position in the answer, and an
// over-budget catalog is split into several prompts rather than cut.

import Foundation

/// The selection tier's dynamic session over a `SelectionCatalog` (plan.md
/// §6): generalizes FoundationModelsMetadataRegistry's own `SelectionTier`,
/// which itself generalized Multitool's shipped `Librarian`
/// (`../FoundationModelsMultitool/Sources/.../Librarian.swift`), over any
/// narrow `SelectionCatalog` conformer instead of a bespoke index type.
///
/// Assembles a prefix from `SelectionConfig.preamble`, a `# Candidates`
/// header, and every catalog id rendered as a markdown heading above that
/// id's **`summaryBlock(forID:)`** (plan.md §4: the summary seeds the
/// selection prefix; the full `block(forID:)` is the result payload) once
/// at `init`, since the catalog never changes for this tier's lifetime — a
/// reload replaces the whole tier rather than mutating one in place.
///
/// **One prompt picks.** A search sends the intent to the model and returns
/// the ids the model answered, in the model's order. No retrieval signal
/// enters a selection: the tier needs no embedder and no BM25 index, and a
/// `SelectionMatch` it returns carries an order score (`1 / rank`) and no
/// `signals`.
///
/// **Under budget** (assembled prefix ≤ `capacityCharacterLimit`): a cached
/// root session is seeded once with the prefix, and each
/// `search(intent:limit:)` `fork()`s a fresh child from it, so the prefix's
/// KV cache is prefilled once and inherited per call — lifted from
/// `Librarian.findAPIs(task:)`'s cached-root + fork-per-call mechanics.
///
/// **Over budget**: the catalog ids are split, in catalog order, into runs
/// whose assembled prefix each fits the budget, and every run gets one
/// prompt on a **fresh, uncached one-off session**. Every id reaches exactly
/// one prompt. The answers are merged in run order, then in the model's
/// order inside each run. `search(intent:limit:)` documents the design.
///
/// **Where the prefix goes** follows `SelectionConfig.sessionSource`. A
/// `.factory` source seeds the prefix as each session's instructions, so the
/// prompt carries the intent alone, under a `# Task` heading. A `.session`
/// source hands over one live session, which takes no new instructions: the
/// tier forks that session for each prompt and carries the prefix above the
/// same heading instead (`prompt(prefix:intent:)`). Either way the model sees
/// the same prefix, and reads the intent as a task to select for.
///
/// **IDs only** (plan.md §6, decision #4): the guided output is
/// `Selection { ids: [String] }`. The assembled prefix shows every candidate
/// id as a markdown heading, so the model can read the ids it may return.
/// This tier applies no grammar of its own: a caller that wants guided
/// generation applies one when it makes the session, and
/// `idEnumSchema(ids:)` gives that caller the id set. Returned ids map back
/// through the catalog to verbatim `SelectionMatch`es; an id the catalog
/// does not hold is filtered and reported via
/// `RankDiagnostic.unknownSelectedId(id:)`.
public actor SelectionTier {
    /// The full catalog this tier answers `search(intent:limit:)` calls
    /// over.
    private let catalog: any SelectionCatalog

    /// This tier's session source, preamble, and capacity budget.
    private let config: SelectionConfig

    /// `assemblePrefix(preamble:catalog:)`, precomputed once at `init` since
    /// `catalog` never changes for this tier's lifetime.
    private let assembledPrefix: String

    /// `catalog.ids` split into the runs the over-budget path prompts, one
    /// prompt per run (`candidateRuns(preamble:catalog:limit:)`).
    /// Precomputed once at `init`, like `assembledPrefix`, and read only
    /// when the whole prefix does not fit the budget.
    private let candidateRuns: [[String]]

    /// Called for every diagnostic this tier emits (currently
    /// `.unknownSelectedId`).
    private let onDiagnostic: @Sendable (RankDiagnostic) -> Void

    /// This tier's cached root session — `nil` until the first under-budget
    /// `search(intent:limit:)` call creates and caches it.
    private var rootSession: (any AgentSession)?

    /// The text between two candidate entries in an assembled prefix.
    private static let candidateSeparator = "\n\n"

    /// Creates a selection tier over `catalog`, using `config`'s session
    /// source, preamble, and budget.
    ///
    /// - Parameters:
    ///   - catalog: the catalog to answer `search(intent:limit:)` calls over.
    ///   - config: this tier's session source, preamble, and budget.
    ///   - onDiagnostic: called for every diagnostic this tier emits.
    public init(
        catalog: any SelectionCatalog,
        config: SelectionConfig,
        onDiagnostic: @escaping @Sendable (RankDiagnostic) -> Void
    ) {
        self.catalog = catalog
        self.config = config
        self.assembledPrefix = Self.assemblePrefix(preamble: config.preamble, catalog: catalog)
        self.candidateRuns = Self.candidateRuns(
            preamble: config.preamble,
            catalog: catalog,
            limit: config.capacityCharacterLimit
        )
        self.onDiagnostic = onDiagnostic
    }

    /// Creates a selection tier and ignores `retrievalRanking`.
    ///
    /// The tier ranks nothing since task ^kqp9e5e, so the closure is never
    /// called. This initializer keeps a consumer that still passes one
    /// compiling (`FoundationModelsMetadataRegistry`'s `MetadataSearcher`
    /// builds the tier this way) until it moves to
    /// `init(catalog:config:onDiagnostic:)`.
    ///
    /// - Parameters:
    ///   - catalog: the catalog to answer `search(intent:limit:)` calls over.
    ///   - config: this tier's session source, preamble, and budget.
    ///   - onDiagnostic: called for every diagnostic this tier emits.
    ///   - retrievalRanking: ignored. The tier makes one prompt that picks
    ///     and never ranks the catalog.
    @available(
        *, deprecated,
        message: "The selection tier never ranks the catalog; `retrievalRanking` is ignored. Use init(catalog:config:onDiagnostic:)."
    )
    public init(
        catalog: any SelectionCatalog,
        config: SelectionConfig,
        onDiagnostic: @escaping @Sendable (RankDiagnostic) -> Void,
        retrievalRanking: @escaping @Sendable (String) async -> [SelectionMatch]
    ) {
        self.init(catalog: catalog, config: config, onDiagnostic: onDiagnostic)
    }

    /// Answers one `search(intent:limit:)` call with one prompt per run of
    /// candidates, and no retrieval pass.
    ///
    /// Under budget: reuses (creating on first use) this tier's cached root
    /// session, seeded with the full assembled prefix, and `fork()`s a fresh
    /// child per call so the prefix's prefilled compute is inherited rather
    /// than replayed. One prompt goes out, and its answer is the result.
    ///
    /// Over budget, the tier splits the catalog rather than cutting it. The
    /// catalog ids are divided, in catalog order, into runs whose assembled
    /// prefix each fits `capacityCharacterLimit` (`candidateRuns`). An entry
    /// that does not fit the budget alone still gets a run of its own,
    /// because the tier cannot make a prompt smaller than one entry. Each
    /// run gets one prompt on a one-off session, and every run is prompted
    /// before the result is cut to `limit`, so a later run's pick is never
    /// lost to an early stop. The answers are merged in run order, then in
    /// the model's order inside each run. The cost is one prompt per run per
    /// search, and no retrieval ranking picks which ids the model sees:
    /// every id reaches exactly one prompt.
    ///
    /// A `.session` source is forked once per prompt, so a session whose
    /// `fork()` gives back `self` (`LanguageModelSession`) adds one turn per
    /// run to its transcript on an over-budget search.
    ///
    /// - Parameters:
    ///   - intent: the plain-language search intent.
    ///   - limit: the maximum number of matches to return. `limit <= 0`
    ///     yields an empty result without forking or creating a session.
    /// - Returns: the selected ids' verbatim `SelectionMatch`es, in the
    ///   model's order, each scored by its position (`1 / rank`) and
    ///   carrying no `signals`, at most `limit`. A catalog with no ids
    ///   yields an empty result without forking or creating a session: it
    ///   has no id to select, and a model that gets a prompt with no
    ///   candidates answers with text that does not decode.
    /// - Throws: whatever the underlying session's
    ///   `fork()`/`respond(to:generating:)` throws.
    public func search(intent: String, limit: Int) async throws -> [SelectionMatch] {
        guard limit > 0 else { return [] }
        guard !catalog.ids.isEmpty else { return [] }
        guard assembledPrefix.count <= config.capacityCharacterLimit else {
            return matches(forIDs: try await selectFromEveryRun(intent: intent), limit: limit)
        }

        let child = try await cachedRootSession().fork()
        let selection = try await child.respond(
            to: prompt(prefix: assembledPrefix, intent: intent),
            generating: Selection.self
        )
        return matches(forIDs: selection.ids, limit: limit)
    }

    /// Returns this tier's cached root session, creating and caching it on
    /// first use.
    ///
    /// A `.factory` source makes the root from the full assembled prefix, so
    /// the prefix is the root's instructions. A `.session` source is the
    /// root as it stands: a live session takes no new instructions, so
    /// `prompt(prefix:intent:)` carries the prefix instead. Either root is
    /// forked once per call by `search(intent:limit:)`.
    ///
    /// - Returns: the cached root session -- every catalog id is a legal
    ///   selection under budget, since the assembled prefix already
    ///   summarizes the whole catalog.
    private func cachedRootSession() -> any AgentSession {
        if let rootSession { return rootSession }
        let session: any AgentSession
        switch config.sessionSource {
        case .factory(let makeSession):
            session = makeSession(assembledPrefix)
        case .session(let suppliedSession):
            session = suppliedSession
        }
        rootSession = session
        return session
    }

    /// Assembles the prompt for one model call.
    ///
    /// Both the cached-root path and the over-budget path prompt through
    /// this one function, so the two cannot drift apart.
    ///
    /// Every prompt puts the intent under a `# Task` heading, whatever the
    /// session source. The heading tells the model that the message names a
    /// task to *select candidates for*, not a task to *do*. Many search
    /// intents read as an order to the model itself -- "record my staged
    /// changes as a new commit", "how do I list or delete a branch" -- and a
    /// session that has answered nothing yet has nothing but the heading to
    /// tell the two apart. Measured on the on-device system model over
    /// `FullMonty`'s four demo queries, five cold runs each on a new
    /// `Searcher`: without the heading the two order-shaped queries answered
    /// 0 of 5 and 3 of 5; with it, every query answered 5 of 5. A session
    /// that has already answered once needs no heading, because its own
    /// transcript shows what an answer looks like, which is why the defect
    /// showed only on the first question of a new `Searcher`.
    ///
    /// The heading is where the two sources stop being alike. A `.factory`
    /// source already seeded `prefix` as the session's instructions, so its
    /// prompt is the heading and the intent. A `.session` source cannot take
    /// new instructions, so its prompt carries the whole prefix above the
    /// heading; without the prefix the model never sees the catalog and can
    /// return no id at all.
    ///
    /// - Parameters:
    ///   - prefix: this call's assembled candidate prefix -- the whole
    ///     catalog under budget, one run's candidates over budget.
    ///   - intent: the plain-language search intent.
    /// - Returns: the prompt text to send.
    private func prompt(prefix: String, intent: String) -> String {
        let task = "# Task\n\n\(intent)"
        switch config.sessionSource {
        case .factory:
            return task
        case .session:
            return "\(prefix)\n\n\(task)"
        }
    }

    // MARK: - Over budget: one prompt per run of candidates

    /// Answers one over-budget search: prompts every run of `candidateRuns`
    /// in turn and merges the answered ids in run order.
    ///
    /// The runs are prompted one after another, not concurrently, because a
    /// `.session` source forks one live session whose transcript grows with
    /// each prompt, and because the merged order is the run order.
    ///
    /// - Parameter intent: the plain-language search intent.
    /// - Returns: every id the model answered, run by run, in the model's
    ///   order inside each run. Not yet resolved, deduplicated, or cut to a
    ///   limit; `matches(forIDs:limit:)` does that.
    /// - Throws: whatever a one-off session's `fork()` or
    ///   `respond(to:generating:)` throws.
    private func selectFromEveryRun(intent: String) async throws -> [String] {
        var selectedIDs: [String] = []
        for run in candidateRuns {
            let prefix = Self.assemblePrefix(preamble: config.preamble, ids: run, catalog: catalog)
            let session = try await oneOffSession(instructions: prefix)
            let selection = try await session.respond(
                to: prompt(prefix: prefix, intent: intent),
                generating: Selection.self
            )
            selectedIDs.append(contentsOf: selection.ids)
        }
        return selectedIDs
    }

    /// Makes the session one over-budget prompt goes to.
    ///
    /// There is no stable prefix to cache over budget, since each run has
    /// its own. A `.factory` source makes a fresh session seeded with
    /// `instructions` and never forks it; a `.session` source forks the
    /// supplied session, because a live session takes no new instructions.
    ///
    /// - Parameter instructions: the run's assembled prefix.
    /// - Returns: the session to prompt for this run.
    /// - Throws: whatever the supplied session's `fork()` throws.
    private func oneOffSession(instructions: String) async throws -> any AgentSession {
        switch config.sessionSource {
        case .factory(let makeSession):
            return makeSession(instructions)
        case .session(let suppliedSession):
            return try await suppliedSession.fork()
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
            if !run.isEmpty, runCount + candidateSeparator.count + entry.count > limit {
                runs.append(run)
                run = []
                runCount = headerCount
            }
            runCount += (run.isEmpty ? 0 : candidateSeparator.count) + entry.count
            run.append(id)
        }
        if !run.isEmpty {
            runs.append(run)
        }
        return runs
    }

    // MARK: - Verbatim lookup and order scores

    /// Maps model-selected `ids` back through the catalog to verbatim
    /// `SelectionMatch`es (plan.md §6 "Verbatim lookup"), filtering any id
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

    /// Assembles this tier's instruction prefix (plan.md §6): `preamble`
    /// followed by a `# Candidates` header and one entry per catalog id, in
    /// catalog order. Each entry is the id as a markdown heading above the
    /// id's **`summaryBlock(forID:)`** — never `block(forID:)`, which stays
    /// reserved for the verbatim `SelectionMatch.block` a selected id looks
    /// up afterward (plan.md §4).
    ///
    /// - Parameters:
    ///   - preamble: the selection guidance to prepend.
    ///   - catalog: the catalog to assemble a prefix for.
    /// - Returns: the assembled prefix text.
    public static func assemblePrefix(preamble: String, catalog: any SelectionCatalog) -> String {
        assemblePrefix(preamble: preamble, ids: catalog.ids, catalog: catalog)
    }

    /// Assembles an instruction prefix for an arbitrary candidate id
    /// set (plan.md §6): `preamble` followed by a `# Candidates` header and
    /// one `candidateEntry(forID:catalog:)` per id, in `ids`' order —
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
        return "\(preamble)\n\n# Candidates\n\(entries.joined(separator: candidateSeparator))"
    }

    /// Renders one candidate's prefix entry: the candidate id as a markdown
    /// heading, with the id's `summaryBlock(forID:)` on the line below.
    ///
    /// The heading is what makes the id visible to the model. The preamble
    /// tells the model "Use only the ids shown", so the prefix must show
    /// which ids exist; a prefix of bare summaries makes the model answer with a
    /// summary, which then resolves to nothing and reports
    /// `.unknownSelectedId`. Both `assemblePrefix` overloads and
    /// `candidateRuns` render through this one function, so the paths
    /// cannot drift apart.
    ///
    /// - Parameters:
    ///   - id: the candidate id to render.
    ///   - catalog: the catalog to look the candidate summary up in.
    /// - Returns: the rendered entry, or `nil` if `id` isn't in `catalog`.
    private static func candidateEntry(forID id: String, catalog: any SelectionCatalog) -> String? {
        guard let summary = catalog.summaryBlock(forID: id) else { return nil }
        return "## \(id)\n\(summary)"
    }

    // MARK: - Guided-generation JSON Schema

    /// Makes the JSON Schema source text that limits `Selection.ids` to
    /// exactly `ids` (plan.md §6 "IDs only, grammar-enforced"). This is the
    /// same derived schema as Multitool's own
    /// `Librarian.grammarSchemaSource()`.
    ///
    /// The schema puts an `enum` constraint on the `items` subschema of the
    /// `ids` array. The `enum` prevents the model from inventing an id that
    /// is not in the current candidate set. The schema also sets `maxItems`
    /// to `ids.count`. This cap prevents the model from giving more ids than
    /// there are candidates. The cap is the backstop for `uniqueItems`, which
    /// the xgrammar pipeline ignores.
    ///
    /// This function gives the schema text only. A caller whose model
    /// backend accepts a JSON Schema grammar makes a grammar from the text
    /// with that backend's own grammar type, for example
    /// `Grammar.jsonSchema(SelectionTier.idEnumSchema(ids: ids))`.
    ///
    /// - Parameter ids: the candidate ids to limit the output to. Use the
    ///   full catalog's ids under budget, or the ids of one prompt's run
    ///   over budget.
    /// - Returns: the JSON Schema source text.
    /// - Throws: an encoding error if `Selection.generationSchema` cannot be
    ///   encoded to JSON. This is not expected for a valid `@Generable` type.
    ///   Throws `SelectionSchemaShapeError` if the encoded shape does not have
    ///   the expected `properties.ids.items` subschema to constrain. This is
    ///   not expected for `Selection`'s fixed shape.
    public static func idEnumSchema(ids: [String]) throws -> String {
        let data = try JSONEncoder().encode(Selection.generationSchema)
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            var properties = root["properties"] as? [String: Any],
            var idsSchema = properties["ids"] as? [String: Any],
            var itemsSchema = idsSchema["items"] as? [String: Any]
        else {
            throw SelectionSchemaShapeError()
        }

        itemsSchema["enum"] = ids
        idsSchema["items"] = itemsSchema
        // No duplicate ids in one selection -- pairs with the per-element
        // `enum` constraint above to make the *set* of ids structurally
        // exact, not just each individual element's membership.
        idsSchema["uniqueItems"] = true
        // Hard length cap -- the xgrammar pipeline enforces
        // `minItems`/`maxItems` but silently ignores `uniqueItems`, so
        // without this bound the compiled grammar permits an
        // unbounded-length array of repeated enum members (observed as a
        // ~6150-token runaway on an off-topic intent). A selection can
        // never legitimately contain more ids than there are candidates.
        idsSchema["maxItems"] = ids.count
        properties["ids"] = idsSchema
        root["properties"] = properties

        let constrained = try JSONSerialization.data(withJSONObject: root)
        return String(decoding: constrained, as: UTF8.self)
    }
}

/// Thrown by `SelectionTier.idEnumSchema(ids:)` if `Selection`'s encoded
/// `GenerationSchema` doesn't have the expected `properties.ids.items`
/// subschema shape to inject an `enum` constraint into — not expected for
/// `Selection`'s fixed shape, kept as a genuine (if practically unreachable)
/// failure mode rather than trapping.
public struct SelectionSchemaShapeError: Error, Sendable, Equatable {}
