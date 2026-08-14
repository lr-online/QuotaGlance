# Repository topology

`Contracts/` is the repository-level authority for shared provider, aggregation,
alert, and refresh-lifecycle behaviour. It is never owned by, or relocated into,
a platform module. Platform copies are generated resources and remain explicitly
identified as such by their platform sync scripts.

The repository is migrating from its historical mixed root layout to this
canonical ownership model:

```text
Contracts/
Shared/
  SwiftCore/
Platforms/
  macOS/
  Android/
  HarmonyOS/
  Windows/
scripts/
docs/
skills/
.github/
```

`project.yml` and the generated Xcode project remain at the repository root
during the migration because XcodeGen consumes them there. They must reference
the macOS host and SwiftCore package through explicit paths. `Package.swift`
moves with SwiftCore, which owns the package implementation, tests, and
package-local resources.

## Migration policy

The migration is expand-contract at the module boundary. A module must exist in
exactly one of its legacy and canonical locations; copying a live module to both
locations is prohibited. A platform migration may land independently after the
topology contract, while the final contraction removes every legacy location.

| Module | Legacy location | Canonical location |
| --- | --- | --- |
| SwiftCore | `Sources/QuotaGlanceCore/` | `Shared/SwiftCore/` |
| macOS host | `App/`, `Widget/`, `NCWidget/`, `NCIntents/`, `Config/`, `Distribution/` | `Platforms/macOS/` |
| Android | `Android/` | `Platforms/Android/` |
| HarmonyOS | `HarmonyOS/` | `Platforms/HarmonyOS/` |
| Windows | `Windows/` | `Platforms/Windows/` |

The six macOS host directories form one buildable unit and must move together.
`script/build_and_run.sh` is the sole temporary legacy alias; it is a pure exec
adapter to the canonical `scripts/run-local.sh`. No new executable belongs in
`script/`.

Run `bash scripts/verify-repository-topology.sh` after changing root-level
ownership. The check is deliberately path-focused: it does not replace the
platform build, package, or provider-parity checks.
