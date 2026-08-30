import Foundation
import FoundationModelsRanker
import os

/// The error `CountingEmbedder` throws for each call inside its failure
/// window.
///
/// The caller under test swallows this error -- `RetrievalEngine
/// .cosineScores(forQuery:)` embeds the query with `try?` -- so a test asserts
/// on the degradation, not on the error value. The type therefore carries no
/// payload, and it is `Equatable` for a test that does compare it.
struct CountingEmbedderFailure: Error, Equatable {}

/// A `TextEmbedding` test double that counts how many times `embed(_:)` is
/// called, wrapping `FakeEmbedder` for deterministic vectors underneath, and
/// that can fail for a window of call numbers.
///
/// Exists for `StreamingSearchCorpus`'s incremental-embed economy (^rayd7bq):
/// "each added item is embedded exactly once, at add time" and "only the
/// query string is embedded per search" are both claims about *how many
/// times* `embed(_:)` runs, not just what it returns -- `FakeEmbedder` alone
/// has no way to assert that. A test drives calls in a known order (adds,
/// then searches) and reads `callCount` before/after each phase to assert the
/// expected delta.
///
/// The same count also selects which calls fail, which is what
/// `FakeEmbedder(dimension:failure:)` cannot do: its `failure` throws on
/// *every* call, so a caller that embeds at `init` never gets built. A caller
/// that embeds more than once needs the later call to fail alone. `Searcher`
/// is that caller: it embeds every item in call 1 at `init`, then embeds the
/// query in call 2 at each search, so `failingFromCall: 2` fails the query
/// embed by itself and leaves the item embeddings whole.
///
/// `recoveringAtCall` ends the failure again, so one embedder can fail a call
/// and let a later call through. A caller that decides for each operation --
/// `StreamingSearchCorpus` decides again at each search whether cosine can
/// contribute -- needs that window: it is the only way a test can hold the
/// caller constant and change nothing but the health of the embedder, and
/// thus show that the caller keeps no memory of the failure.
final class CountingEmbedder: TextEmbedding, Sendable {
    let dimension: Int

    private let fake: FakeEmbedder
    private let callCountBox = OSAllocatedUnfairLock<Int>(initialState: 0)

    /// The 1-indexed call number from which `embed(_:)` throws, or `nil` when
    /// this embedder always succeeds.
    private let failingFromCall: Int?

    /// The 1-indexed call number at which `embed(_:)` embeds normally again,
    /// or `nil` when the failure has no end.
    private let recoveringAtCall: Int?

    /// Creates a counting embedder that deterministically hashes text into
    /// vectors of `dimension` length, exactly like `FakeEmbedder`.
    ///
    /// The two call numbers make a half-open window of the calls that fail:
    /// `failingFromCall` is the first failure, and `recoveringAtCall` is the
    /// first success after it. Leave `recoveringAtCall` at `nil` for a window
    /// with no end.
    ///
    /// - Parameters:
    ///   - dimension: the length of every vector this embedder produces.
    ///   - failingFromCall: the 1-indexed call number from which `embed(_:)`
    ///     throws `CountingEmbedderFailure` in place of vectors. Each earlier
    ///     call embeds normally. Defaults to `nil`, which never fails.
    ///   - recoveringAtCall: the 1-indexed call number from which `embed(_:)`
    ///     embeds normally again. Each call at or after this number succeeds.
    ///     Defaults to `nil`, which never recovers. Has no effect when
    ///     `failingFromCall` is `nil`, and no effect on a call before
    ///     `failingFromCall`, which succeeds anyway.
    init(dimension: Int, failingFromCall: Int? = nil, recoveringAtCall: Int? = nil) {
        self.dimension = dimension
        self.failingFromCall = failingFromCall
        self.recoveringAtCall = recoveringAtCall
        fake = FakeEmbedder(dimension: dimension)
    }

    /// The number of times `embed(_:)` has been called so far.
    var callCount: Int { callCountBox.withLock { $0 } }

    /// Increments the call count, then throws `CountingEmbedderFailure` when
    /// this call number falls inside the failure window, or returns
    /// embeddings from the wrapped embedder.
    func embed(_ texts: [String]) async throws -> [[Float]] {
        let callNumber = callCountBox.withLock { count in
            count += 1
            return count
        }
        if fails(callNumber: callNumber) {
            throw CountingEmbedderFailure()
        }
        return try await fake.embed(texts)
    }

    /// Answers whether the call with this 1-indexed number falls inside the
    /// half-open failure window `failingFromCall ..< recoveringAtCall`.
    ///
    /// - Parameter callNumber: the 1-indexed number of the call to test.
    /// - Returns: `true` when the call throws, `false` when it embeds.
    private func fails(callNumber: Int) -> Bool {
        guard let failingFromCall, callNumber >= failingFromCall else {
            return false
        }
        guard let recoveringAtCall else {
            return true
        }
        return callNumber < recoveringAtCall
    }
}
