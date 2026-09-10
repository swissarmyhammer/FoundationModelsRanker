/// The scores a selection pick carries by its position in the model's
/// answer, named so a test can assert them without an unnamed literal.
///
/// A selection tier scores its picks by order alone: the first pick scores
/// `1.0`, and the n-th pick scores `1 / n`. `SelectionMatch.score` documents
/// the rule; these constants are its first three values. Each score is
/// derived from a named rank, so no unnamed number stands in a division.
enum OrderScores {
    /// The 1-based rank of the second pick, the divisor of its score.
    private static let secondRank = 2.0

    /// The 1-based rank of the third pick, the divisor of its score.
    private static let thirdRank = 3.0

    /// The score of the first pick.
    static let firstPick = 1.0

    /// The score of the second pick.
    static let secondPick = 1.0 / secondRank

    /// The score of the third pick.
    static let thirdPick = 1.0 / thirdRank
}
