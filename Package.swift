// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

/// The package, library product, and library target name.
///
/// Repeated identifiers are extracted to named constants so the manifest has
/// a single source of truth, following the pattern established by the
/// sibling FoundationModelsMetadataRegistry package.
let packageName = "FoundationModelsRanker"

/// The example-logic target and its library product name.
///
/// `FullMonty`'s entry logic lives in this target, and two test targets drive
/// it: the root test target, which reaches it as a sibling target, and the
/// nested `IntegrationTests` package, which reaches it only through the
/// product of the same name. The two spellings must agree, so the name is a
/// constant, the same pattern `packageName` follows.
let exampleCoreName = "FullMontyCore"

/// The SwiftPM manifest for FoundationModelsRanker (plan.md §3).
///
/// The manifest declares no external package dependency. Every target builds
/// against the macOS SDK alone, so anyone can build and test this package
/// with no access to a private repository and no SSH key.
///
/// The package holds a single library target, a Swift Testing unit test
/// target, and the `Examples/FullMonty` / `Examples/FullMontyCore` targets
/// (plan.md §3a): the package's runnable living proof of the `Searcher`
/// facade — demo only, never a dependency of the library. `FullMonty`'s
/// entry logic lives in `FullMontyCore` (a plain library target, not the
/// executable itself) so the test target can `@testable import` and invoke
/// it directly as a plain library dependency, mirroring
/// FoundationModelsMetadataRegistry's `*Core` example targets.
let package = Package(
    name: packageName,
    // Commit to macOS 27 / FoundationModels v2, the floor both consumer
    // repos use (plan.md §3).
    platforms: [
        .macOS("27.0")
    ],
    products: [
        .library(
            name: packageName,
            targets: [packageName]
        ),
        // The example is a demo, never part of the library, and this product
        // does not make it one: no library target depends on it. The product
        // exists because a target in another package reaches this code no
        // other way, and the real-model half of the demo's default path is a
        // test in the nested `IntegrationTests` package.
        .library(
            name: exampleCoreName,
            targets: [exampleCoreName]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: packageName,
            dependencies: [],
            path: "Sources/\(packageName)"
        ),
        .testTarget(
            name: "\(packageName)Tests",
            dependencies: [
                .target(name: packageName),
                .target(name: exampleCoreName),
            ],
            path: "Tests/\(packageName)Tests"
        ),
        // `FullMonty`'s entry logic (plan.md §3a): a fixture catalog of ~50
        // developer-tool items, a handful of queries, printed matches with
        // per-signal scores and the model's final selection — the living
        // proof of the `Searcher` facade documented in `Searcher.swift`'s
        // header. A plain library (not the executable itself) so
        // `ExamplesSmokeTests` can invoke its GPU-free paths directly.
        .target(
            name: exampleCoreName,
            dependencies: [.target(name: packageName)],
            path: "Examples/\(exampleCoreName)"
        ),
        // A thin runnable entry point over `FullMontyCore`. `swift build`
        // compiles this GPU-free; `swift run FullMonty --no-model` and
        // `swift run FullMonty --embedder` both run GPU-free; the default
        // path uses the on-device system model and needs Apple Intelligence.
        .executableTarget(
            name: "FullMonty",
            dependencies: [.target(name: exampleCoreName)],
            path: "Examples/FullMonty"
        ),
    ]
)
