# QuotaGlance DMG Distribution Design

Status: Approved for written-spec review
Date: 2026-07-23

## Objective

Create a reproducible Apple Silicon DMG for sharing QuotaGlance with a small
group of users. The image must provide the standard drag-to-Applications flow,
preserve the working menu bar app and WidgetKit extension, contain no personal
API keys or cached account data, and clearly explain the first-launch
Gatekeeper override required by an ad hoc signed application.

## Confirmed Decisions

- Distribution format: compressed read-only DMG.
- Architecture: Apple Silicon (`arm64`) only.
- Minimum system: macOS 14.
- Signing: existing ad hoc signature with local sandbox entitlements.
- Notarization: not included because this Mac has no Developer ID identity.
- Installation: drag `QuotaGlance.app` to the `Applications` shortcut.
- Version: read from the built app rather than duplicated in the packaging
  script.
- Initial artifact name: `QuotaGlance-0.1.0-arm64.dmg`.

The missing Developer ID signature is a distribution constraint, not a build
failure. Recipients must explicitly approve the first launch. A future
Developer ID and notarization workflow can replace the signing stage without
changing the DMG layout.

## Deliverables

The packaging command will produce:

```text
dist/
  QuotaGlance-0.1.0-arm64.dmg
  QuotaGlance-0.1.0-arm64.dmg.sha256
```

The mounted DMG will contain:

```text
QuotaGlance.app
Applications -> /Applications
README.txt
```

`README.txt` will contain concise Chinese installation, first-launch, account
setup, and widget setup instructions. It will state that the build is arm64,
ad hoc signed, and not notarized.

## Packaging Flow

A tracked `scripts/package-dmg.sh` command will own the complete workflow:

1. Build the existing Release application through `scripts/build-local.sh`.
2. Read `CFBundleShortVersionString` from the built application.
3. Require the expected host and widget bundle identifiers.
4. Validate nested signatures, local entitlements, App Intent account metadata,
   legacy widget compatibility, and the WidgetKit extension entry point.
5. Stage only the built application, the Applications symlink, and the tracked
   distribution README in a temporary directory.
6. Create a compressed UDZO image with `hdiutil` and volume name `QuotaGlance`.
7. Verify the image, mount it read-only without opening Finder, and validate the
   mounted app and layout.
8. Detach the image and generate a SHA-256 checksum beside it.

The script will use temporary output followed by an atomic move. It will refuse
to overwrite an existing final DMG or checksum so a prior release is never
silently replaced.

## Recipient Experience

The documented installation path is:

1. Open the DMG and drag QuotaGlance into Applications.
2. Eject the image.
3. In Applications, Control-click QuotaGlance and choose Open.
4. If macOS still blocks the app, use System Settings, Privacy & Security, Open
   Anyway. No terminal command is required.
5. Add API Info credentials inside QuotaGlance and refresh once.
6. Add the configurable QuotaGlance widget from the macOS widget gallery.

Existing account data is not shipped. Each recipient receives a clean app and
stores their own credentials in their own macOS Keychain.

## Security And Privacy

- The DMG must not contain `.env` files, API keys, shared snapshots, Keychain
  exports, logs, DerivedData, or user preferences.
- When `LAOGE_KEY` is available, the packaging workflow will run the existing
  byte-level secret scan against tracked files and the built app before
  accepting the artifact. Independently, staging is restricted to the built
  app, tracked README, and Applications symlink.
- The host keeps network client access and read-write access to its private
  `/Users/Shared/QuotaGlance/` snapshot directory.
- The widget remains network-free and receives read-only snapshot access.
- Ad hoc signing and Gatekeeper status must be reported accurately; the README
  must not imply Apple notarization or an identified developer signature.

## Verification

Packaging is complete only when all of the following pass:

- the Swift test suite;
- shell syntax and local installation safety tests;
- the repository and artifact secret scan;
- Release application build;
- `codesign --verify --deep --strict` on the staged and mounted app;
- existing local widget bundle and extension entry-point verifiers;
- host and widget bundle identifier checks;
- `lipo -archs` confirming arm64 and excluding x86_64;
- `hdiutil verify`;
- read-only mount inspection confirming exactly the expected top-level items;
- checksum verification using the generated `.sha256` file.

Gatekeeper assessment is expected to reject this build because it is ad hoc
signed. Verification must record that expected limitation rather than treating
it as notarization success.

## Failure Handling

- Missing Xcode, incomplete first-launch setup, build failure, signature
  failure, widget validation failure, or secret-scan failure stops packaging.
- A missing distribution README stops packaging.
- An existing final artifact stops packaging instead of overwriting it.
- A mount or layout validation failure detaches any mounted image and leaves no
  final artifact.
- Temporary staging directories and intermediate images are removed on exit.

## Out Of Scope

- Developer ID signing, hardened-runtime distribution signing, notarization,
  and stapling.
- Intel or Universal 2 binaries.
- Mac App Store distribution.
- A `.pkg` installer, privileged helper, or administrator prompt.
- Automatic updates, release hosting, and remote publishing.
- Custom Finder backgrounds, custom volume icons, or decorative DMG layout.

## Git Integration

The packaging implementation will be committed on
`feature/quota-glance-phase-one`. After the DMG passes verification, the branch
will be merged locally into `main`. No remote is configured, so the workflow
will not push or create a pull request. The verified DMG and checksum are build
artifacts under `dist/` and are not committed to Git.
