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

The migration is complete. Every module must exist only at its canonical
location; copying a live module to a former root location is prohibited.

| Module | Legacy location | Canonical location |
| --- | --- | --- |
| SwiftCore | `Sources/QuotaGlanceCore/` | `Shared/SwiftCore/` |
| macOS host | `App/`, `Widget/`, `NCWidget/`, `NCIntents/`, `Config/`, `Distribution/` | `Platforms/macOS/` |
| Android | `Android/` | `Platforms/Android/` |
| HarmonyOS | `HarmonyOS/` | `Platforms/HarmonyOS/` |
| Windows | `Windows/` | `Platforms/Windows/` |

The six macOS host directories form one buildable unit. `scripts/run-local.sh`
is the canonical local-run entrypoint; the former singular `script/` directory
is not part of the repository topology.

Run `bash scripts/verify-repository-topology.sh` after changing root-level
ownership. The check is deliberately path-focused: it does not replace the
platform build, package, or provider-parity checks.

Each module relocation also moves its path consumers: package or project
manifests, CI workflows, sync and packaging scripts, and documented commands.
The relocation ticket owns those changes and proves them through that platform's
existing build and package seams. The final contraction verifies that no active
consumer references a legacy module path.
