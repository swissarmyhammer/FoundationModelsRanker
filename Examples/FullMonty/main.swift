import FullMontyCore

/// # The `Searcher` facade's living proof (plan.md §3a).
///
/// Two paths. The example examines them in this order:
///
/// - `--no-model`: the degraded, GPU-free, CI-safe path — keyword-only
///   (BM25 + trigram) retrieval, no selection model, with the
///   `.embeddingUnavailable` diagnostic printed for every query.
/// - Neither: the default, out-of-the-box path — keyword-only retrieval
///   signals, but real agent selection on the on-device system model
///   (`Searcher.defaultSessionFactory`).
///
/// The actual search logic lives in `FullMontyCore` so `ExamplesSmokeTests`
/// can invoke its GPU-free paths directly; this file is just the runnable
/// entry point. Run with `swift run FullMonty` or `swift run FullMonty
/// --no-model`.

if CommandLine.arguments.contains("--no-model") {
    print("--no-model set -- printing keyword-only retrieval results (GPU-free, CI-safe).\n")
    let results = try await runNoModelDemo(onDiagnostic: printDiagnostic)
    printResults(results)
} else {
    print(
        """
        Running the default path: keyword-only retrieval, real agent selection on the on-device system model.
        Pass --no-model for the GPU-free keyword-only path.

        """
    )
    let results = try await runDefaultDemo(onDiagnostic: printDiagnostic)
    printResults(results)
}
