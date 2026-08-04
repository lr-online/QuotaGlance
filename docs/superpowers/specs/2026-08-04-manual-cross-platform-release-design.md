# Manual Cross-Platform Release Design

## Goal

Publish versioned macOS and Android assets from an explicitly selected existing
Git tag. Keep HarmonyOS as an unsigned CI artifact until signing is available.
Make the release process discoverable through a repository skill that requires
the developer to choose and confirm the next version.

## Workflow Boundaries

- Rename `package.yml` to the displayed workflow name `Package macOS`. It keeps
  its PR, main, merge-queue, and manual DMG packaging triggers.
- `release.yml` has only `workflow_dispatch`. Its required `tag` input must be
  an existing `vX.Y.Z` tag, and each job checks out that tag rather than the
  branch selected in the Actions UI.
- `android.yml` remains a verification and artifact-build workflow. It no
  longer reacts to tags or publishes GitHub Release assets.
- The Release workflow builds macOS 12/macOS 14 DMGs and an Android universal
  APK. It deliberately excludes the unsigned HarmonyOS HAP.

## Version Contract

The selected tag is the release version source. `scripts/release-version.sh`
rejects malformed SemVer tags and emits the normalized version plus an Android
version code calculated as `major * 1_000_000 + minor * 1_000 + patch`.

- macOS receives `QUOTAGLANCE_VERSION=vX.Y.Z`; its existing package script
  embeds `X.Y.Z` in both DMG names.
- Android receives Gradle properties for `versionName` and `versionCode`; its
  checked-in development values remain the default for normal builds.
- Normal Package macOS, Android, and HarmonyOS CI artifacts use the platform's
  declared version plus a short commit SHA. Android and HarmonyOS copy package
  files to those versioned names and emit SHA-256 files.

## Manual Release

The Release workflow uses `prepare`, `macos`, `android`, and `publish` jobs.
`prepare` verifies the selected tag resolves to the checked-out commit and
emits the release version. Build jobs have read-only permissions and upload
only versioned assets and checksums. `publish` alone has `contents: write`,
downloads both asset sets, and creates or updates the GitHub Release.

Release notes are generated from non-merge commit subjects between the previous
reachable SemVer tag and the selected tag. The release action uses the generated
`release-notes.md` body and does not request GitHub-generated notes.

## Release Skill

`skills/releasing-quotaglance/SKILL.md` routes requests to publish or release
through two approvals. It first fetches tags, reports the latest reachable tag
and subsequent commits, recommends a SemVer bump, and asks the developer to
select the exact next version. After local checks it presents the target commit,
macOS/Android asset scope, HarmonyOS exclusion, and release-note range, then
requires final approval before it creates/pushes an annotated tag or dispatches
Release.

## Verification

`ReleaseVersionTests.sh` checks tag parsing, version-code bounds, and Gradle
property integration. `GitHubActionsTests.sh` checks the workflow display name,
manual-only Release trigger, tag checkout, centralized publish ownership,
versioned artifacts, commit-derived notes, and HarmonyOS release exclusion.
