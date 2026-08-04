# Assets (sync targets)

Two subdirectories here are produced by sync scripts. They are intentionally
not committed (see `Windows/.gitignore`):

- `providerspecs/` - per-provider `spec.json` copies for the runtime spec
  engine. Source of truth: `Contracts/Providers/<id>/spec.json`. Producer:
  `scripts/sync-specs-to-windows.sh` (CI milestone). Each file matches
  `tauri.conf.json`'s `bundle.resources` glob so it ends up bundled into the
  portable `zip` and the `nsis` / `msi` installers.

- `contracts/` - the full `Contracts/Providers/`, `Contracts/Aggregation/`,
  and `Contracts/Alerts/` tree, used as fixture input for `cargo test` in
  `src-tauri/tests/contract_fixtures.rs` (test milestone). Producer:
  `scripts/sync-contracts-to-windows.sh`.

Both directories are empty by design during the scaffold phase. The first CI
run will populate them via the sync scripts; do not edit by hand.
