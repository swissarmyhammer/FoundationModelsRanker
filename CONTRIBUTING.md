# Contributing

## Run the example

`swift run FullMonty` has three paths:

- With no argument, it runs the agent selection tier on the on-device system
  model. It needs a Mac with Apple Intelligence turned on.
- `swift run FullMonty --no-model` prints keyword-only retrieval results.
- `swift run FullMonty --embedder` adds the cosine signal from a
  demonstration embedder.

The last two paths need no model, no GPU, and no network. See
[`Examples/FullMonty`](Examples/FullMonty).

## Run the tests

A package boundary separates the two test suites:

- `swift test` runs the unit suite. Every test in it drives a double, so it
  needs no model, no GPU, and no network.
- `swift test --package-path IntegrationTests` runs the real-model suite in
  the nested [`IntegrationTests`](IntegrationTests) package. Those tests drive
  a real `SystemLanguageModel`, so run them on a Mac with Apple Intelligence
  turned on.

The package structure selects the suite, and no environment variable changes
it. The root `Package.swift` declares one test target, the unit suite, so a
root `swift test` cannot reach a model. The real-model target exists only in
the nested package.
