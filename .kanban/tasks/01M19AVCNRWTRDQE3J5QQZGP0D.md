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
- actor: claude-code
  id: 01m19jyzne7fchqwgqs0wwwgj5
  text: |-
    ### CI evidence — the run-level criteria are now met

    Pushed `35447e4..fd1e024`. CI run **33318330212** for `fd1e024`:

    ```
    RUN: completed success
    completed  success   ci / Build & test
    completed  success   ci / Integration (opt-in, real dependencies)
    ```

    Neither job skipped. Compare the two runs before this change, `33310680821` and `32997172742`, where the integration job was `skipped` — as it had been on every run this repository ever had.

    Unit job log:
    ```
    ✔ Test run with 279 tests in 22 suites passed after 0.174 seconds.
    ```

    Integration job log — the real-model tests genuinely executed on the CI Mac mini, with a non-zero pass count:
    ```
    ✔ Test "A bare LanguageModelSession reaches guided generation" passed after 3.877 seconds.
    ✔ Test "A LanguageModelSession held as any AgentSession answers with plain text" passed after 4.639 seconds.
    ✔ Test "Searcher(items) with no session argument answers every demo query on a cold session" with 4 test cases passed after 5.104 seconds.
    ✔ Test "runDefaultDemo answers every demo query on the on-device system model" passed after 6.827 seconds.
    ✔ Test run with 4 tests in 4 suites passed after 6.828 seconds.
    ```

    That satisfies every acceptance criterion, including the two that could only be checked by a real run: both jobs green with neither skipped, and the integration job showing the real-model test names with a pass count above zero. The unit job's wall time also stayed in the same order as before.

    Apple Intelligence works on the CI runner. That was the open question when the card was written, and the answer is yes.
  timestamp: 2026-08-30T15:00:16.686426+00:00
- actor: claude-code
  id: 01m19k5fkab0rw79sz5d9wttn7
  text: |-
    ### review — clean

    - evidence: `review sha a2a9718~1..a2a9718` gave 0 findings (attempted 1, failed 0, skipped 0). The change adds 4 lines to `.github/workflows/ci.yml`.

    I checked the CI proof again by myself. I did not use the earlier comment as proof.

    **Run 33318330212**

    - Status `completed`, result `success`.
    - Job `ci / Build & test`: `success`.
    - Job `ci / Integration (opt-in, real dependencies)`: `success`. This job is not `skipped`.
    - Head commit `fd1e024`. The command `git merge-base --is-ancestor a2a9718 fd1e024` gives code 0. So the run contains commit `a2a9718`. The file `.github/workflows/ci.yml` at `fd1e024` holds the same `with:` block that `a2a9718` added.

    **The unit job**

    ```
    swift build --package-path 'IntegrationTests' --build-tests
    Build complete! (5.12 sec)
    ✔ Test run with 279 tests in 22 suites passed after 0.174 seconds.
    ```

    The job time is 22 seconds (14:58:41 to 14:59:03). This time is near the time before the change.

    **The integration job**

    ```
    ##[group]swift test --package-path IntegrationTests
    ✔ Test "A bare LanguageModelSession reaches guided generation" passed after 3.877 seconds.
    ✔ Test "A LanguageModelSession held as any AgentSession answers with plain text" passed after 4.639 seconds.
    ✔ Test "Searcher(items) with no session argument answers every demo query on a cold session" with 4 test cases passed after 5.104 seconds.
    ✔ Test "runDefaultDemo answers every demo query on the on-device system model" passed after 6.827 seconds.
    ✔ Test run with 4 tests in 4 suites passed after 6.828 seconds.
    ```

    Four tests passed. The count is more than zero. Each test took 3.8 to 6.8 seconds. These times match calls to the real model on the device.

    **The guard**

    - The text `::error::swift test ... matched no test case: this run measured nothing` is in the log one time only, at line 199. That line is part of the script text that GitHub prints before the step starts. The line has the ANSI prefix that GitHub puts on printed script text.
    - No true `::error::` note and no true `::warning::` note is in the log of the two jobs.
    - The guard reads the file that holds the output of `swift test`. The text `No matching test cases were run` is not in that output.
    - So the guard did not fire. The guard was active and the step ran it. The "green but measured nothing" fault is not present.

    **The two runs before the change**

    - Run 33310680821, commit `35447e4`: the integration job is `skipped`. `35447e4` comes before `a2a9718`. Its `ci.yml` has no `with:` block.
    - Run 32997172742, commit `222e74a`: the integration job is `skipped`. `222e74a` does not contain `a2a9718`. Its `ci.yml` has no `with:` block.
    - So the input `integration-package-path` is the cause of the new behavior. No other change caused it.

    - next: I did not change the boxes in the description. The skill says the person who owns the card marks them. All four acceptance criteria and both test items now have proof in this comment.
  timestamp: 2026-08-30T15:03:49.610468+00:00
depends_on:
- 01M19ACG799X8YF41B4BA0C6FV
position_column: done
position_ordinal: a680
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