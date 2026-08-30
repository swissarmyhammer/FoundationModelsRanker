import Foundation
import Testing

/// Holds the boundary between this package's unit suite and the real-model
/// suite in the nested `IntegrationTests` package.
///
/// `swift test` at the repository root runs the unit suite.
/// `swift test --package-path IntegrationTests` runs the real-model suite.
/// The selection is structural: the root manifest declares one test target
/// and no integration target, so a root run cannot reach a real model.
/// Nothing reads an environment variable to decide which tests run.
///
/// The tests below read the checked-in files, so the boundary cannot erode
/// without one of them failing.
@Suite("Test partitioning")
struct TestPartitioningTests {
    // MARK: - Fixtures

    /// The expression a Swift source reads an environment variable through.
    ///
    /// A test target has no honest reason to read one. An environment
    /// variable selects no test here: the package boundary carries the whole
    /// split, and a variable that switched a suite on would put a real model
    /// back into a root `swift test`.
    private static let environmentRead = "ProcessInfo.processInfo.environment"

    /// The directories the scan reads, each holding one test target's
    /// sources.
    private static let scannedTestDirectories = ["Tests", "IntegrationTests"]

    /// This file's own name, which the scan passes over: the test spells
    /// `environmentRead` in order to search for it.
    private static let unscannedFileName = URL(filePath: #filePath).lastPathComponent

    /// Every checked-in Swift source of both test targets, in no particular
    /// order.
    ///
    /// Walks each directory rather than a fixed list, so a source added
    /// later is read without anyone remembering to list it. Hidden entries
    /// are passed over, which leaves out `.build` and `.swiftpm`.
    ///
    /// - Returns: the sources the scan covers.
    private static func scannedTestSources() -> [URL] {
        scannedTestDirectories.flatMap { directory -> [URL] in
            let enumerator = FileManager.default.enumerator(
                at: repositoryRootURL.appending(path: directory),
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            let entries = enumerator?.compactMap { $0 as? URL } ?? []
            return entries.filter { url in
                url.pathExtension == "swift" && url.lastPathComponent != unscannedFileName
            }
        }
    }

    // MARK: - Nothing selects a test at run time

    @Test("No test source reads the process environment")
    func noTestSourceReadsTheProcessEnvironment() throws {
        let sources = Self.scannedTestSources()
        try #require(!sources.isEmpty, "The scan read no source, so it proves nothing.")

        var reading: [String] = []
        for source in sources {
            let text = try String(contentsOf: source, encoding: .utf8)
            guard text.contains(Self.environmentRead) else { continue }
            reading.append(source.lastPathComponent)
        }

        #expect(reading == [])
    }

    // MARK: - The package boundary that selects each suite

    @Test("The root manifest declares exactly one test target, the unit suite")
    func theRootManifestDeclaresExactlyOneTestTarget() throws {
        let manifest = try String(contentsOf: manifestURL, encoding: .utf8)

        #expect(manifest.ranges(of: ".testTarget(").count == 1)
    }

    @Test("The integration package depends on the root package by path")
    func theIntegrationPackageDependsOnTheRootPackageByPath() throws {
        let manifest = try String(contentsOf: integrationTestsManifestURL, encoding: .utf8)

        #expect(manifest.contains(#".package(path: "..")"#))
    }
}
