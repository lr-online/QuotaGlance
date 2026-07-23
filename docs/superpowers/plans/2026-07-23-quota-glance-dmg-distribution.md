# QuotaGlance DMG Distribution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and verify a reproducible, ad hoc signed, Apple Silicon DMG containing the app and its exact reviewable source revision.

**Architecture:** Keep the existing Xcode Release build and local entitlement model as the source of the distributable app. Require a clean Git worktree, use `git archive` for the source zip, and add one packaging command that stages only the app, source, commit record, Applications symlink, and tracked recipient README. A separate mounted-image verifier checks layout, source provenance, architecture, signatures, entitlements, widget metadata, and checksum.

**Tech Stack:** Bash 3.2, Xcode/xcodebuild, `codesign`, `hdiutil`, `lipo`, `plutil`, `shasum`, Swift Testing, Git worktrees.

---

## File Map

- Create `Distribution/README.txt`: recipient-facing installation and Gatekeeper instructions included in the DMG.
- Create `scripts/package-dmg.sh`: clean-tree enforcement, source archive, Release build, staging, image creation, preflight checks, and checksum generation.
- Create `scripts/verify-dmg.sh`: read-only mount and distribution artifact validation.
- Create `Tests/ScriptTests/DMGPackagingTests.sh`: real integration coverage for secret scanning, DMG creation, verification, and overwrite refusal.
- Modify `scripts/verify-no-secret.sh`: accept an optional app bundle path so packaging can scan the actual build artifact.
- Modify `.gitignore`: exclude generated `dist/` artifacts.
- Modify `README.md`: document DMG creation and recipient installation limitations.

### Task 1: Make Secret Scanning Artifact-Aware

**Files:**
- Create: `Tests/ScriptTests/DMGPackagingTests.sh`
- Modify: `scripts/verify-no-secret.sh:7-40`

- [ ] **Step 1: Write the failing artifact-path test**

Create `Tests/ScriptTests/DMGPackagingTests.sh` with the initial secret-scan test:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_ROOT="$(mktemp -d /tmp/QuotaGlance-dmg-tests.XXXXXX)"
trap '/bin/chmod -R u+rwX "$TEST_ROOT"; /bin/rm -rf "$TEST_ROOT"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_fails() {
  if "$@" >/dev/null 2>&1; then
    fail "command unexpectedly succeeded: $*"
  fi
}

test_secret_scan_accepts_an_artifact_path() {
  local clean_app="$TEST_ROOT/Clean.app"
  local contaminated_app="$TEST_ROOT/Contaminated.app"
  local sentinel
  sentinel="$(printf '%s%s' 'quota-glance-packaging-' 'sentinel')"

  /bin/mkdir -p "$clean_app" "$contaminated_app"
  LAOGE_KEY="$sentinel" \
    "$ROOT_DIR/scripts/verify-no-secret.sh" "$clean_app" >/dev/null

  printf '%s' "$sentinel" > "$contaminated_app/payload"
  assert_fails env LAOGE_KEY="$sentinel" \
    "$ROOT_DIR/scripts/verify-no-secret.sh" "$contaminated_app"
}

test_secret_scan_accepts_an_artifact_path
echo "DMG packaging tests passed"
```

- [ ] **Step 2: Run the test and verify RED**

Run:

```bash
/bin/bash Tests/ScriptTests/DMGPackagingTests.sh
```

Expected: FAIL because `verify-no-secret.sh` ignores the supplied app path and requires the installed app.

- [ ] **Step 3: Implement optional artifact selection**

In `scripts/verify-no-secret.sh`, replace the installed-app constant and its uses:

```bash
APP_BUNDLE="${1:-$HOME/Applications/QuotaGlance.app}"
```

Use `APP_BUNDLE` for the directory check and binary byte scan:

```bash
if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "App bundle not found: $APP_BUNDLE" >&2
  exit 1
fi

if rg -a -q -F -f "$SECRET_PATTERN_FILE" "$APP_BUNDLE"; then
  echo "Secret bytes found in app bundle" >&2
  exit 1
fi
```

- [ ] **Step 4: Run the test and verify GREEN**

Run:

```bash
/bin/bash Tests/ScriptTests/DMGPackagingTests.sh
```

Expected: `DMG packaging tests passed`.

- [ ] **Step 5: Commit**

```bash
git add Tests/ScriptTests/DMGPackagingTests.sh scripts/verify-no-secret.sh
git commit -m "test: scan selected distribution artifacts"
```

### Task 2: Add Distribution Contents And Packaging Contract

**Files:**
- Create: `Distribution/README.txt`
- Modify: `.gitignore`
- Modify: `Tests/ScriptTests/DMGPackagingTests.sh`

- [ ] **Step 1: Add recipient instructions**

Create `Distribution/README.txt`:

```text
QuotaGlance 0.1.0 安装说明

系统要求
- Apple Silicon Mac（M1 或更新）
- macOS 14 或更高版本

安装
1. 将 QuotaGlance.app 拖到 Applications。
2. 推出 QuotaGlance 磁盘映像。
3. 打开“应用程序”，按住 Control 点击 QuotaGlance，然后选择“打开”。
4. 如果 macOS 仍然阻止启动，请打开“系统设置 > 隐私与安全性”，选择“仍要打开”。

初次使用
1. 从菜单栏打开 QuotaGlance 设置。
2. 添加自己的 API Info 账户名称和 key；key 只保存在本机 Keychain。
3. 成功刷新一次后，在桌面小组件库中搜索 QuotaGlance。
4. 添加名为 QuotaGlance 的可配置小组件；右键“编辑小组件”可以选择账户。

说明
- 此版本仅支持 API Info 和 Apple Silicon Mac。
- 此版本使用临时签名，未经过 Apple Developer ID 签名或 Apple 公证，因此首次启动需要手动批准。
- 安装包不包含制作者的 API key、账户、余额或用量数据。
- `QuotaGlance-0.1.0-source.zip` 是与应用一同打包的源码；`SOURCE-COMMIT.txt` 记录对应的 Git commit，方便审查。
```

- [ ] **Step 2: Ignore generated artifacts**

Append to `.gitignore`:

```gitignore

# Distribution artifacts
dist/
```

- [ ] **Step 3: Extend the test with the packaging contract**

Add these variables near the top of `Tests/ScriptTests/DMGPackagingTests.sh`:

```bash
PACKAGE_SCRIPT="$ROOT_DIR/scripts/package-dmg.sh"
VERIFY_SCRIPT="$ROOT_DIR/scripts/verify-dmg.sh"
```

Add this test before the final invocation block:

```bash
test_distribution_contract() {
  [[ -f "$ROOT_DIR/Distribution/README.txt" ]] \
    || fail "distribution README is missing"
  rg -q '未经过 Apple Developer ID 签名或 Apple 公证' \
    "$ROOT_DIR/Distribution/README.txt" \
    || fail "distribution README does not disclose Gatekeeper limitations"
  rg -q '^dist/$' "$ROOT_DIR/.gitignore" \
    || fail "dist directory is not ignored"
  [[ -x "$PACKAGE_SCRIPT" ]] || fail "package script is missing"
  [[ -x "$VERIFY_SCRIPT" ]] || fail "DMG verifier is missing"
}
```

Invoke it after the secret-scan test:

```bash
test_distribution_contract
```

- [ ] **Step 4: Run the test and verify RED**

Run:

```bash
/bin/bash Tests/ScriptTests/DMGPackagingTests.sh
```

Expected: FAIL with `package script is missing`.

- [ ] **Step 5: Commit the contract and failing test**

```bash
git add .gitignore Distribution/README.txt Tests/ScriptTests/DMGPackagingTests.sh
git commit -m "test: define dmg distribution contract"
```

### Task 3: Implement DMG Verification And Packaging

**Files:**
- Create: `scripts/verify-dmg.sh`
- Create: `scripts/package-dmg.sh`
- Modify: `Tests/ScriptTests/DMGPackagingTests.sh`

- [ ] **Step 1: Implement mounted-image verification**

Create executable `scripts/verify-dmg.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

DMG_PATH="${1:?usage: verify-dmg.sh DMG_PATH [CHECKSUM_PATH]}"
CHECKSUM_PATH="${2:-}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE_ID="com.liangrui.QuotaGlance"
WIDGET_BUNDLE_ID="com.liangrui.QuotaGlance.Widget"
VERIFY_DIR="$(mktemp -d /tmp/QuotaGlance-dmg-verify.XXXXXX)"
ATTACH_PLIST="$VERIFY_DIR/attach.plist"
MOUNT_POINT=""

cleanup() {
  if [[ -n "$MOUNT_POINT" && -d "$MOUNT_POINT" ]]; then
    /usr/bin/hdiutil detach "$MOUNT_POINT" >/dev/null 2>&1 || true
  fi
  /bin/rm -rf -- "$VERIFY_DIR"
}
trap cleanup EXIT

bundle_id() {
  /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
    "$1/Contents/Info.plist" 2>/dev/null
}

[[ -f "$DMG_PATH" && ! -L "$DMG_PATH" ]] || {
  echo "DMG is missing or is not a regular file: $DMG_PATH" >&2
  exit 1
}

/usr/bin/hdiutil verify "$DMG_PATH" >/dev/null

if [[ -n "$CHECKSUM_PATH" ]]; then
  [[ -f "$CHECKSUM_PATH" && ! -L "$CHECKSUM_PATH" ]] || {
    echo "Checksum is missing or is not a regular file: $CHECKSUM_PATH" >&2
    exit 1
  }
  (
    cd "$(dirname "$CHECKSUM_PATH")"
    /usr/bin/shasum -a 256 -c "$(basename "$CHECKSUM_PATH")"
  ) >/dev/null
fi

/usr/bin/hdiutil attach -readonly -nobrowse -plist "$DMG_PATH" > "$ATTACH_PLIST"
for index in {0..15}; do
  candidate="$(/usr/libexec/PlistBuddy \
    -c "Print :system-entities:$index:mount-point" \
    "$ATTACH_PLIST" 2>/dev/null || true)"
  if [[ -n "$candidate" ]]; then
    MOUNT_POINT="$candidate"
    break
  fi
done

[[ -n "$MOUNT_POINT" && -d "$MOUNT_POINT" ]] || {
  echo "DMG did not mount successfully" >&2
  exit 1
}

APP="$MOUNT_POINT/QuotaGlance.app"
[[ -d "$APP" ]] || {
  echo "DMG app is missing" >&2
  exit 1
}
VERSION="$(/usr/libexec/PlistBuddy \
  -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
SOURCE_NAME="QuotaGlance-$VERSION-source.zip"

ACTUAL_ITEMS="$(
  /usr/bin/find "$MOUNT_POINT" -mindepth 1 -maxdepth 1 \
    -exec /usr/bin/basename {} \; | LC_ALL=C /usr/bin/sort
)"
EXPECTED_ITEMS="$(printf '%s\n' \
  'Applications' \
  'QuotaGlance.app' \
  'README.txt' \
  'SOURCE-COMMIT.txt' \
  "$SOURCE_NAME" | LC_ALL=C /usr/bin/sort)"
[[ "$ACTUAL_ITEMS" == "$EXPECTED_ITEMS" ]] || {
  echo "DMG top-level layout is invalid:" >&2
  printf '%s\n' "$ACTUAL_ITEMS" >&2
  exit 1
}

[[ -L "$MOUNT_POINT/Applications" \
  && "$(/usr/bin/readlink "$MOUNT_POINT/Applications")" == "/Applications" ]] || {
  echo "DMG Applications shortcut is invalid" >&2
  exit 1
}

WIDGET="$APP/Contents/PlugIns/QuotaGlanceWidget.appex"
[[ "$(bundle_id "$APP")" == "$APP_BUNDLE_ID" ]] || {
  echo "Unexpected host bundle identifier" >&2
  exit 1
}
[[ "$(bundle_id "$WIDGET")" == "$WIDGET_BUNDLE_ID" ]] || {
  echo "Unexpected widget bundle identifier" >&2
  exit 1
}

/usr/bin/codesign --verify --deep --strict "$APP"
"$ROOT_DIR/scripts/verify-local-widget-bundle.sh" "$APP"
"$ROOT_DIR/scripts/verify-widget-entrypoint.sh" "$WIDGET"

ARCHS="$(/usr/bin/lipo -archs "$APP/Contents/MacOS/QuotaGlance")"
[[ "$ARCHS" == "arm64" ]] || {
  echo "DMG app must contain only arm64, found: $ARCHS" >&2
  exit 1
}

SIGNING_DETAILS="$(/usr/bin/codesign -dvvv "$APP" 2>&1)"
rg -q '^Signature=adhoc$' <<< "$SIGNING_DETAILS" || {
  echo "DMG app is not ad hoc signed as documented" >&2
  exit 1
}

rg -q '未经过 Apple Developer ID 签名或 Apple 公证' "$MOUNT_POINT/README.txt" || {
  echo "DMG README does not disclose Gatekeeper limitations" >&2
  exit 1
}

SOURCE_ZIP="$MOUNT_POINT/$SOURCE_NAME"
SOURCE_COMMIT="$(/usr/bin/sed -n 's/^Git commit: //p' \
  "$MOUNT_POINT/SOURCE-COMMIT.txt")"
[[ "$SOURCE_COMMIT" =~ ^[0-9a-f]{40}$ ]] || {
  echo "DMG source commit record is invalid" >&2
  exit 1
}
/usr/bin/unzip -tq "$SOURCE_ZIP" >/dev/null
ARCHIVE_COMMENT="$(/usr/bin/unzip -z "$SOURCE_ZIP" | /usr/bin/tail -n 1 \
  | /usr/bin/tr -d '\r')"
[[ "$ARCHIVE_COMMENT" == "$SOURCE_COMMIT" ]] || {
  echo "Source archive comment does not match SOURCE-COMMIT.txt" >&2
  exit 1
}
SOURCE_ITEMS="$(/usr/bin/unzip -Z1 "$SOURCE_ZIP")"
SOURCE_PREFIXES="$(printf '%s\n' "$SOURCE_ITEMS" | /usr/bin/cut -d/ -f1 \
  | LC_ALL=C /usr/bin/sort -u)"
[[ "$SOURCE_PREFIXES" == "QuotaGlance-$VERSION-source" ]] || {
  echo "Source archive has an unexpected top-level prefix" >&2
  exit 1
}
if rg -q '(^|/)(\.env|\.git|DerivedData|dist|\.build|xcuserdata)(/|$)' \
  <<< "$SOURCE_ITEMS"; then
  echo "Source archive contains a forbidden path" >&2
  exit 1
fi

if /usr/sbin/spctl -a -vv --type execute "$APP" >/dev/null 2>&1; then
  echo "Gatekeeper unexpectedly accepted the ad hoc build" >&2
else
  echo "Gatekeeper rejection confirmed for the documented ad hoc build"
fi

echo "DMG verification passed: $DMG_PATH"
```

Make it executable:

```bash
chmod +x scripts/verify-dmg.sh
```

- [ ] **Step 2: Implement the package command**

Create executable `scripts/package-dmg.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${1:-$ROOT_DIR/dist}"
README_SOURCE="$ROOT_DIR/Distribution/README.txt"
GIT="/usr/bin/git"
WORK_DIR="$(mktemp -d /tmp/QuotaGlance-dmg-package.XXXXXX)"
STAGING_DIR="$WORK_DIR/staging"

cleanup() {
  /bin/rm -rf -- "$WORK_DIR"
}
trap cleanup EXIT

[[ -f "$README_SOURCE" && ! -L "$README_SOURCE" ]] || {
  echo "Distribution README is missing: $README_SOURCE" >&2
  exit 1
}
[[ ! -L "$OUTPUT_DIR" ]] || {
  echo "Refusing symlink output directory: $OUTPUT_DIR" >&2
  exit 1
}

cd "$ROOT_DIR"
[[ -z "$("$GIT" status --porcelain --untracked-files=all)" ]] || {
  echo "Refusing to package a dirty Git worktree" >&2
  exit 1
}
SOURCE_COMMIT="$("$GIT" rev-parse HEAD)"
[[ "$SOURCE_COMMIT" =~ ^[0-9a-f]{40}$ ]] || {
  echo "Unable to resolve the source commit" >&2
  exit 1
}

BUILT_APP="$("$ROOT_DIR/scripts/build-local.sh" Release)"
VERSION="$(/usr/libexec/PlistBuddy \
  -c 'Print :CFBundleShortVersionString' \
  "$BUILT_APP/Contents/Info.plist")"
[[ "$VERSION" =~ ^[0-9A-Za-z][0-9A-Za-z.-]*$ ]] || {
  echo "Invalid app version for artifact name: $VERSION" >&2
  exit 1
}

DMG_NAME="QuotaGlance-$VERSION-arm64.dmg"
CHECKSUM_NAME="$DMG_NAME.sha256"
SOURCE_NAME="QuotaGlance-$VERSION-source.zip"
FINAL_DMG="$OUTPUT_DIR/$DMG_NAME"
FINAL_CHECKSUM="$OUTPUT_DIR/$CHECKSUM_NAME"
TEMP_DMG="$WORK_DIR/$DMG_NAME"
TEMP_CHECKSUM="$WORK_DIR/$CHECKSUM_NAME"

if [[ -e "$FINAL_DMG" || -L "$FINAL_DMG" \
  || -e "$FINAL_CHECKSUM" || -L "$FINAL_CHECKSUM" ]]; then
  echo "Refusing to overwrite an existing distribution artifact" >&2
  exit 1
fi

/usr/bin/codesign --verify --deep --strict "$BUILT_APP"
"$ROOT_DIR/scripts/verify-local-widget-bundle.sh" "$BUILT_APP"
"$ROOT_DIR/scripts/verify-widget-entrypoint.sh" \
  "$BUILT_APP/Contents/PlugIns/QuotaGlanceWidget.appex"

ARCHS="$(/usr/bin/lipo -archs "$BUILT_APP/Contents/MacOS/QuotaGlance")"
[[ "$ARCHS" == "arm64" ]] || {
  echo "Release build must contain only arm64, found: $ARCHS" >&2
  exit 1
}

if [[ -n "${LAOGE_KEY:-}" ]]; then
  "$ROOT_DIR/scripts/verify-no-secret.sh" "$BUILT_APP"
else
  echo "LAOGE_KEY is not set; skipping configured-key byte scan"
fi

/bin/mkdir -p "$STAGING_DIR"
/usr/bin/ditto "$BUILT_APP" "$STAGING_DIR/QuotaGlance.app"
/bin/cp "$README_SOURCE" "$STAGING_DIR/README.txt"
/bin/ln -s /Applications "$STAGING_DIR/Applications"
"$GIT" archive \
  --format=zip \
  --prefix="QuotaGlance-$VERSION-source/" \
  --output="$STAGING_DIR/$SOURCE_NAME" \
  "$SOURCE_COMMIT"
printf 'Git commit: %s\n' "$SOURCE_COMMIT" \
  > "$STAGING_DIR/SOURCE-COMMIT.txt"

/usr/bin/hdiutil create \
  -volname QuotaGlance \
  -srcfolder "$STAGING_DIR" \
  -format UDZO \
  -imagekey zlib-level=9 \
  "$TEMP_DMG" >/dev/null

(
  cd "$WORK_DIR"
  /usr/bin/shasum -a 256 "$DMG_NAME" > "$CHECKSUM_NAME"
)

"$ROOT_DIR/scripts/verify-dmg.sh" "$TEMP_DMG" "$TEMP_CHECKSUM"

/bin/mkdir -p "$OUTPUT_DIR"
/bin/mv "$TEMP_DMG" "$FINAL_DMG"
/bin/mv "$TEMP_CHECKSUM" "$FINAL_CHECKSUM"

printf '%s\n%s\n' "$FINAL_DMG" "$FINAL_CHECKSUM"
```

Make it executable:

```bash
chmod +x scripts/package-dmg.sh
```

- [ ] **Step 3: Extend the integration test to build a real DMG**

Add this test to `Tests/ScriptTests/DMGPackagingTests.sh`:

```bash
test_real_dmg_round_trip() {
  local clean_repo="$TEST_ROOT/clean-repository"
  local clean_output="$TEST_ROOT/output"
  local clean_package
  local clean_verify

  /usr/bin/git clone --quiet --no-local "$ROOT_DIR" "$clean_repo"
  /usr/bin/ditto "$PACKAGE_SCRIPT" "$clean_repo/scripts/package-dmg.sh"
  /usr/bin/ditto "$VERIFY_SCRIPT" "$clean_repo/scripts/verify-dmg.sh"
  /usr/bin/git -C "$clean_repo" add scripts/package-dmg.sh scripts/verify-dmg.sh
  /usr/bin/git -C "$clean_repo" \
    -c user.name='QuotaGlance Tests' \
    -c user.email='tests@localhost' \
    commit --quiet -m 'test fixture: add dmg packaging scripts'

  clean_package="$clean_repo/scripts/package-dmg.sh"
  clean_verify="$clean_repo/scripts/verify-dmg.sh"
  /bin/mkdir -p "$clean_output"
  "$clean_package" "$clean_output" >/dev/null

  local dmg="$clean_output/QuotaGlance-0.1.0-arm64.dmg"
  local checksum="$dmg.sha256"
  [[ -f "$dmg" ]] || fail "DMG was not created"
  [[ -f "$checksum" ]] || fail "DMG checksum was not created"
  "$clean_verify" "$dmg" "$checksum" >/dev/null

  assert_fails "$clean_package" "$clean_output"
}
```

Invoke it after `test_distribution_contract`:

```bash
test_real_dmg_round_trip
```

- [ ] **Step 4: Run the integration test and verify GREEN**

Run:

```bash
/bin/bash Tests/ScriptTests/DMGPackagingTests.sh
```

Expected: two successful Release builds, a verified mount round trip, overwrite refusal on the second package attempt, and `DMG packaging tests passed`.

- [ ] **Step 5: Run shell and repository regression checks**

Run:

```bash
for file in scripts/*.sh Tests/ScriptTests/*.sh; do
  /bin/bash -n "$file"
done
/bin/bash Tests/ScriptTests/LocalInstallSafetyTests.sh
swift test
git diff --check
```

Expected: shell syntax clean, local safety tests pass, 58 Swift tests pass, and no whitespace errors.

- [ ] **Step 6: Commit**

```bash
git add scripts/package-dmg.sh scripts/verify-dmg.sh Tests/ScriptTests/DMGPackagingTests.sh
git commit -m "feat: package verified arm64 dmg"
```

### Task 4: Document Packaging And Produce The Release Artifact

**Files:**
- Modify: `README.md`
- Generate (ignored): `dist/QuotaGlance-0.1.0-arm64.dmg`
- Generate (ignored): `dist/QuotaGlance-0.1.0-arm64.dmg.sha256`

- [ ] **Step 1: Add maintainer packaging instructions to README**

Add a `## 生成分享版 DMG` section after local build and installation:

````markdown
## 生成分享版 DMG

当前分享版仅支持 Apple Silicon，使用临时签名且未经过 Apple 公证：

```bash
./scripts/package-dmg.sh
```

产物位于 `dist/QuotaGlance-0.1.0-arm64.dmg`，相邻的 `.sha256` 文件用于校验下载或传输完整性。DMG 同时包含 `QuotaGlance-0.1.0-source.zip` 和 `SOURCE-COMMIT.txt`，供接收者核对并审查对应源码。接收者需将应用拖入 Applications，并在首次启动时按住 Control 点击应用后选择“打开”；如果仍被拦截，请在“系统设置 > 隐私与安全性”中选择“仍要打开”。
````

- [ ] **Step 2: Commit documentation**

```bash
git add README.md
git commit -m "docs: explain dmg distribution"
```

- [ ] **Step 3: Produce a fresh default artifact**

Run:

```bash
./scripts/package-dmg.sh
```

Expected output paths:

```text
/Users/liangrui/Projects/QuotaGlance/.worktrees/quota-glance-phase-one/dist/QuotaGlance-0.1.0-arm64.dmg
/Users/liangrui/Projects/QuotaGlance/.worktrees/quota-glance-phase-one/dist/QuotaGlance-0.1.0-arm64.dmg.sha256
```

- [ ] **Step 4: Verify artifact, checksum, Gatekeeper status, and Git state**

Run:

```bash
./scripts/verify-dmg.sh \
  dist/QuotaGlance-0.1.0-arm64.dmg \
  dist/QuotaGlance-0.1.0-arm64.dmg.sha256
(
  cd dist
  /usr/bin/shasum -a 256 -c QuotaGlance-0.1.0-arm64.dmg.sha256
)
/usr/sbin/spctl -a -vv --type open \
  --context context:primary-signature \
  dist/QuotaGlance-0.1.0-arm64.dmg || true
git status --short --branch
```

Expected: DMG verification and checksum pass; Gatekeeper reports rejection because the image is not notarized; `dist/` remains ignored and the tracked worktree is clean.

### Task 5: Review, Merge To Main, And Verify The Merged Result

**Files:**
- No new source files.

- [ ] **Step 1: Request focused code review**

Ask a reviewer to inspect all changes after `6712c8b`, focusing on destructive path safety, mount cleanup, signature and architecture assertions, accurate Gatekeeper messaging, and secret exclusion.

- [ ] **Step 2: Address Critical and Important findings**

Apply fixes with a failing test first, rerun `DMGPackagingTests.sh`, and commit each correction. Do not defer Critical or Important findings.

- [ ] **Step 3: Run final branch verification**

Run:

```bash
swift test
for file in scripts/*.sh Tests/ScriptTests/*.sh; do
  /bin/bash -n "$file"
done
/bin/bash Tests/ScriptTests/LocalInstallSafetyTests.sh
/bin/bash Tests/ScriptTests/DMGPackagingTests.sh
./scripts/verify-dmg.sh \
  dist/QuotaGlance-0.1.0-arm64.dmg \
  dist/QuotaGlance-0.1.0-arm64.dmg.sha256
git diff --check
git status --short --branch
```

Expected: 58 Swift tests pass, all shell tests and DMG checks pass, and the feature worktree is clean.

- [ ] **Step 4: Merge locally into main**

From `/Users/liangrui/Projects/QuotaGlance`:

```bash
git checkout main
git merge feature/quota-glance-phase-one
swift test
```

Expected: fast-forward merge and 58 passing tests on `main`.

- [ ] **Step 5: Preserve the release artifact and clean the feature worktree**

Copy the ignored DMG and checksum to `/Users/liangrui/Projects/QuotaGlance/dist/`, verify them from `main`, then remove the feature worktree and delete the merged feature branch according to the finishing-a-development-branch workflow.
