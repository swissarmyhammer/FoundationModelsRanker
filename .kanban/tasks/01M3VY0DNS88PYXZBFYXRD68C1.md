---
assignees:
- claude-code
position_column: todo
position_ordinal: '80'
title: Measure the function-catalog suite on the system model with the exact-id preamble
---
## What
During ^knyvhkf, one full run of `swift test --package-path IntegrationTests` recorded 1 issue in `FunctionCatalogRealModelTests` ("A function catalog on the live system model"). The run output was cut, so the failing query and the issue are not known. The next run of that suite alone passed 10 of 10, and the next full run passed 6 of 6 suites.

The cause can be the new `SelectionConfig.selectionDefault` text, or the change to `LiveToolCatalog.summaryBlock(forID:)`, which now gives the description alone (the summary does not repeat the id). Card ^zxm99zs measured the earlier default at 30 of 30 on the on-device system model.

## Acceptance Criteria
- [ ] Run the ten function-catalog queries three rounds each on the system model, one cold session for each query, and record the count of answered queries and each issue on this card.
- [ ] If the count is less than 30 of 30, find the query and the cause, and correct the prompt text or the test catalog so that the suite passes each run.

## Tests
- [ ] `swift test --package-path IntegrationTests --filter FunctionCatalogRealModelTests` passes three runs in sequence. #selection