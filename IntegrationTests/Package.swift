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
// This package depends on the root package by path, and on
// FoundationModelsExtras. A test here loads `mlx-community/Qwen3-4B-4bit`
// through the `PooledModel` of Extras, and a target can use a product only of
// a package that its own manifest names. The Extras URL and branch are the
// same as in the root manifest, so SwiftPM resolves one Extras checkout for
// both packages. Keep the two declarations in step.

/// The root package, library product, and library target name.
///
/// Repeated identifiers are extracted to named constants so the manifest has
/// a single source of truth, the same pattern the root manifest follows.
let rootPackageName = "FoundationModelsRanker"

/// The package and the core library product of FoundationModelsExtras. The
/// root manifest holds the same name in its own `extrasName` constant.
let extrasName = "FoundationModelsExtras"

/// The root package's example-logic library product.
///
/// `FullMonty`'s entry logic lives in this product, and one test here drives
/// its default path, the path that needs the on-device system model. The root
/// manifest holds the same name in its own `exampleCoreName` constant.
let exampleCoreProductName = "FullMontyCore"

/// The SwiftPM manifest for FoundationModelsRanker's real-model tests.
///
/// The one test target holds the tests that drive a live model: the
/// `SystemLanguageModel`, so a run needs a Mac with Apple Intelligence turned
/// on, and `mlx-community/Qwen3-4B-4bit` through MLX, so the first run
/// downloads its weights into the Hugging Face cache. Selection is
/// structural: this target exists only in this package, so a root
/// `swift test` cannot see it.
let package = Package(
    name: "IntegrationTests",
    // Commit to macOS 27 / FoundationModels v2, the same floor as the root
    // package.
    platforms: [
        .macOS("27.0")
    ],
    dependencies: [
        .package(path: ".."),
        .package(url: "git@github.com:swissarmyhammer/\(extrasName).git", branch: "main"),
    ],
    targets: [
        .testTarget(
            name: "\(rootPackageName)IntegrationTests",
            dependencies: [
                .product(name: rootPackageName, package: rootPackageName),
                .product(name: exampleCoreProductName, package: rootPackageName),
                // `PooledModel`: the URI-id catalog suite loads Qwen3-4B.
                .product(name: extrasName, package: extrasName),
            ],
            path: "Tests/\(rootPackageName)IntegrationTests"
        )
    ]
)
