import Foundation

// MARK: - The checked-in files that tests read
//
// Two suites read a file that lives at the repository root, and not in a
// bundle: `PackageTests` reads `Package.swift`, and `ReadmeExampleTests`
// reads both `Package.swift` and `README.md`. The walk to the root, and the
// path of each file, live here one time.

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
