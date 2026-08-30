import Foundation

// MARK: - The checked-in files that tests read
//
// Three suites read a file that lives at the repository root, and not in a
// bundle: `PackageTests` reads `Package.swift`, `ReadmeExampleTests` reads
// both `Package.swift` and `README.md`, and `TestPartitioningTests` reads
// `Package.swift`, the nested integration package's own manifest, and both
// test source trees. The walk to the root, and the path of each file, live
// here one time.

/// The repository root, found from this file's own source path.
///
/// This file is
/// `Tests/FoundationModelsRankerTests/Support/RepositoryRoot.swift`, so the
/// root is the fourth directory above it. The path of the source file, and
/// not the working directory, gives the root, so the test run can start
/// anywhere.
let repositoryRootURL = URL(filePath: #filePath)
    .deletingLastPathComponent()  // Tests/FoundationModelsRankerTests/Support
    .deletingLastPathComponent()  // Tests/FoundationModelsRankerTests
    .deletingLastPathComponent()  // Tests
    .deletingLastPathComponent()  // the repository root

/// The `Package.swift` manifest at the repository root.
let manifestURL = repositoryRootURL.appending(path: "Package.swift")

/// The `README.md` document at the repository root.
let readmeURL = repositoryRootURL.appending(path: "README.md")

/// The `Package.swift` manifest of the nested integration test package.
///
/// The real-model tests live in that package, and `swift test
/// --package-path IntegrationTests` runs them.
let integrationTestsManifestURL = repositoryRootURL
    .appending(path: "IntegrationTests")
    .appending(path: "Package.swift")
