---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m19cc6rq9ed9y3e8mgjpacst
  text: |-
    Research done.

    - Blocker `^ba0c6fv` is complete and committed as `d4ef034`. `IntegrationTests/Package.swift` exists and declares the test target `FoundationModelsRankerIntegrationTests`, which depends on the root package by path.
    - The shared workflow `/Users/wballard/github/swissarmyhammer/workflows/.github/workflows/swift-ci.yaml` declares the input `integration-package-path` (a string, default `""`). Its own description says the UNIT job also builds the nested package on every run, and the integration job runs `swift test --package-path` on it. The integration job's `if` condition includes `inputs.integration-package-path != ''`, so this input alone starts that job.
    - The comment style comes from the sibling `FoundationModelsMultitool/.github/workflows/ci.yml`, which writes: "The real-model suite is a nested package. This input makes the unit job build it on every run and makes the integration job run it." The other sibling `FoundationModelsCodeContext/.github/workflows/ci.yml` passes the same input with no comment.
    - No test in this repository pins the workflow file, so no test needs a change.
  timestamp: 2026-08-30T13:05:09.911211+00:00
- actor: claude-code
  id: 01m19ce59pqc5tv689ksttsbqh
  text: |-
    ### implement — changed
    - evidence: 1 file — `.github/workflows/ci.yml`. Added:

    ```yaml
        with:
          # The real-model suite is a nested package. This input makes the unit
          # job build it on every run and makes the integration job run it.
          integration-package-path: IntegrationTests
    ```

      The comment is copied from the sibling `FoundationModelsMultitool/.github/workflows/ci.yml`.

    - verified locally:
      - The YAML parses. `python3 -c "import yaml,json; d=yaml.safe_load(open('.github/workflows/ci.yml')); print(json.dumps(d['jobs'], indent=2))"` prints `"with": {"integration-package-path": "IntegrationTests"}`.
      - The input name is real. `integration-package-path` is declared at line 128 of `/Users/wballard/github/swissarmyhammer/workflows/.github/workflows/swift-ci.yaml`, and the integration job's `if` condition includes `inputs.integration-package-path != ''`.
      - The path value is real. `IntegrationTests/Package.swift` exists.
      - `swift test` at the root: "Test run with 273 tests in 22 suites passed".
      - `swift build --package-path IntegrationTests --build-tests`: "Build complete!" This is the step the unit job now also runs.
      - `swift test --package-path IntegrationTests`: `✔ Test "A bare LanguageModelSession reaches guided generation" passed after 1.560 seconds.` / "Test run with 1 test in 1 suite passed". This is the command the integration job runs.

    - NOT verified, and why: the last three Acceptance Criteria and both Tests items need a real CI run, and a CI run needs a push. A push is the user's decision, so this step did not push and did not start a workflow. Those boxes stay unchecked. Only the first criterion is checked, because the diff and the YAML parse prove it without a run.

    - next: the user pushes, then a later step reads `gh run view <id> --json jobs`, confirms two jobs both `success`, and quotes the real-model test name and its pass count from the integration job log.
  timestamp: 2026-08-30T13:06:13.942537+00:00
depends_on:
- 01M19ACG799X8YF41B4BA0C6FV
position_column: doing
position_ordinal: '80'
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

- [x] `.github/workflows/ci.yml` passes `integration-package-path: IntegrationTests`.
- [ ] A CI run for the resulting commit shows BOTH jobs with conclusion `success`. Neither may be `skipped`.
- [ ] The integration job's log shows the real-model test actually executing, with a pass count above zero — a green job that ran no test does not satisfy this.
- [ ] The unit job still passes and its wall time stays in the same order as today's (about 30 seconds).

## Tests

- [ ] Verify against the real run, not by reading YAML: `gh run view <id> --json jobs` must report two jobs, both `success`, and the integration job's step log must show the real-model test name and a non-zero pass count. Quote both in the step record.
- [ ] Confirm the unit job still reports the full root suite count.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. Here the "test" is the CI run itself: push, then read the run. #coverage-gap