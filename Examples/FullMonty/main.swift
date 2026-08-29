import FullMontyCore

/// # The `Searcher` facade's living proof (plan.md §3a).
///
/// Three paths. The example examines them in this order:
///
/// - `--no-model`: the degraded, GPU-free, CI-safe path — keyword-only
///   (BM25 + trigram) retrieval, no selection model, with the
///   `.embeddingUnavailable` diagnostic printed for every query.
/// - `--embedder`: the same GPU-free retrieval with the cosine signal
///   switched on, from `DemoEmbedder` — a hashed bag of character trigrams
///   that needs no model, no GPU, and no network. No selection model, and
///   no `.embeddingUnavailable` diagnostic.
/// - Neither: the default, out-of-the-box path — keyword-only retrieval
///   signals, but real agent selection on the on-device system model
///   (`Searcher.defaultSessionFactory`).
///
/// The actual search logic lives in `FullMontyCore` so `ExamplesSmokeTests`
/// can invoke its GPU-free paths directly; this file is just the runnable
/// entry point. Run with `swift run FullMonty`, `swift run FullMonty
/// --no-model`, or `swift run FullMonty --embedder`.

if CommandLine.arguments.contains("--no-model") {
    print("--no-model set -- printing keyword-only retrieval results (GPU-free, CI-safe).\n")
    let results = try await runNoModelDemo(onDiagnostic: printDiagnostic)
    printResults(results)
} else if CommandLine.arguments.contains("--embedder") {
    print("--embedder set -- printing retrieval results with the cosine signal (GPU-free, CI-safe).\n")
    let results = try await runEmbedderDemo(onDiagnostic: printDiagnostic)
    printResults(results)
} else {
    print(
        """
        Running the default path: keyword-only retrieval, real agent selection on the on-device system model.
        Pass --no-model for the GPU-free keyword-only path.
        Pass --embedder for the GPU-free path that adds the cosine signal.

        """
    )
    let results = try await runDefaultDemo(onDiagnostic: printDiagnostic)
    printResults(results)
}
