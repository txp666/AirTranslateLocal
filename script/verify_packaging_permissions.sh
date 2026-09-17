#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-source}"
case "$MODE" in
  source|--release-artifacts) ;;
  *) echo "usage: $0 [--release-artifacts]" >&2; exit 2 ;;
esac
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=app_metadata.sh
source "$ROOT_DIR/script/app_metadata.sh"
ENTITLEMENTS_PATH="$ROOT_DIR/Resources/AirTranslate.entitlements"
DEBUG_ENTITLEMENTS_PATH="$ROOT_DIR/Resources/AirTranslate.debug.entitlements"
LOCAL_BUILD_SCRIPT="$ROOT_DIR/script/build_and_run.sh"
RELEASE_BUILD_SCRIPT="$ROOT_DIR/Release/build_open_source_release.sh"
PLIST_WRITER="$ROOT_DIR/script/write_info_plist.sh"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/airtranslate-packaging-permissions.XXXXXX")"
MOUNT_POINT=""
cleanup() {
  if [[ -n "$MOUNT_POINT" ]]; then
    /usr/bin/hdiutil detach "$MOUNT_POINT" >/dev/null 2>&1 || true
  fi
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

require_pattern() {
  if ! /usr/bin/grep -Fq -- "$1" "$2"; then
    echo "Missing packaging configuration in $2: $1" >&2
    exit 1
  fi
}
assert_entitlement_is_true() {
  local value
  value="$(/usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null || true)"
  if [[ "$value" != "true" ]]; then
    echo "$1 must set $2 to Boolean true." >&2
    exit 1
  fi
}
assert_entitlement_is_absent() {
  if /usr/libexec/PlistBuddy -c "Print :$2" "$1" >/dev/null 2>&1; then
    echo "$1 must not contain $2." >&2
    exit 1
  fi
}
write_embedded_entitlements() {
  /usr/bin/codesign -d --entitlements :- "$1" > "$2" 2>/dev/null
  /usr/bin/plutil -lint "$2" >/dev/null
}
assert_hardened_runtime() {
  /usr/bin/codesign -dvv "$1" > "$TEMP_DIR/codesign-details.txt" 2>&1
  if ! /usr/bin/grep -Eq 'flags=.*runtime' "$TEMP_DIR/codesign-details.txt"; then
    echo "Hardened Runtime missing: $1" >&2
    exit 1
  fi
}

assert_entitlement_is_true "$ENTITLEMENTS_PATH" com.apple.security.device.audio-input
assert_entitlement_is_absent "$ENTITLEMENTS_PATH" com.apple.security.get-task-allow
assert_entitlement_is_true "$DEBUG_ENTITLEMENTS_PATH" com.apple.security.device.audio-input
assert_entitlement_is_true "$DEBUG_ENTITLEMENTS_PATH" com.apple.security.get-task-allow
for signing_script in "$LOCAL_BUILD_SCRIPT" "$RELEASE_BUILD_SCRIPT"; do
  require_pattern '--options runtime' "$signing_script"
  require_pattern '--entitlements "$ENTITLEMENTS_PATH"' "$signing_script"
  require_pattern 'local_mlx_watchdog.py' "$signing_script"
  require_pattern 'setup_local_mlx.sh' "$signing_script"
done
require_pattern 'DEBUG_ENTITLEMENTS_PATH=' "$LOCAL_BUILD_SCRIPT"
require_pattern '--debug|debug)' "$LOCAL_BUILD_SCRIPT"
require_pattern 'ENTITLEMENTS_PATH="$DEBUG_ENTITLEMENTS_PATH"' "$LOCAL_BUILD_SCRIPT"
require_pattern 'tccutil reset Microphone "$BUNDLE_ID"' "$LOCAL_BUILD_SCRIPT"
if /usr/bin/grep -Fq 'AirTranslate.debug.entitlements' "$RELEASE_BUILD_SCRIPT"; then
  echo "Release signing must not use debug entitlements." >&2
  exit 1
fi

for plist_mode in local release; do
  plist_path="$TEMP_DIR/$plist_mode-Info.plist"
  "$PLIST_WRITER" "$plist_path" "$plist_mode"
  /usr/bin/plutil -lint "$plist_path" >/dev/null
  for key in NSMicrophoneUsageDescription NSSpeechRecognitionUsageDescription; do
    /usr/libexec/PlistBuddy -c "Print :$key" "$plist_path" >/dev/null
  done
  test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist_path")" = "$BUNDLE_ID"
done

TEST_APP="$TEMP_DIR/$APP_BUNDLE_NAME.app"
mkdir -p "$TEST_APP/Contents/MacOS"
/bin/cp "$TEMP_DIR/local-Info.plist" "$TEST_APP/Contents/Info.plist"
/bin/cp /usr/bin/true "$TEST_APP/Contents/MacOS/$APP_NAME"
for signing_mode in release debug; do
  signing_entitlements="$ENTITLEMENTS_PATH"
  [[ "$signing_mode" != debug ]] || signing_entitlements="$DEBUG_ENTITLEMENTS_PATH"
  /usr/bin/codesign --force --options runtime --entitlements "$signing_entitlements" --sign - "$TEST_APP"
  embedded="$TEMP_DIR/$signing_mode.entitlements"
  write_embedded_entitlements "$TEST_APP" "$embedded"
  assert_entitlement_is_true "$embedded" com.apple.security.device.audio-input
  if [[ "$signing_mode" == debug ]]; then
    assert_entitlement_is_true "$embedded" com.apple.security.get-task-allow
  else
    assert_entitlement_is_absent "$embedded" com.apple.security.get-task-allow
  fi
  assert_hardened_runtime "$TEST_APP"
done

echo "Packaging permission checks passed."
[[ "$MODE" == --release-artifacts ]] || exit 0

PRODUCT_DIR="$ROOT_DIR/Release/product"
APP_BUNDLE="$PRODUCT_DIR/$APP_BUNDLE_NAME.app"
ZIP_NAME="$ARTIFACT_NAME-$VERSION-$BUILD_NUMBER.zip"
DMG_NAME="$ARTIFACT_NAME.dmg"
assert_bundle() {
  local bundle="$1"
  local resources="$bundle/Contents/Resources"
  /usr/bin/codesign --verify --deep --strict "$bundle"
  assert_hardened_runtime "$bundle"
  write_embedded_entitlements "$bundle" "$TEMP_DIR/artifact.entitlements"
  assert_entitlement_is_true "$TEMP_DIR/artifact.entitlements" com.apple.security.device.audio-input
  assert_entitlement_is_absent "$TEMP_DIR/artifact.entitlements" com.apple.security.get-task-allow
  test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$bundle/Contents/Info.plist")" = "$BUNDLE_ID"
  test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$bundle/Contents/Info.plist")" = "$VERSION"
  test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$bundle/Contents/Info.plist")" = "$BUILD_NUMBER"
  for notice in LICENSE NOTICE; do
    cmp "$ROOT_DIR/$notice" "$resources/$notice"
  done
  for resource in AppIcon.icns local_mlx_watchdog.py setup_local_mlx.sh; do
    cmp "$ROOT_DIR/Resources/$resource" "$resources/$resource"
  done
  if /usr/bin/find "$bundle" -type f \( -name '.env' -o -name '.env.*' -o -name '*.p12' -o -name '*.key' -o -name '*.pem' -o -name '*.mobileprovision' -o -name '*.provisionprofile' -o -name '*.safetensors' \) -print | /usr/bin/grep -q .; then
    echo "Unexpected sensitive/model file in bundle: $bundle" >&2
    exit 1
  fi
  # Print only filenames: a failed secret scan must not leak the secret to CI logs.
  local secret_pattern='(sk-[A-Za-z0-9_-]{20,}|AIza[0-9A-Za-z_-]{35}|ghp_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,}|hf_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|-----BEGIN (RSA |OPENSSH |EC |DSA )?PRIVATE KEY-----)'
  local scan_status=0
  /usr/bin/grep -aERl "$secret_pattern" "$bundle" > "$TEMP_DIR/secret-paths.txt" || scan_status=$?
  if [[ "$scan_status" == 0 ]]; then
    echo "Credential pattern found in these files (values withheld):" >&2
    cat "$TEMP_DIR/secret-paths.txt" >&2
    exit 1
  elif [[ "$scan_status" != 1 ]]; then
    echo "Credential scanner failed with status $scan_status." >&2
    exit "$scan_status"
  fi
}
assert_bundle "$APP_BUNDLE"
(cd "$PRODUCT_DIR" && /usr/bin/shasum -a 256 -c "$ZIP_NAME.sha256" && /usr/bin/shasum -a 256 -c "$DMG_NAME.sha256")
mkdir -p "$TEMP_DIR/unpacked" "$TEMP_DIR/mount"
/usr/bin/ditto -x -k "$PRODUCT_DIR/$ZIP_NAME" "$TEMP_DIR/unpacked"
assert_bundle "$TEMP_DIR/unpacked/$APP_BUNDLE_NAME.app"
diff -rq "$APP_BUNDLE" "$TEMP_DIR/unpacked/$APP_BUNDLE_NAME.app"
/usr/bin/hdiutil verify "$PRODUCT_DIR/$DMG_NAME"
MOUNT_POINT="$TEMP_DIR/mount"
/usr/bin/hdiutil attach -readonly -nobrowse -mountpoint "$MOUNT_POINT" "$PRODUCT_DIR/$DMG_NAME"
assert_bundle "$MOUNT_POINT/$APP_BUNDLE_NAME.app"
test "$(readlink "$MOUNT_POINT/Applications")" = /Applications
diff -rq "$APP_BUNDLE" "$MOUNT_POINT/$APP_BUNDLE_NAME.app"
echo "Release bundle, ZIP, DMG, resource, entitlement, and checksum checks passed."
