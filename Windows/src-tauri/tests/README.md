# Cargo integration tests

Integration tests for the Rust engine live here. Three suites are planned and
will land in their respective milestones:

1. `provider_contract_fixtures.rs` - replays each fixture in
   `../assets/contracts/Providers/<id>/<case>-response.json` through the spec
   engine and asserts the produced snapshot against
   `<case>-expected.json`. Step URLs / headers are checked against
   `<case>-requests.json`. Mirrors the ArkTS `Contract.test.ets` suite and the
   Kotlin `ProviderContractTest.kt` suite.

2. `aggregation_contract_fixtures.rs` - replays each fixture in
   `../assets/contracts/Aggregation/<case>-input.json` through
   `SnapshotAggregator` and asserts against `<case>-expected.json`.

3. `alerts_contract_fixtures.rs` - replays each fixture in
   `../assets/contracts/Alerts/<case>-input.json` through `AlertEvaluator`
   and asserts against `<case>-expected.json`.

Until these land the directory is empty; `cargo test` runs the lib-level
`quotaglance_tauri_lib::scaffold_tests` smoke test for the time being.
