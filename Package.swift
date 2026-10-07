// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

/// The package, library product, and library target name.
///
/// Repeated identifiers are named constants, so the manifest has a single
/// source of truth.
let packageName = "FoundationModelsRanker"

/// The package and the core library product of FoundationModelsExtras.
///
/// The package name and the product name are the same. The library target
/// and the test target both name the product, so the name is a constant.
let extrasName = "FoundationModelsExtras"

/// The SwiftPM manifest for FoundationModelsRanker.
///
/// The manifest declares one external package dependency: the core
/// `FoundationModelsExtras` product. Each embedder of the library is an
/// `any PooledEmbedding` of that product, so a caller gives a
/// `PooledEmbedder`, or any other `PooledEmbedding`, directly. Extras
/// compiles MLX, and the checkout uses SSH, so a build needs read access to
/// the swissarmyhammer repositories.
///
/// The package holds a single library target and a Swift Testing unit test
/// target. The runnable example is in the nested `Examples` package, and
/// this manifest does not name it.
let package = Package(
    name: packageName,
    // Commit to macOS 27, the floor for FoundationModels v2. Both consumer
    // repos use the same floor.
    platforms: [
        .macOS("27.0")
    ],
    products: [
        .library(
            name: packageName,
            targets: [packageName]
        ),
    ],
    dependencies: [
        .package(url: "git@github.com:swissarmyhammer/\(extrasName).git", branch: "main")
    ],
    targets: [
        .target(
            name: packageName,
            dependencies: [
                .product(name: extrasName, package: extrasName)
            ],
            path: "Sources/\(packageName)"
        ),
        .testTarget(
            name: "\(packageName)Tests",
            dependencies: [
                .target(name: packageName),
                // The embedder doubles conform to `PooledEmbedding`, and some
                // tests make a `ModelPool` with a stub loader, so the tests
                // name the Extras types directly.
                .product(name: extrasName, package: extrasName),
            ],
            path: "Tests/\(packageName)Tests"
        ),
    ]
)
