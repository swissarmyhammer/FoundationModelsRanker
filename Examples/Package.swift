// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// The runnable example of FoundationModelsRanker.
//
// This is a separate package, and the root manifest does not name it. The
// example depends on the library and on FoundationModelsExtras only. It
// embeds with a `PooledEmbedder` and selects with a `PooledModel` of
// FoundationModelsExtras. Each one loads an MLX model from the Hugging Face
// hub through `ModelPool.shared`.
//
//     swift run --package-path Examples FullMonty
//     swift run --package-path Examples FullMonty --no-model

/// The root package, library product, and library target name.
let rankerPackage = "FoundationModelsRanker"

/// The package and the core library product of FoundationModelsExtras.
let extrasPackage = "FoundationModelsExtras"

/// The name of the example executable. Its target is in `<name>/`.
let exampleName = "FullMonty"

let package = Package(
    name: "Examples",
    // The same floor as the root package.
    platforms: [
        .macOS("27.0")
    ],
    dependencies: [
        .package(path: ".."),
        // The model pool (`ModelPool`, `PooledEmbedder`, `PooledModel`). The
        // same URL and branch as in the root manifest, so the two resolve as
        // one package.
        .package(url: "git@github.com:swissarmyhammer/\(extrasPackage).git", branch: "main"),
    ],
    targets: [
        .executableTarget(
            name: exampleName,
            dependencies: [
                .product(name: rankerPackage, package: rankerPackage),
                .product(name: extrasPackage, package: extrasPackage),
            ],
            path: exampleName
        )
    ]
)
