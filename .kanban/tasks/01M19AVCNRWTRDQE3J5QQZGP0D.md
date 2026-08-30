---
assignees:
- claude-code
depends_on:
- 01M19ACG799X8YF41B4BA0C6FV
position_column: todo
position_ordinal: '8580'
title: Run both the unit and the integration job in CI
---
## What

`.github/workflows/ci.yml` calls the shared org workflow with no inputs:

```yaml
jobs:
  ci:
    uses: swissarmyhammer/workflows/.github/workflows/swift-ci.yaml@main
```

The shared workflow's integration job runs only when one of `integration-gate-env`, `integration-filter`, `integration-skip` or `integration-package-path` is non-empty. We pass none, so that job has been `skipped` on every run this repository has ever had — verified on run `33310680821` and on the pre-change baseline `32997172742`. Our real-model test has never run in CI.

The runner is a self-hosted Mac mini that can run Apple Intelligence, so there is no reason for the integration job to sit idle.

After task `^ba0c6fv` creates the nested package, add the input the siblings use:

```yaml
jobs:
  ci:
    uses: swissarmyhammer/workflows/.github/workflows/swift-ci.yaml@main
    with:
      integration-package-path: IntegrationTests
```

That is the exact form `FoundationModelsACP`, `FoundationModelsACPClient`, `FoundationModelsCodeContext`, `FoundationModelsMultitool` and `FoundationModelsRouter` already pass. Per the shared workflow's own description, that input makes the UNIT job build the nested package on every run and makes the INTEGRATION job run it — so both jobs do real work.

Do NOT use `integration-gate-env`. Two sibling workflows document it as a legacy input, and it additionally requires `integration-xctest-glob`, whose documented limitation is that exactly one `.xctest` bundle runs because the glob is read with `head -n 1`.

Add a comment above the input saying what it does and why the nested package exists, in the style the siblings use.

## Acceptance Criteria

- [ ] `.github/workflows/ci.yml` passes `integration-package-path: IntegrationTests`.
- [ ] A CI run for the resulting commit shows BOTH jobs with conclusion `success`. Neither may be `skipped`.
- [ ] The integration job's log shows the real-model test actually executing, with a pass count above zero — a green job that ran no test does not satisfy this.
- [ ] The unit job still passes and its wall time stays in the same order as today's (about 30 seconds).

## Tests

- [ ] Verify against the real run, not by reading YAML: `gh run view <id> --json jobs` must report two jobs, both `success`, and the integration job's step log must show the real-model test name and a non-zero pass count. Quote both in the step record.
- [ ] Confirm the unit job still reports the full root suite count.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. Here the "test" is the CI run itself: push, then read the run. #coverage-gap