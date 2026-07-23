# QuotaGlance macOS 12 Compatibility Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce separately verified Apple Silicon DMGs for a host-only macOS 12 edition and a full macOS 14 Widget edition from the same reviewed source commit.

**Architecture:** Both Xcode host targets compile the same macOS 12-compatible AppKit/SwiftUI source. The legacy target excludes the macOS 14 Widget, while the full target embeds it. Packaging builds in a detached temporary clone and verifies each edition's bundle shape, minimum system version, source archive, signature, and checksum before publication.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Combine, WidgetKit, AppIntents, SwiftPM, XcodeGen, Bash, hdiutil, codesign, spctl.

---

### Task 1: Lock The Distribution Security Contract

**Files:**
- Modify: `Tests/ScriptTests/DMGPackagingTests.sh`
- Modify: `scripts/verify-dmg.sh`
- Modify: `scripts/package-dmg.sh`
- Modify: `scripts/verify-no-secret.sh`

- [ ] **Step 1: Verify the checksum mismatch test is red**

Run `./Tests/ScriptTests/DMGPackagingTests.sh` and expect failure because a
checksum file for `unrelated.bin` is incorrectly accepted for the DMG.

- [ ] **Step 2: Bind checksums to the selected DMG**

Parse the checksum as exactly one SHA-256 line, require its filename to equal
`basename "$DMG_PATH"`, compute the digest of `DMG_PATH`, and compare the two
digests without asking `shasum -c` to resolve another path.

- [ ] **Step 3: Add red tests for unsafe archive and payload paths**

Extend the shell contract with fixtures that reject top-level payload symlinks,
absolute ZIP paths, parent traversal, `.env.*`, logs, snapshots, preference
exports, and Keychain exports. Each fixture must fail before verifier changes.

- [ ] **Step 4: Harden payload and ZIP validation**

Allow only the exact `/Applications` symlink. Require all other DMG payloads to
be regular files or the expected app directory without symlink components.
Inspect every ZIP entry for an absolute path, `..` component, one exact source
prefix, and the sensitive-path denylist.

- [ ] **Step 5: Make scanner errors fail closed**

Capture exit codes from `git grep` and `rg`: zero means a secret was found, one
means no match, and any other status aborts verification.

- [ ] **Step 6: Build and publish from one immutable commit**

Create a detached temporary clone at `HEAD`, build and archive there, place
temporary DMGs in a private staging directory under the final output directory,
and publish with non-overwriting links or equivalent same-filesystem operations.

- [ ] **Step 7: Narrow Gatekeeper handling**

Capture `spctl` output and require the known ad hoc rejection classification.
Reject command errors and unrelated policy failures.

- [ ] **Step 8: Run shell tests and commit**

Run both `./Tests/ScriptTests/DMGPackagingTests.sh` and
`./Tests/ScriptTests/LocalInstallSafetyTests.sh`. Commit only after both pass.

### Task 2: Define The Two Build Editions

**Files:**
- Modify: `Package.swift`
- Modify: `project.yml`
- Regenerate: `QuotaGlance.xcodeproj/project.pbxproj`
- Create: `QuotaGlance.xcodeproj/xcshareddata/xcschemes/QuotaGlanceLegacy.xcscheme`
- Modify: `scripts/build-local.sh`
- Test: `Tests/ScriptTests/BuildEditionTests.sh`

- [ ] **Step 1: Add a red project-contract test**

Assert that the core package supports macOS 12, the legacy host has deployment
target 12 and no Widget dependency, and the full host and Widget remain 14.

- [ ] **Step 2: Add targets and build selection**

Set SwiftPM to macOS 12. Add `QuotaGlanceLegacy` with product name
`QuotaGlance`, the common App sources, and no extension dependency. Keep
`QuotaGlance` and `QuotaGlanceWidget` at macOS 14. Make `build-local.sh` accept
`legacy` or `full`, select the matching scheme, and verify expected extension
presence.

- [ ] **Step 3: Regenerate and verify the project**

Run `xcodegen generate`, then the project-contract test. Use `xcodebuild -list`
to confirm the three shared schemes.

- [ ] **Step 4: Commit the edition scaffold**

Commit the package manifest, project definition, generated Xcode project,
build script, and passing contract test together.

### Task 3: Make The Shared Host Run On macOS 12

**Files:**
- Modify: `App/AppModel.swift`
- Modify: `App/QuotaGlanceApp.swift`
- Create: `App/MenuBar/StatusBarController.swift`
- Modify: `App/MenuBar/MenuBarDashboardView.swift`
- Modify: `App/Settings/SettingsView.swift`
- Modify: `App/Settings/AccountEditorView.swift`
- Modify: `App/SetupWindowPresenter.swift`
- Modify: `App/Services/LaunchAtLoginService.swift`
- Test: `Tests/ScriptTests/BuildEditionTests.sh`

- [ ] **Step 1: Compile the legacy target to capture unavailable APIs**

Run `./scripts/build-local.sh Debug legacy` and keep the compiler diagnostics as
the red test for the current host source.

- [ ] **Step 2: Replace Observation with Combine observation**

Make `AppModel` an `ObservableObject`, publish each UI-observed property, and
mark model properties in SwiftUI views with `@ObservedObject`. Replace
duration-based sleep with `Task.sleep(nanoseconds:)`.

- [ ] **Step 3: Add the AppKit status bar lifecycle**

Own `AppModel`, `NSStatusItem`, and a fixed-size `NSPopover` from the application
delegate. Host `MenuBarDashboardView` in the popover, toggle it from the status
item button, start refresh after application launch, and show setup when there
are no accounts.

- [ ] **Step 4: Replace unavailable SwiftUI convenience views**

Replace `SettingsLink` with a compatible settings action and replace
`ContentUnavailableView` with an ordinary Label/VStack state. Hide launch at
login on macOS 12. Guard `SMAppService` behind macOS 13 availability.

- [ ] **Step 5: Build both editions**

Run `./scripts/build-local.sh Debug legacy` and
`./scripts/build-local.sh Debug full`. Inspect `LSMinimumSystemVersion`, verify
the legacy app has no `PlugIns` Widget, and verify the full app has the expected
Widget.

- [ ] **Step 6: Run core and script tests, then commit**

Run `swift test` and all `Tests/ScriptTests/*.sh`, then commit the compatible
host implementation.

### Task 4: Package And Verify Both Editions

**Files:**
- Create: `Distribution/README-macOS12.txt`
- Create: `Distribution/README-macOS14.txt`
- Modify: `README.md`
- Modify: `scripts/package-dmg.sh`
- Modify: `scripts/verify-dmg.sh`
- Modify: `Tests/ScriptTests/DMGPackagingTests.sh`

- [ ] **Step 1: Add red dual-artifact assertions**

Require distinct macOS 12 and macOS 14 DMG names, checksums, minimum versions,
and extension presence contracts. Remove the hard-coded source version from
tests by reading the project or built app version.

- [ ] **Step 2: Generate edition-aware instructions**

Package a README that names its edition and clearly states whether desktop
Widgets and launch at login are supported. Keep the source archive and commit
record in both images.

- [ ] **Step 3: Package both artifacts**

Make the default packaging command produce both edition DMGs from one detached
commit. Permit an explicit edition for focused testing without changing the
source identity.

- [ ] **Step 4: Verify distribution artifacts**

For each DMG run `verify-dmg.sh`, `hdiutil verify`, `codesign --verify --deep
--strict`, `lipo -archs`, `plutil` minimum-version inspection, source ZIP path
inspection, source commit comparison, and the configured-key byte scan when
`LAOGE_KEY` exists.

- [ ] **Step 5: Commit documentation and packaging changes**

Commit only after the dual-artifact round trip and all regression tests pass.

### Task 5: Merge And Deliver From Main

**Files:**
- Output: `dist/QuotaGlance-<version>-macOS12-arm64.dmg`
- Output: `dist/QuotaGlance-<version>-macOS14-arm64.dmg`
- Output: adjacent `.sha256` files

- [ ] **Step 1: Confirm branch cleanliness and commit identity**

Require a clean feature worktree and record its 40-character commit.

- [ ] **Step 2: Fast-forward main**

Run `git merge --ff-only feature/quota-glance-phase-one` in the primary
worktree. Do not push because this repository has no remote.

- [ ] **Step 3: Re-run verification on main**

Run `swift test`, every shell test, both Release builds, and both DMG verifiers
from `main`.

- [ ] **Step 4: Generate final artifacts from main**

Run the packaging command in the main worktree so each embedded source archive
and `SOURCE-COMMIT.txt` names the merged `main` commit. Record byte size and
SHA-256 for both DMGs.

- [ ] **Step 5: Remove the merged worktree and branch**

After confirming the main worktree and artifacts are intact, remove the clean
feature worktree and delete its fully merged local branch.
