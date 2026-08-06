---
name: releasing-quotaglance
description: Use when a developer asks to publish, release, tag, or distribute QuotaGlance through GitHub Releases.
---

# Releasing QuotaGlance

Release only from a confirmed existing `vX.Y.Z` tag. A request to "发布" or
"release" starts preparation; it never authorizes a tag creation, push, or
public release.

## Prepare

1. Run `git fetch --force --tags origin`.
2. Find the highest `vX.Y.Z` tag reachable from `HEAD` with
   `git tag --merged HEAD --sort=-version:refname`; ignore non-SemVer tags.
3. Report that tag and `git log --no-merges --oneline <tag>..HEAD`. If no
   release tag exists, report that this would be the first release.
4. Recommend a version: major for `BREAKING CHANGE` or `!`, minor for `feat`,
   patch otherwise. Ask the developer to select one exact unused `vX.Y.Z`.

Do not create a tag or run a workflow before the developer chooses the
version.

## Verify

After the developer selects a version, require a clean worktree, `main` at the
selected target commit, and no matching local or remote tag. Run:

```bash
bash scripts/release-version.sh "$SELECTED_TAG"
swift test
bash scripts/verify-provider-parity.sh
bash Tests/ScriptTests/ReleaseVersionTests.sh
bash Tests/ScriptTests/GitHubActionsTests.sh
```

Show the exact tag and commit SHA, the previous-tag-to-current-tag commit
range, the macOS 12/macOS 14 DMGs, Android universal APK, Windows x64 portable
ZIP, NSIS installer, English and Simplified Chinese MSI installers, and every
SHA-256 file. Also state the explicit exclusion of the unsigned HarmonyOS HAP.
Ask for a distinct final approval.

## Publish

Only after final approval, create and push an annotated tag, then dispatch the
manual workflow:

```bash
git tag -a "$SELECTED_TAG" -m "QuotaGlance $SELECTED_TAG"
git push origin "$SELECTED_TAG"
gh workflow run "Release" --ref main -f tag="$SELECTED_TAG"
```

Find the new `Release` workflow run, report its URL, and wait for its final
conclusion. Do not claim a release completed until the run succeeds and the
GitHub Release contains the macOS DMGs, Android APK, Windows ZIP/NSIS/MSI
assets, and all SHA-256 files.
