// The default preamble constant is `.selectionDefault`. Its wording is
// neutral, with no "API librarian"/"functions" domain language, because
// this package never assumes the catalog is an API surface. The wording
// helps a small model answer a query that a candidate serves, and tells
// the model to copy each id exactly. The constant's doc comment records
// the measurement.

import FoundationModels

/// Configuration for a selection tier: the model that answers each prompt,
/// the guidance that starts the assembled prefix, and the capacity budget
/// that decides between one prompt and one prompt for each run of
/// candidates.
///
/// Collects the model, the preamble and the budget into one value type, so
/// a selection tier takes one configuration and not a set of initializer
/// overloads.
public struct SelectionConfig: Sendable {
    /// A generous default capacity, in characters, approximating a
    /// typical 8,192-token context budget at roughly 4 characters per
    /// token.
    public static let defaultCapacityCharacterLimit = 32_000

    /// The FoundationModels model that answers each selection prompt: for
    /// example `SystemLanguageModel.default`, or a `PooledModel` of
    /// FoundationModelsExtras. The tier makes a new `LanguageModelSession`
    /// on this model for each prompt, with the assembled prefix as its
    /// instructions, and asks for a `Selection` through the native guided
    /// generation of the session.
    public var model: any LanguageModel

    /// The selection guidance prepended to every assembled prefix. Defaults
    /// to `.selectionDefault`.
    public var preamble: String

    /// The assembled prefix's character budget. The budget measures the full
    /// prefix text: the preamble, and one `<candidate>` block for each
    /// candidate, with an `id:` line and a `description:` line that holds
    /// the candidate's summary block. At or under this budget, the tier
    /// sends one prompt. Over it, the tier splits the catalog into runs whose
    /// prefix each fits this budget and sends one prompt per run
    /// (`SelectionTier.search(intent:limit:)`). Negative values are clamped
    /// to `0`.
    public var capacityCharacterLimit: Int

    /// Creates a selection tier configuration.
    ///
    /// - Parameters:
    ///   - model: the model that answers each selection prompt. The caller
    ///     always chooses it.
    ///   - preamble: the selection guidance prepended to every assembled
    ///     prefix. Defaults to `.selectionDefault`.
    ///   - capacityCharacterLimit: the assembled prefix's character
    ///     budget. Defaults to `defaultCapacityCharacterLimit`. A negative
    ///     value is clamped to `0`.
    public init(
        model: any LanguageModel,
        preamble: String = .selectionDefault,
        capacityCharacterLimit: Int = SelectionConfig.defaultCapacityCharacterLimit
    ) {
        self.model = model
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
    /// surface. It keeps the rule: the fewest candidates that suffice, in
    /// order of use when order matters.
    ///
    /// **The exact-id paragraph.** Each candidate entry of the prefix is a
    /// `<candidate>` block with an `id:` line and a `description:` line
    /// (`SelectionTier.assemblePrefix`). When an id is a `## <id>` heading
    /// and no sentence tells the model to copy the id, the heading reads
    /// like a title. Then a real model (`mlx-community/Qwen3-4B-4bit`, and
    /// the on-device system model) answered `"quantum-flux-capacitor"` for
    /// the id `https://example.com/modules/quantum-flux-capacitor`, and the
    /// tier dropped that answer as an unknown id. The second paragraph tells
    /// the model to copy each id from its `id:` line, whole.
    ///
    /// **The empty-answer paragraph.** A default that
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
