// Ported from FoundationModelsMetadataRegistry's
// `Sources/FoundationModelsMetadataRegistry/Selection/SelectionConfig.swift`
// (plan.md §6 phase 3). Behavior unchanged (defaults, clamping); the one
// deliberate diff is the default preamble constant, renamed from
// `.librarianDefault` to `.selectionDefault` with neutral wording -- no
// "API librarian"/"functions" domain language, since FoundationModelsRanker's catalog is
// never assumed to be an API surface.
//
// A session factory takes only the instructions text. A caller that wants
// guided generation applies its own grammar when it makes the session. A
// session's grammar is set at creation, and a `fork()` of that session
// inherits it. `SelectionTier.idEnumSchema(ids:)` gives such a caller the id
// set.

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
    /// session's instructions, so the prompt is the intent alone.
    case factory(@Sendable (String) -> any AgentSession)

    /// Reuses one supplied session. The tier forks the session for each
    /// call, and the prefix rides above the intent on each prompt.
    case session(any AgentSession)
}

/// Configuration for a selection tier: how selection sessions are created,
/// what guidance seeds the assembled prefix, and the capacity/candidate
/// budgets that decide between the cached-root and one-off session paths.
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

    /// The default number of top-ranked candidates the over-budget path
    /// seeds its one-off session with.
    public static let defaultCandidateLimit = 24

    /// Where this tier's sessions come from -- the seam a selection tier
    /// drives both the cached root session and the over-budget one-off
    /// session through. `Sendable` so it can cross a selection tier's actor
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

    /// The assembled prefix's character budget (preamble + every
    /// candidate's summary block); at or under this, the cached-root +
    /// fork-per-call path runs. Negative values are clamped to `0`.
    public var capacityCharacterLimit: Int

    /// Over budget, how many top-ranked retrieval candidates seed the
    /// one-off session. Negative values are clamped to `0`.
    public var candidateLimit: Int

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
    ///   - candidateLimit: the over-budget top-M candidate count. Defaults
    ///     to `defaultCandidateLimit`.
    public init(
        model: @escaping @Sendable (String) -> any AgentSession,
        preamble: String = .selectionDefault,
        capacityCharacterLimit: Int = SelectionConfig.defaultCapacityCharacterLimit,
        candidateLimit: Int = SelectionConfig.defaultCandidateLimit
    ) {
        self.init(
            sessionSource: .factory(model),
            preamble: preamble,
            capacityCharacterLimit: capacityCharacterLimit,
            candidateLimit: candidateLimit
        )
    }

    /// Creates a selection tier configuration that reuses one live session --
    /// a `.session` session source.
    ///
    /// A live session takes no new instructions, so the tier forks this
    /// session for each call and puts the assembled prefix in the prompt.
    ///
    /// - Parameters:
    ///   - session: the session every selection call forks a child from.
    ///   - preamble: the selection guidance prepended to every assembled
    ///     prefix. Defaults to `.selectionDefault`.
    ///   - capacityCharacterLimit: the assembled prefix's character
    ///     budget. Defaults to `defaultCapacityCharacterLimit`.
    ///   - candidateLimit: the over-budget top-M candidate count. Defaults
    ///     to `defaultCandidateLimit`.
    public init(
        session: any AgentSession,
        preamble: String = .selectionDefault,
        capacityCharacterLimit: Int = SelectionConfig.defaultCapacityCharacterLimit,
        candidateLimit: Int = SelectionConfig.defaultCandidateLimit
    ) {
        self.init(
            sessionSource: .session(session),
            preamble: preamble,
            capacityCharacterLimit: capacityCharacterLimit,
            candidateLimit: candidateLimit
        )
    }

    /// Creates a selection tier configuration from an already-chosen session
    /// source -- the one place the budgets are clamped, so both public
    /// initializers above clamp identically.
    ///
    /// - Parameters:
    ///   - sessionSource: where this tier's sessions come from.
    ///   - preamble: the selection guidance prepended to every assembled
    ///     prefix.
    ///   - capacityCharacterLimit: the assembled prefix's character budget.
    ///   - candidateLimit: the over-budget top-M candidate count.
    private init(
        sessionSource: SelectionSessionSource,
        preamble: String,
        capacityCharacterLimit: Int,
        candidateLimit: Int
    ) {
        self.sessionSource = sessionSource
        self.preamble = preamble
        self.capacityCharacterLimit = max(0, capacityCharacterLimit)
        self.candidateLimit = max(0, candidateLimit)
    }
}

extension String {
    /// The curated selection guidance every `SelectionConfig` defaults its
    /// `preamble` to -- a neutral rewrite of Multitool's shipped
    /// `Librarian.selectionGuidance` ("You are an API librarian ... return
    /// ONLY the functions needed"), generalized to items/ids rather than
    /// functions so it carries no domain-specific language (plan.md §6
    /// phase 3): "fewest that suffice, in call order when order matters."
    public static let selectionDefault: String = """
        Given a task, return ONLY the items needed — fewest that suffice, in call order when
        order matters. Do not invent ids; return an empty list if nothing fits.
        """
}
