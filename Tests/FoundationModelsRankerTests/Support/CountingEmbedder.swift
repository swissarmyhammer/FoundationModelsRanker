import Foundation
import FoundationModelsRanker
import os

/// The error `CountingEmbedder` throws for each call at or after its
/// `failingFromCall` number.
///
/// The caller under test swallows this error -- `RetrievalEngine
/// .cosineScores(forQuery:)` embeds the query with `try?` -- so a test asserts
/// on the degradation, not on the error value. The type therefore carries no
/// payload, and it is `Equatable` for a test that does compare it.
struct CountingEmbedderFailure: Error, Equatable {}

/// A `TextEmbedding` test double that counts how many times `embed(_:)` is
/// called, wrapping `FakeEmbedder` for deterministic vectors underneath, and
/// that can fail from a given call number onward.
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
final class CountingEmbedder: TextEmbedding, Sendable {
    let dimension: Int

    private let fake: FakeEmbedder
    private let callCountBox = OSAllocatedUnfairLock<Int>(initialState: 0)

    /// The 1-indexed call number from which `embed(_:)` throws, or `nil` when
    /// this embedder always succeeds.
    private let failingFromCall: Int?

    /// Creates a counting embedder that deterministically hashes text into
    /// vectors of `dimension` length, exactly like `FakeEmbedder`.
    ///
    /// - Parameters:
    ///   - dimension: the length of every vector this embedder produces.
    ///   - failingFromCall: the 1-indexed call number from which `embed(_:)`
    ///     throws `CountingEmbedderFailure` in place of vectors. Each earlier
    ///     call embeds normally. Defaults to `nil`, which never fails.
    init(dimension: Int, failingFromCall: Int? = nil) {
        self.dimension = dimension
        self.failingFromCall = failingFromCall
        fake = FakeEmbedder(dimension: dimension)
    }

    /// The number of times `embed(_:)` has been called so far.
    var callCount: Int { callCountBox.withLock { $0 } }

    /// Increments the call count, then throws `CountingEmbedderFailure` when
    /// this call number is at or after `failingFromCall`, or returns
    /// embeddings from the wrapped embedder.
    func embed(_ texts: [String]) async throws -> [[Float]] {
        let callNumber = callCountBox.withLock { count in
            count += 1
            return count
        }
        if let failingFromCall, callNumber >= failingFromCall {
            throw CountingEmbedderFailure()
        }
        return try await fake.embed(texts)
    }
}
