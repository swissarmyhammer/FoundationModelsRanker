// Ported from FoundationModelsMetadataRegistry's
// `Sources/FoundationModelsMetadataRegistry/Selection/SelectionTier.swift`
// (plan.md §6 phase 3), generalized over `any SelectionCatalog` instead of
// `MetadataIndex<Item>`: `index.ids`/`item(forID:)`/`block(forID:)`/
// `renderSummaryBlock()` map onto `catalog.ids`/`summaryBlock(forID:)`/
// `block(forID:)`; `Match<Item>` becomes `SelectionMatch` (no catalog item to
// carry); `MetadataDiagnostic` becomes `RankDiagnostic`. Semantics unchanged.

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
/// selection prefix; retrieval indexes the full `block(forID:)` instead)
/// once at `init`, since the catalog never changes for this tier's lifetime
/// — a reload replaces the whole tier rather than mutating one in place.
///
/// **Under budget** (assembled prefix ≤ `capacityCharacterLimit`): a cached
/// root session is seeded once with the prefix, and each
/// `search(intent:limit:)` `fork()`s a fresh child from it, so the prefix's
/// KV cache is prefilled once and inherited per call — lifted from
/// `Librarian.findAPIs(task:)`'s cached-root + fork-per-call mechanics.
/// `retrievalRanking` then ranks the whole catalog once per call so every
/// selected id carries its real fused `score`/`signals` (plan.md §3a); the
/// whole catalog stays selectable, so no `.retrievalCut` is reported.
///
/// **Over budget**: `retrievalRanking` ranks the whole catalog for the
/// intent, and the top `config.candidateLimit` candidates (best-first) go to
/// a **fresh, uncached one-off session** — there is no stable
/// prefix to reuse, since the candidate set differs per intent. The cut is
/// reported via `RankDiagnostic.retrievalCut(considered:kept:)` (the
/// `onPrefilterCut` pattern, generalized to ranked retrieval). Returned
/// `SelectionMatch`es carry the same real fused `score`/`signals` as the
/// under-budget path's, and a selected id outside this round's candidates —
/// even a legitimate id from elsewhere in the wider catalog — is filtered
/// and reported via `.unknownSelectedId`, exactly like an id absent from
/// the catalog altogether.
///
/// **Where the prefix goes** follows `SelectionConfig.sessionSource`. A
/// `.factory` source seeds the prefix as each session's instructions, so the
/// prompt carries the intent alone, under a `# Task` heading. A `.session`
/// source hands over one live session, which takes no new instructions: the
/// tier forks that session for each call and carries the prefix above the
/// same heading instead (`prompt(prefix:intent:)`). Either way the model sees
/// the same prefix, and reads the intent as a task to select for.
///
/// **IDs only** (plan.md §6, decision #4): the guided output is
/// `Selection { ids: [String] }`. The assembled prefix shows every candidate
/// id as a markdown heading, so the model can read the ids it may return.
/// This tier applies no grammar of its own: a caller that wants guided
/// generation applies one when it makes the session, and
/// `idEnumSchema(ids:)` gives that caller the id set — the whole catalog
/// under budget, the top-M ranked ids over budget. Returned ids map back
/// through the catalog to verbatim `SelectionMatch`es; an id outside the
/// current candidate set is filtered and reported via
/// `RankDiagnostic.unknownSelectedId(id:)`.
public actor SelectionTier {
    /// The full catalog this tier answers `search(intent:limit:)` calls
    /// over.
    private let catalog: any SelectionCatalog

    /// This tier's session source, preamble, and capacity/candidate budgets.
    private let config: SelectionConfig

    /// `assemblePrefix(preamble:catalog:)`, precomputed once at `init` since
    /// `catalog` never changes for this tier's lifetime.
    private let assembledPrefix: String

    /// Called for every diagnostic this tier emits (currently
    /// `.unknownSelectedId` and `.retrievalCut`).
    private let onDiagnostic: @Sendable (RankDiagnostic) -> Void

    /// Ranks the whole catalog for one intent, best-first, always returning
    /// exactly as many `SelectionMatch`es as the catalog has entries — the
    /// over-budget path's source of top-M candidates, and the under-budget
    /// path's source of the real `score`/`signals` every selected id
    /// carries. A consumer composing this tier with FoundationModelsRanker's
    /// own `HybridRanker` wires this to
    /// `HybridRanker.fullOrdering(ids:documents:query:cosineScores:weights:)`
    /// mapped into `SelectionMatch`; tests script it directly.
    private let retrievalRanking: @Sendable (String) async -> [SelectionMatch]

    /// This tier's cached root session — `nil` until the first under-budget
    /// `search(intent:limit:)` call creates and caches it.
    private var rootSession: (any AgentSession)?

    /// Creates a selection tier over `catalog`, using `config`'s session
    /// source, preamble, and budgets.
    ///
    /// - Parameters:
    ///   - catalog: the catalog to answer `search(intent:limit:)` calls over.
    ///   - config: this tier's session source, preamble, and budgets.
    ///   - onDiagnostic: called for every diagnostic this tier emits.
    ///   - retrievalRanking: ranks the whole catalog for one intent,
    ///     best-first — the over-budget path's source of top-M candidates,
    ///     and the under-budget path's source of every selected id's real
    ///     `score`/`signals`.
    public init(
        catalog: any SelectionCatalog,
        config: SelectionConfig,
        onDiagnostic: @escaping @Sendable (RankDiagnostic) -> Void,
        retrievalRanking: @escaping @Sendable (String) async -> [SelectionMatch]
    ) {
        self.catalog = catalog
        self.config = config
        self.assembledPrefix = Self.assemblePrefix(preamble: config.preamble, catalog: catalog)
        self.onDiagnostic = onDiagnostic
        self.retrievalRanking = retrievalRanking
    }

    /// Answers one `search(intent:limit:)` call.
    ///
    /// Under budget: reuses (creating on first use) this tier's cached root
    /// session, seeded with the full assembled prefix, and `fork()`s a fresh
    /// child per call so the prefix's prefilled compute is inherited rather
    /// than replayed; `retrievalRanking` then ranks the whole catalog once
    /// so every selected id carries its real fused `score`/`signals`. The
    /// whole catalog stays selectable — no candidate cut happens, so no
    /// `.retrievalCut` is reported. That enrichment costs one
    /// `retrievalRanking` pass per call, which includes one query-embedding
    /// call when the consumer's ranking uses an embedder. Over budget: ranks
    /// the whole catalog and gives a one-off session the top-M
    /// candidates (`overBudgetSearch(intent:limit:)`, plan.md §6) — no
    /// caching, and no cached root to fork.
    ///
    /// - Parameters:
    ///   - intent: the plain-language search intent.
    ///   - limit: the maximum number of matches to return. `limit <= 0`
    ///     yields an empty result without forking, creating a session, or
    ///     ranking anything.
    /// - Returns: the selected ids' verbatim `SelectionMatch`es, each
    ///   carrying the real fused `score`/`signals` `retrievalRanking`
    ///   reported for it, at most `limit`.
    /// - Throws: whatever the underlying session's
    ///   `fork()`/`respond(to:generating:)` throws.
    public func search(intent: String, limit: Int) async throws -> [SelectionMatch] {
        guard limit > 0 else { return [] }
        guard assembledPrefix.count <= config.capacityCharacterLimit else {
            return try await overBudgetSearch(intent: intent, limit: limit)
        }

        let child = try await cachedRootSession().fork()
        let selection = try await child.respond(
            to: prompt(prefix: assembledPrefix, intent: intent),
            generating: Selection.self
        )
        // Ranked after the model call, so a throwing session never pays the
        // retrieval (and query-embedding) cost -- the full ordering resolves
        // every catalog id, including the zero-scored tail, to its real
        // fused score/signals.
        let ranked = await retrievalRanking(intent)
        return matches(
            forIDs: selection.ids,
            limit: limit,
            retrievalMatches: Dictionary(uniqueKeysWithValues: ranked.map { ($0.id, $0) })
        )
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

    /// Assembles the prompt for one `search(intent:limit:)` call.
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
    ///     catalog under budget, this round's top-M candidates over budget.
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

    // MARK: - Over budget: retrieval top-M + one-off session

    /// Answers one over-budget `search(intent:limit:)` call (plan.md §6
    /// "Over budget"): ranks the whole catalog through `retrievalRanking`,
    /// takes the top `config.candidateLimit` candidates (best-first —
    /// always `min(config.candidateLimit, considered)` of them, even when
    /// few or none score positively, so the model always has a full
    /// candidate set to pick from), reports the cut via
    /// `.retrievalCut(considered:kept:)`, and answers on a **fresh,
    /// uncached** one-off session carrying exactly those candidates' ids and
    /// `summaryBlock(forID:)`s — there is no stable prefix here to reuse,
    /// since the candidate set differs per intent. A `.factory` source makes
    /// that session and never forks it; a `.session` source forks the
    /// supplied session, because a live session takes no new instructions.
    ///
    /// - Parameters:
    ///   - intent: the plain-language search intent.
    ///   - limit: the maximum number of matches to return.
    /// - Returns: the selected candidates' verbatim `SelectionMatch`es,
    ///   carrying the real retrieval `score`/`signals` that ranked them, at
    ///   most `limit`.
    /// - Throws: whatever the one-off session's `respond(to:generating:)`
    ///   throws.
    private func overBudgetSearch(intent: String, limit: Int) async throws -> [SelectionMatch] {
        let ranked = await retrievalRanking(intent)
        let candidates = Array(ranked.prefix(config.candidateLimit))
        onDiagnostic(.retrievalCut(considered: ranked.count, kept: candidates.count))

        // Nothing to seed a session with -- and nothing worth asking a
        // model to choose among -- when the catalog itself is empty.
        guard !candidates.isEmpty else { return [] }

        let candidateIDs = candidates.map(\.id)
        let prefix = Self.assemblePrefix(preamble: config.preamble, ids: candidateIDs, catalog: catalog)
        // There is no cached root here, so a `.session` source forks the
        // supplied session for this one call.
        let session: any AgentSession
        switch config.sessionSource {
        case .factory(let makeSession):
            session = makeSession(prefix)
        case .session(let suppliedSession):
            session = try await suppliedSession.fork()
        }
        let selection = try await session.respond(
            to: prompt(prefix: prefix, intent: intent),
            generating: Selection.self
        )
        return matches(
            forIDs: selection.ids,
            limit: limit,
            allowedIDs: Set(candidateIDs),
            retrievalMatches: Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0) })
        )
    }

    /// Maps model-selected `ids` back through the catalog to verbatim
    /// `SelectionMatch`es (plan.md §6 "Verbatim lookup"), filtering any id
    /// not resolvable and reporting it via `.unknownSelectedId` — the
    /// backstop against a model that answers with an id the current
    /// candidate set does not hold — deduplicating repeats (first
    /// occurrence wins, which keeps the model's own call-order intent)
    /// without reporting a diagnostic for them, and truncating to `limit`.
    ///
    /// - Parameters:
    ///   - ids: the model-selected ids, in the order the model returned them.
    ///   - limit: the maximum number of matches to return.
    ///   - allowedIDs: restricts resolution to this id set (the over-budget
    ///     path's current candidates) in addition to the catalog itself; an
    ///     id absent from `allowedIDs` is treated exactly like an id absent
    ///     from the catalog. `nil` (the under-budget default) allows any
    ///     catalog id.
    ///   - retrievalMatches: the retrieval `SelectionMatch` (real fused
    ///     `score` and `signals`) for every resolvable id, keyed by id — the
    ///     full-catalog ordering under budget, this round's candidates over
    ///     budget. An id absent from it is treated exactly like an id absent
    ///     from the catalog (structurally unreachable for both callers:
    ///     `retrievalRanking` covers every catalog id, and the over-budget
    ///     `allowedIDs` are exactly its candidates' keys).
    /// - Returns: the verbatim `SelectionMatch`es for every known, allowed,
    ///   first-seen id, each carrying its retrieval `score`/`signals`, at
    ///   most `limit`.
    private func matches(
        forIDs ids: [String],
        limit: Int,
        allowedIDs: Set<String>? = nil,
        retrievalMatches: [String: SelectionMatch]
    ) -> [SelectionMatch] {
        var results: [SelectionMatch] = []
        results.reserveCapacity(min(ids.count, limit))
        var seenIDs: Set<String> = []
        for id in ids {
            guard results.count < limit else { break }
            guard seenIDs.insert(id).inserted else { continue }
            guard allowedIDs?.contains(id) ?? true,
                let block = catalog.block(forID: id),
                let retrievalMatch = retrievalMatches[id]
            else {
                onDiagnostic(.unknownSelectedId(id: id))
                continue
            }
            results.append(
                SelectionMatch(
                    id: id,
                    block: block,
                    score: retrievalMatch.score,
                    signals: retrievalMatch.signals
                )
            )
        }
        return results
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
    /// `ids: catalog.ids`; the over-budget path passes the top-M ranked ids
    /// instead, best-first. An id the catalog has no summary for is left
    /// out, exactly as the catalog itself reports it absent.
    ///
    /// - Parameters:
    ///   - preamble: the selection guidance to prepend.
    ///   - ids: the candidate ids to render, in the order they should appear.
    ///   - catalog: the catalog to look candidate summaries up in.
    /// - Returns: the assembled prefix text.
    public static func assemblePrefix(preamble: String, ids: [String], catalog: any SelectionCatalog) -> String {
        let entries = ids.compactMap { candidateEntry(forID: $0, catalog: catalog) }
        return "\(preamble)\n\n# Candidates\n\(entries.joined(separator: "\n\n"))"
    }

    /// Renders one candidate's prefix entry: the candidate id as a markdown
    /// heading, with the id's `summaryBlock(forID:)` on the line below.
    ///
    /// The heading is what makes the id visible to the model. The preamble
    /// tells the model "Do not invent ids", so the prefix must show which
    /// ids exist; a prefix of bare summaries makes the model answer with a
    /// summary, which then resolves to nothing and reports
    /// `.unknownSelectedId`. Both `assemblePrefix` overloads render through
    /// this one function, so the two paths cannot drift apart.
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
    ///   full catalog's ids under budget, or the top-M ranked ids over
    ///   budget.
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
