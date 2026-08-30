// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// The real-model test target lives in this nested package, and the root
// package declares no integration target. The package boundary is what
// separates the hermetic tests from the real-model tests:
//
// - `swift test` at the repository root runs ONLY the hermetic tests, by
//   construction -- no `--skip`, no name regex, and no environment variable.
// - `swift test --package-path IntegrationTests` runs the real-model tests.
//   Use `--filter` inside this package to run one test.
//
// The root package declares no external dependency, so there is no pin here
// to keep in step with the root manifest. This package depends on the root
// package by path and on nothing else.

/// The root package, library product, and library target name.
///
/// Repeated identifiers are extracted to named constants so the manifest has
/// a single source of truth, the same pattern the root manifest follows.
let rootPackageName = "FoundationModelsRanker"

/// The SwiftPM manifest for FoundationModelsRanker's real-model tests.
///
/// The one test target holds the tests that drive a live
/// `SystemLanguageModel`, so a run needs a Mac with Apple Intelligence turned
/// on. Selection is structural: this target exists only in this package, so a
/// root `swift test` cannot see it.
let package = Package(
    name: "IntegrationTests",
    // Commit to macOS 27 / FoundationModels v2, the same floor as the root
    // package.
    platforms: [
        .macOS("27.0")
    ],
    dependencies: [
        .package(path: "..")
    ],
    targets: [
        .testTarget(
            name: "\(rootPackageName)IntegrationTests",
            dependencies: [
                .product(name: rootPackageName, package: rootPackageName)
            ],
            path: "Tests/\(rootPackageName)IntegrationTests"
        )
    ]
)
