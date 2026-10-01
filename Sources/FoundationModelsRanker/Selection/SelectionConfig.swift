// Ported from FoundationModelsMetadataRegistry's
// `Sources/FoundationModelsMetadataRegistry/Selection/SelectionConfig.swift`.
// Behavior unchanged (defaults, clamping); the one
// deliberate diff is the default preamble constant, renamed from
// `.librarianDefault` to `.selectionDefault` with neutral wording -- no
// "API librarian"/"functions" domain language, since FoundationModelsRanker's catalog is
// never assumed to be an API surface. Card ^zxm99zs then reworded the
// default so a small model answers a query that a candidate serves; the
// constant's doc comment records the measurement. Card ^knyvhkf then added
// the paragraph that tells the model to copy each id exactly.
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
    /// session's instructions, so the prompt carries only the request part:
    /// the intent in the `<request>` block that every prompt puts the intent
    /// in, and the line that asks for the exact ids.
    ///
    /// The factory can `await` and `throw`: a session can come from a pooled
    /// model that loads at the first request. An error from the factory
    /// comes out of `SelectionTier.search(intent:limit:)`. A synchronous
    /// closure is also a factory.
    case factory(@Sendable (String) async throws -> any AgentSession)

    /// Reuses one supplied session. The tier forks the session for each
    /// prompt, and the prefix rides above the request part of each prompt.
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
    /// prefix text: the preamble, and one `<candidate>` block for each
    /// candidate, with an `id:` line and a `description:` line that holds
    /// the candidate's summary block. At or under
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
    ///     text. It can `await` (for example, while a pooled model loads)
    ///     and `throw`; an error from it comes out of the search that asked
    ///     for the session.
    ///   - preamble: the selection guidance prepended to every assembled
    ///     prefix. Defaults to `.selectionDefault`.
    ///   - capacityCharacterLimit: the assembled prefix's character
    ///     budget. Defaults to `defaultCapacityCharacterLimit`.
    public init(
        model: @escaping @Sendable (String) async throws -> any AgentSession,
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
    /// The text has three paragraphs. The first says what the candidates
    /// are and which candidates to choose. The second says that an answer
    /// is the exact id of each chosen candidate. The third says when an
    /// empty answer is correct. The text speaks of candidates and ids,
    /// never of functions, because a catalog is never assumed to be an API
    /// surface. It keeps the rule every earlier default carried: the fewest
    /// candidates that suffice, in order of use when order matters.
    ///
    /// **The exact-id paragraph (card `^knyvhkf`).** Each candidate entry of
    /// the prefix is a `<candidate>` block with an `id:` line and a
    /// `description:` line (`SelectionTier.assemblePrefix`). Before that,
    /// each id was a `## <id>` heading, and no sentence told the model to
    /// copy the id. A heading reads like a title, so a real model
    /// (`mlx-community/Qwen3-4B-4bit`, and the on-device system model
    /// before it) answered `"quantum-flux-capacitor"` for the id
    /// `https://example.com/modules/quantum-flux-capacitor`. The tier then
    /// dropped that answer as an unknown id. The second paragraph tells the
    /// model to copy each id from its `id:` line, whole.
    ///
    /// **The empty-answer paragraph (card `^zxm99zs`).** A default that
    /// read "return an empty list if nothing fits" made
    /// `mlx-community/Qwen3-4B-4bit` answer 0 of 30 over a nine-function
    /// catalog with ten consumer queries, three rounds each, and made the
    /// on-device system model answer 27 of 30. A default that permits an
    /// empty list only when no candidate is related to the request answered
    /// 30 of 30 on both models.
    public static let selectionDefault: String = """
        Each candidate below has an id and a description. Given a request, choose the candidates \
        that serve it: the fewest that suffice, in order of use when order matters.

        Answer with the id of each chosen candidate. Copy each id exactly as it is written after \
        "id:", character for character, with its full scheme, path and punctuation. An id is not a \
        name or a title: do not shorten it, change it or make one up.

        Answer with an empty list only when no candidate is related to the request at all.
        """
}
