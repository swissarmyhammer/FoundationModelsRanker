---
assignees:
- claude-code
position_column: todo
position_ordinal: '80'
title: Guard the integration test package against any dependency except the root package
---
## What
The nested integration test package must not depend on Router, or on any other package except the root package. Today `IntegrationTests/Package.swift` declares only `.package(path: "..")`, and that is correct. But the test `TestPartitioningTests.theIntegrationPackageDependsOnTheRootPackageByPath` (`Tests/FoundationModelsRankerTests/TestPartitioningTests.swift:84`) only checks that `.package(path: "..")` is present. If a person adds a second `.package(` call, for example a Router URL, no test fails.

The root manifest already has this guard: `PackageTests.theManifestDeclaresNoPackageDependency` (`Tests/FoundationModelsRankerTests/PackageTests.swift:18`). This task adds the same guard to the nested manifest.

Files:
- `Tests/FoundationModelsRankerTests/TestPartitioningTests.swift`: add the new tests to the section "The package boundary that selects each suite".
- `IntegrationTests/Package.swift`: change only the header comment (lines 15-17), if necessary, so that it names the new test as the guard.

Approach:
- Read `integrationTestsManifestURL` (from `Support/RepositoryRoot.swift`).
- Count the `.package(` occurrences. The count must be exactly 1, and that occurrence must be `.package(path: "..")`.
- Do a case-insensitive check that the text "router" does not occur in the root manifest or in the nested manifest.

## Acceptance Criteria
- [ ] A test fails if `IntegrationTests/Package.swift` has a `.package(` call other than `.package(path: "..")`.
- [ ] A test fails if the root `Package.swift` or `IntegrationTests/Package.swift` contains the text "router" (any case).
- [ ] No change to the targets or dependencies of either manifest.
- [ ] `swift test` at the repository root passes.

## Tests
- [ ] Add `theIntegrationPackageDeclaresOnlyTheRootPackageDependency` to `Tests/FoundationModelsRankerTests/TestPartitioningTests.swift`. It counts `.package(` occurrences (== 1) and requires `.package(path: "..")`.
- [ ] Add `noManifestNamesRouter` to the same file. It reads `manifestURL` and `integrationTestsManifestURL`.
- [ ] Before you write each test, add a temporary `.package(url: "https://example.invalid/FoundationModelsRouter.git", branch: "main")` line to a scratch copy of the manifest text in the test input. Make sure that each assertion fails for that input. Then make the assertions pass on the real files.
- [ ] Run `swift test --filter TestPartitioningTests`. Expected result: all tests pass.
- [ ] Run `swift test`. Expected result: the full hermetic suite passes.

## Workflow
- Use `/tdd`. Write the failing tests first, then make them pass.