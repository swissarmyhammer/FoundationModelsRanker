import FoundationModels
import FoundationModelsExtras
import os

/// One generation call that a ``StubLanguageModel`` answered.
///
/// A test compares the calls with `==`, so the type holds only the two facts
/// that a pooled-session test asserts: what the transcript asked, and if the
/// call asked for guided output.
struct StubGenerationCall: Sendable, Equatable {
    /// The text of each prompt entry of the transcript of the call, in order.
    /// A session that continues an old transcript shows its old prompts here.
    let prompts: [String]

    /// `true` when the call carried a generation schema. A session that asks
    /// for a `Generable` type through its native guided generation sends the
    /// schema. A session that asks for plain text and decodes it after the
    /// call sends none.
    let isGuided: Bool
}

/// The script that each copy of one ``StubLanguageModel`` plays, and the log
/// of the calls that it answered.
///
/// A class, because the identity of the script is the cache key of the
/// executor. Each stored property is `Sendable`, so the compiler checks the
/// `Sendable` conformance.
final class StubLanguageModelScript: Sendable {
    /// The text that the model gives for each generation call.
    let answer: String

    /// The calls that the model answered, in order, under one lock.
    private let recordedCalls = OSAllocatedUnfairLock<[StubGenerationCall]>(initialState: [])

    /// Makes a script.
    ///
    /// - Parameter answer: The text that the model gives for each generation
    ///   call.
    init(answer: String) {
        self.answer = answer
    }

    /// The calls that the model answered, in order.
    var calls: [StubGenerationCall] { recordedCalls.withLock { $0 } }

    /// Adds `call` to the log.
    ///
    /// - Parameter call: The call that the model answered.
    fileprivate func record(_ call: StubGenerationCall) {
        recordedCalls.withLock { $0.append(call) }
    }
}

/// A FoundationModels `LanguageModel` that loads nothing and plays a
/// ``StubLanguageModelScript``.
///
/// Each generation call writes one ``StubGenerationCall`` to the log of the
/// script, and then answers with the answer of the script. The model needs
/// no GPU and no download, so a unit test can put it in a `ModelPool` behind
/// a ``StubModelLoader``.
struct StubLanguageModel: LanguageModel {
    /// The executor that plays the script.
    typealias Executor = StubLanguageModelExecutor

    /// The script that the model plays.
    let script: StubLanguageModelScript

    /// Guided generation, so a session can ask for a `Generable` type.
    var capabilities: LanguageModelCapabilities {
        LanguageModelCapabilities([.guidedGeneration])
    }

    /// The cache key of the executor: the identity of the script.
    var executorConfiguration: StubLanguageModelExecutor.Configuration {
        StubLanguageModelExecutor.Configuration(script: ObjectIdentifier(script))
    }
}

/// The executor of ``StubLanguageModel``.
struct StubLanguageModelExecutor: LanguageModelExecutor {
    /// The cache key that the SDK makes and reuses the executor by.
    struct Configuration: Sendable, Hashable {
        /// The identity of the script that the model plays.
        let script: ObjectIdentifier
    }

    /// The model that this executor runs for.
    typealias Model = StubLanguageModel

    /// The token count of the one emitted fragment. The stub meters nothing.
    private static let emittedTokenCount = 1

    /// Makes an executor. The configuration holds nothing that the executor
    /// reads: the script arrives with the model on each call.
    ///
    /// - Parameter configuration: The cache key.
    /// - Throws: Never. `throws` comes from the `LanguageModelExecutor`
    ///   requirement.
    init(configuration: Configuration) throws {}

    /// Writes the call to the log of the script, and emits the answer of the
    /// script.
    ///
    /// - Parameters:
    ///   - request: The generation request with the full transcript.
    ///   - model: The model with the script.
    ///   - channel: The channel that the answer goes into.
    func respond(
        to request: LanguageModelExecutorGenerationRequest,
        model: StubLanguageModel,
        streamingInto channel: LanguageModelExecutorGenerationChannel
    ) async throws {
        let script = model.script
        script.record(StubGenerationCall(prompts: Self.promptTexts(in: request.transcript), isGuided: request.schema != nil))
        await channel.send(.response(action: .appendText(script.answer, tokenCount: Self.emittedTokenCount)))
    }

    /// The text of each prompt of `transcript`, in order.
    ///
    /// - Parameter transcript: The transcript of a generation call.
    /// - Returns: The text of each prompt entry.
    private static func promptTexts(in transcript: Transcript) -> [String] {
        transcript.compactMap { entry in
            guard case .prompt(let prompt) = entry else { return nil }
            return prompt.segments.compactMap { segment in
                guard case .text(let text) = segment else { return nil }
                return text.content
            }.joined()
        }
    }
}

/// A `PooledModelLoader` that gives one fixed container for each key, and
/// loads nothing.
///
/// A unit test makes a `ModelPool(loader:)` with this loader, so a
/// `PooledModel` or a `PooledEmbedder` of that pool gets a stub model in
/// place of an MLX model.
struct StubModelLoader: PooledModelLoader {
    /// The container that each load gives.
    let container: any Sendable

    /// Gives ``container``.
    ///
    /// - Parameter key: The model and its role. The stub gives the same
    ///   container for each key.
    /// - Returns: ``container``.
    func load(_ key: ModelPoolKey) async throws -> any Sendable {
        container
    }

    /// Does nothing: the stub container holds no memory to free.
    ///
    /// - Parameter container: The container that ``load(_:)`` gave.
    func evict(_ container: any Sendable) async {}
}
