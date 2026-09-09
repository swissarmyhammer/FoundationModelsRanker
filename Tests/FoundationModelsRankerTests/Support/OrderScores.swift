/// The scores a selection pick carries by its position in the model's
/// answer, named so a test can assert them without an unnamed literal.
///
/// A selection tier scores its picks by order alone: the first pick scores
/// `1.0`, and the n-th pick scores `1 / n`. `SelectionMatch.score` documents
/// the rule; these constants are its first three values.
enum OrderScores {
    /// The score of the first pick.
    static let firstPick = 1.0

    /// The score of the second pick.
    static let secondPick = 1.0 / 2.0

    /// The score of the third pick.
    static let thirdPick = 1.0 / 3.0
}
