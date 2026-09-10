import FoundationModelsRanker
import Testing

/// The nine functions of the consumer catalog that card `^zxm99zs` measured:
/// the files and shell tools of FoundationModelsMultitool.
///
/// The consumer renders each entry as its `tools.<path>` id above its full
/// description. This catalog keeps the ids and cuts each description to its
/// first sentence, which is the one line `LiveToolCatalog` renders.
private let functionCatalog = LiveToolCatalog([
    .init(id: "files.read", description: "reads a file's contents, windowed by line"),
    .init(id: "files.write", description: "writes content to a file atomically, replacing any existing file whole"),
    .init(id: "files.edit", description: "rewrites a file by a batch of find/replace pairs, committed in one atomic write"),
    .init(id: "files.patch", description: "applies a multi-file patch in one call"),
    .init(id: "files.glob", description: "finds the files whose relative path matches a glob pattern, newest first"),
    .init(id: "files.grep", description: "searches file contents for a regular expression, line by line"),
    .init(
        id: "shell.execute",
        description: "starts one shell command in the background and answers at once with its completion token"),
    .init(id: "shell.getLines", description: "reads the captured output of one shell run, by line number"),
    .init(
        id: "shell.grepHistory",
        description: "searches the captured output of this session's shell runs, line by line, with a regular expression"),
])

/// The ten queries the consumer's agent gave to its search tool on one
/// SWE-bench run, in the order it gave them (card `^zxm99zs`).
///
/// Each query names at least one candidate of `functionCatalog`, so each
/// query must come back with at least one id.
private let functionCatalogQueries: [String] = [
    "Search the astropy codebase for files, read code, and run tests",
    "list files and read file contents",
    "grep search for text pattern in files",
    "run a shell command or python script, execute code",
    "run pytest tests, execute",
    "write file, edit file, create file",
    "edit code, modify source file, patch",
    "apply changes to a file, save file contents",
    "file operations: create, write, append, delete, move",
    "create a new text file with given content on disk",
]

/// Drives `SelectionTier` over a catalog of functions against a live
/// `SystemLanguageModel`, so a run needs a Mac with Apple Intelligence
/// turned on.
///
/// `ZeroConfigSearcherRealModelTests` holds the demo queries over a catalog
/// of command-line tools. This suite holds the queries of a consumer whose
/// catalog is the functions a program calls, which is the catalog shape the
/// default preamble answered worst on a small model. Nothing selects between
/// the two suites at run time: this target lives only in the nested
/// `IntegrationTests` package, so `swift test` at the repository root cannot
/// see it, and `swift test --package-path IntegrationTests` runs it.
@Suite("A function catalog on the live system model")
struct FunctionCatalogRealModelTests {
    /// The default preamble must make the model answer every query of the
    /// function catalog from a session that has answered nothing yet.
    ///
    /// **Every query gets its own tier**, so every search runs on a cold
    /// session, the state a caller that asks one question starts in. Card
    /// `^zxm99zs` measured the preamble that shipped before this test on this
    /// catalog, three rounds each. On the system model, cold, "file
    /// operations: create, write, append, delete, move" answered 0 of 3 and
    /// the other nine queries 3 of 3. On `mlx-community/Qwen3-4B-4bit`, over
    /// the consumer's own catalog and grammar, all ten queries answered 0 of
    /// 3. The default that ships now says what the candidates are and what an
    /// answer is, and it tells the model to prefer the closest candidates
    /// over an empty answer. With it, both models answered 30 of 30.
    ///
    /// The test makes no claim about which id comes back. A live model can
    /// word a correct pick differently from one run to the next. It claims
    /// that some catalog id came back, and that the tier reported no
    /// diagnostic, because a bare `LanguageModelSession` carries no grammar
    /// and the only diagnostic the tier emits is `.unknownSelectedId`.
    ///
    /// - Parameter query: the consumer query this case asks, cold.
    @Test(
        "The default preamble answers every function-catalog query on a cold session",
        arguments: functionCatalogQueries
    )
    func theDefaultPreambleAnswersEveryFunctionCatalogQueryOnAColdSession(query: String) async throws {
        let tier = SelectionTier(
            catalog: functionCatalog,
            config: SelectionConfig(model: Searcher.defaultSessionFactory),
            onDiagnostic: { diagnostic in
                Issue.record("The selection tier reported \(diagnostic).")
            }
        )

        let matches = try await tier.search(intent: query, limit: functionCatalog.ids.count)

        #expect(!matches.isEmpty)
        #expect(matches.allSatisfy { functionCatalog.ids.contains($0.id) })
    }
}
