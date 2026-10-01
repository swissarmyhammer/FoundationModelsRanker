/// The prompt text that `SelectionTier` sends to a session, written one time
/// for each test that pins it.
///
/// The text is a literal and not a call into the tier, so a change to the
/// prompt the tier sends makes the tests fail.
enum ExpectedSelectionPrompt {
    /// The request part of each selection prompt: the intent in a
    /// `<request>` block, then the line that asks for the exact ids.
    ///
    /// A `.factory` session gets this text alone. A `.session` session gets
    /// the assembled prefix, one blank line, and then this text.
    ///
    /// - Parameter intent: the plain-language search intent.
    /// - Returns: the request text for `intent`.
    static func request(for intent: String) -> String {
        "<request>\n\(intent)\n</request>\nAnswer with the exact ids of the chosen candidates."
    }
}
