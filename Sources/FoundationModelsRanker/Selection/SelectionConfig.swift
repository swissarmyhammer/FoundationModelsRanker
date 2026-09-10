// Ported from FoundationModelsMetadataRegistry's
// `Sources/FoundationModelsMetadataRegistry/Selection/SelectionConfig.swift`
// (plan.md §6 phase 3). Behavior unchanged (defaults, clamping); the one
// deliberate diff is the default preamble constant, renamed from
// `.librarianDefault` to `.selectionDefault` with neutral wording -- no
// "API librarian"/"functions" domain language, since FoundationModelsRanker's catalog is
// never assumed to be an API surface. Card ^zxm99zs then reworded the
// default so a small model answers a query that a candidate serves; the
// constant's doc comment records the measurement.
//
// A session factory takes only the instructions text. A caller that wants
// guided generation applies its own grammar when it makes the session. A
// session's grammar is set at creation, and a `fork()` of that session
// inherits it. `SelectionTier.idEnumSchema(ids:)` gives such a caller the id
// set.
//
// Task ^kqp9e5e removed `candidateLimit`. It sized the retrieval cut the
// over-budget path made before its one-off prompt. The tier now splits an
// over-budget catalog into several prompts and cuts nothing, so the knob had
// no function left.

/// Where a selection tier gets the session it asks the model through.
///
/// Two kinds of caller need two different seams. A caller that can make a
/// session for each prefix gives a factory, and the tier seeds each session
/// with the assembled candidate prefix as its instructions. A caller that
/// already holds one live session gives that session instead: a live session
/// takes no new instructions, so a factory that ignores the prefix would
/// throw the catalog away and the model would never see it.
public enum SelectionSessionSource: Sendable {
    /// Makes a new session for each assembled prefix. The prefix becomes the
    /// session's instructions, so the prompt carries the intent alone, under
    /// the `# Task` heading every prompt puts the intent under.
    case factory(@Sendable (String) -> any AgentSession)

    /// Reuses one supplied session. The tier forks the session for each
    /// prompt, and the prefix rides above the `# Task` heading on each
    /// prompt.
    case session(any AgentSession)
}

/// Configuration for a selection tier: how selection sessions are created,
/// what guidance seeds the assembled prefix, and the capacity budget that
/// decides between the cached-root path and the split, one-off session path.
///
/// Generalizes Multitool's own `Librarian` initializer parameters
/// (`capacityCharacterLimit`, `makeSession`) into one value type so a
/// selection tier can accept -- or omit -- a selection configuration
/// without a combinatorial explosion of initializer overloads.
public struct SelectionConfig: Sendable {
    /// A generous default capacity, in characters, approximating a
    /// typical 8,192-token context budget at roughly 4 characters per
    /// token -- identical to Multitool's own
    /// `Librarian.defaultCapacityCharacterLimit`.
    public static let defaultCapacityCharacterLimit = 32_000

    /// Where this tier's sessions come from -- the seam a selection tier
    /// drives both the cached root session and the over-budget one-off
    /// sessions through. `Sendable` so it can cross a selection tier's actor
    /// isolation boundary.
    ///
    /// A caller that wants guided generation applies its own grammar when it
    /// makes the session, because a session's grammar is set at creation and
    /// a `fork()` of that session inherits it.
    /// `SelectionTier.idEnumSchema(ids:)` gives such a caller the id set.
    public var sessionSource: SelectionSessionSource

    /// The selection guidance prepended to every assembled prefix. Defaults
    /// to `.selectionDefault`.
    public var preamble: String

    /// The assembled prefix's character budget. The budget measures the full
    /// prefix text: the preamble, the `# Candidates` header, and one
    /// `## <id>` heading above each candidate's summary block. At or under
    /// this budget, the cached-root + fork-per-call path runs with one
    /// prompt. Over it, the tier splits the catalog into runs whose prefix
    /// each fits this budget and sends one prompt per run
    /// (`SelectionTier.search(intent:limit:)`). Negative values are clamped
    /// to `0`.
    public var capacityCharacterLimit: Int

    /// Creates a selection tier configuration that makes a session for each
    /// assembled prefix -- a `.factory` session source.
    ///
    /// - Parameters:
    ///   - model: creates a session seeded with the given instructions
    ///     text.
    ///   - preamble: the selection guidance prepended to every assembled
    ///     prefix. Defaults to `.selectionDefault`.
    ///   - capacityCharacterLimit: the assembled prefix's character
    ///     budget. Defaults to `defaultCapacityCharacterLimit`.
    public init(
        model: @escaping @Sendable (String) -> any AgentSession,
        preamble: String = .selectionDefault,
        capacityCharacterLimit: Int = SelectionConfig.defaultCapacityCharacterLimit
    ) {
        self.init(
            sessionSource: .factory(model),
            preamble: preamble,
            capacityCharacterLimit: capacityCharacterLimit
        )
    }

    /// Creates a selection tier configuration that reuses one live session --
    /// a `.session` session source.
    ///
    /// A live session takes no new instructions, so the tier forks this
    /// session for each prompt and puts the assembled prefix in the prompt.
    ///
    /// - Parameters:
    ///   - session: the session every selection prompt forks a child from.
    ///   - preamble: the selection guidance prepended to every assembled
    ///     prefix. Defaults to `.selectionDefault`.
    ///   - capacityCharacterLimit: the assembled prefix's character
    ///     budget. Defaults to `defaultCapacityCharacterLimit`.
    public init(
        session: any AgentSession,
        preamble: String = .selectionDefault,
        capacityCharacterLimit: Int = SelectionConfig.defaultCapacityCharacterLimit
    ) {
        self.init(
            sessionSource: .session(session),
            preamble: preamble,
            capacityCharacterLimit: capacityCharacterLimit
        )
    }

    /// Creates a selection tier configuration from an already-chosen session
    /// source -- the one place the budget is clamped, so both public
    /// initializers above clamp identically.
    ///
    /// - Parameters:
    ///   - sessionSource: where this tier's sessions come from.
    ///   - preamble: the selection guidance prepended to every assembled
    ///     prefix.
    ///   - capacityCharacterLimit: the assembled prefix's character budget.
    private init(
        sessionSource: SelectionSessionSource,
        preamble: String,
        capacityCharacterLimit: Int
    ) {
        self.sessionSource = sessionSource
        self.preamble = preamble
        self.capacityCharacterLimit = max(0, capacityCharacterLimit)
    }
}

extension String {
    /// The selection guidance every `SelectionConfig` defaults its
    /// `preamble` to.
    ///
    /// The text says what the candidates are, what an answer is, and when
    /// an empty answer is right. It speaks of items and ids, never of
    /// functions, because a catalog is never assumed to be an API surface
    /// (plan.md §6 phase 3). It keeps the rule every earlier default carried:
    /// "fewest that suffice, in call order when order matters."
    ///
    /// **The text decides whether a small model answers at all, and it was
    /// measured** (card `^zxm99zs`). The default that shipped before it read
    /// "Given a task, return ONLY the items needed — fewest that suffice, in
    /// call order when order matters. Do not invent ids; return an empty list
    /// if nothing fits." Driven over a nine-function catalog (files read,
    /// write, edit, patch, glob, grep; shell execute, getLines, grepHistory)
    /// with the ten queries a consumer's agent asked, three rounds each:
    ///
    /// - `mlx-community/Qwen3-4B-4bit`, over the consumer's own catalog and
    ///   grammar, answered 0 of 30 with the earlier default and 30 of 30 with
    ///   this text. The consumer's own wording, which names the candidates as
    ///   functions, answered 30 of 30 as well.
    /// - The on-device system model, one cold session for each query,
    ///   answered 27 of 30 with the earlier default ("file operations:
    ///   create, write, append, delete, move" answered 0 of 3) and 30 of 30
    ///   with this text. One cached root session for all ten queries
    ///   answered 30 of 30 with both.
    /// - `FullMonty`'s four demo queries answered 12 of 12 on both models with
    ///   every wording.
    ///
    /// The grammar, the prompt, and the candidate blocks were the same in
    /// every run. The sentence that decides the empty case is the last one:
    /// a model told only to "return an empty list if nothing fits" returns
    /// it for a query that a candidate serves.
    public static let selectionDefault: String = """
        The candidates below are the items available to do a task, each under its id. Given a task, \
        answer with the ids of the candidates that do it — the fewest that suffice, in call order when \
        order matters. Use only the ids shown. Prefer the closest candidates over an empty answer; \
        answer with an empty list only when no candidate is related to the task at all.
        """
}
