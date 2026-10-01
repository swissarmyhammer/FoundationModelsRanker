/// The prompt text that `SelectionTier` sends to a session, written one time
/// for each test that pins it.
///
/// The text is a literal and not a call into the tier, so a change to the
/// prompt the tier sends makes the tests fail.
enum ExpectedSelectionPrompt {
    /// The request part of each selection prompt: the intent in a
    /// `<request>` block, then the line that asks for the exact ids and
    /// names the ids of the prompt's candidates as the only choices.
    ///
    /// A `.factory` session gets this text alone. A `.session` session gets
    /// the assembled prefix, one blank line, and then this text.
    ///
    /// - Parameters:
    ///   - intent: the plain-language search intent.
    ///   - ids: the candidate ids of the prompt, in prefix order: the whole
    ///     catalog under budget, one run over budget.
    /// - Returns: the request text for `intent` over `ids`.
    static func request(for intent: String, ids: [String]) -> String {
        "<request>\n\(intent)\n</request>\nAnswer with the exact ids of the chosen candidates. "
            + "Choose only from these ids: \(ids.joined(separator: ", "))."
    }
}
