# Build local release artifacts

These scripts package AirTranslate Local from this checkout. They do not create a GitHub release or publish to the original author's repository. Configure your own repository before any separate publication step.

## Build

On an Apple Silicon Mac with macOS 26+ and Swift 6.2+:

```bash
swift test
./script/verify_packaging_permissions.sh
./Release/build_open_source_release.sh all
./script/verify_packaging_permissions.sh --release-artifacts
```

Use `zip` or `dmg` instead of `all` for one archive format. Outputs use the metadata in `script/app_metadata.sh`:

```text
Release/product/AirTranslate Local.app
Release/product/AirTranslate-Local-<version>-<build>.zip
Release/product/AirTranslate-Local-<version>-<build>.zip.sha256
Release/product/AirTranslate-Local.dmg
Release/product/AirTranslate-Local.dmg.sha256
```

The bundle includes `LICENSE`, `NOTICE`, the local runtime setup script, and the process watchdog. It does not include model weights, Python, virtual environments, or user settings. A fresh machine still needs the [one-time runtime/model setup](../docs/local-mlx.md).

## Identity and signing

The executable target remains `AirTranslate`. The display/bundle name defaults to `AirTranslate Local`, with bundle ID `com.txp.AirTranslateLocal` for existing local permission compatibility. Set environment variables to identify your own distribution:

```bash
DISPLAY_NAME="My Local Captions" \
APP_BUNDLE_NAME="My Local Captions" \
ARTIFACT_NAME="My-Local-Captions" \
BUNDLE_ID="com.example.LocalCaptions" \
VERSION="0.1.0" BUILD_NUMBER="1" \
./Release/build_open_source_release.sh all
```

No signing secret is needed for ad-hoc local packages. To sign with an installed identity, set `SIGNING_IDENTITY` for release builds or `CODE_SIGN_IDENTITY` for development builds. Never add a certificate private key or password to this repository.

Ad-hoc packages are not notarized and may be blocked by macOS Gatekeeper. Use macOS's per-app **Open Anyway** path only for a build whose origin you trust. The scripts do not disable system security or remove quarantine recursively. Developer ID notarization is a separate distributor-controlled step.

## What CI verifies

The workflow runs Swift tests, permission checks, shell/Python syntax checks, a release build, and ZIP/DMG integrity checks. It reads versions from the metadata script, checks bundled resources and hashes, and uploads artifacts to that workflow run. It has read-only repository permissions and no release publication step. It neither downloads the model nor claims to test live capture on a hosted runner.

Before distributing, also test the installed app with real audio, Apple Speech assets, and a cached model on a fresh user profile. Confirm that Start/Stop, both audio inputs, floating captions, and app-owned model shutdown work. Keep the original Apache license/NOTICE and include accurate dependency/installation instructions.
