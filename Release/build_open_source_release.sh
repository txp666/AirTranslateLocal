#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-zip}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="$ROOT_DIR/script"
# shellcheck source=app_metadata.sh
source "$SCRIPT_DIR/app_metadata.sh"
RELEASE_DIR="$ROOT_DIR/Release"
BUILD_DIR="$RELEASE_DIR/build"
PRODUCT_DIR="$RELEASE_DIR/product"
APP_BUNDLE="$PRODUCT_DIR/$APP_BUNDLE_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ENTITLEMENTS_PATH="$ROOT_DIR/Resources/AirTranslate.entitlements"
ZIP_PATH="$PRODUCT_DIR/$ARTIFACT_NAME-$VERSION-$BUILD_NUMBER.zip"
DMG_STAGING_DIR="$BUILD_DIR/dmg"
DMG_PATH="$PRODUCT_DIR/$ARTIFACT_NAME.dmg"

usage() {
  cat <<EOF
usage: $0 [zip|dmg|all]

Build local app/ZIP/DMG artifacts. No upload or release publication is performed.
Optional: DISPLAY_NAME, APP_BUNDLE_NAME, ARTIFACT_NAME, BUNDLE_ID,
          VERSION, BUILD_NUMBER, MIN_SYSTEM_VERSION, SIGNING_IDENTITY
EOF
}
case "$MODE" in
  zip|dmg|all) ;;
  --help|-h|help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"

cd "$ROOT_DIR"
# Fail before clearing old artifacts if a required packaging resource is absent.
for resource in AppIcon.icns local_mlx_watchdog.py setup_local_mlx.sh; do
  test -f "$ROOT_DIR/Resources/$resource"
done
swift build -c release
BUILD_BINARY="$(swift build -c release --show-bin-path)/$APP_NAME"
# Only replace this build's own bundle/staging tree; preserve other artifacts
# and any unrelated files a distributor keeps in the generated directories.
rm -rf "$APP_BUNDLE" "$DMG_STAGING_DIR"
mkdir -p "$BUILD_DIR" "$APP_MACOS" "$APP_RESOURCES"
install -m 755 "$BUILD_BINARY" "$APP_BINARY"
for resource in AppIcon.icns local_mlx_watchdog.py setup_local_mlx.sh; do
  install -m 644 "$ROOT_DIR/Resources/$resource" "$APP_RESOURCES/$resource"
done
install -m 644 "$ROOT_DIR/LICENSE" "$APP_RESOURCES/LICENSE"
install -m 644 "$ROOT_DIR/NOTICE" "$APP_RESOURCES/NOTICE"
"$SCRIPT_DIR/write_info_plist.sh" "$INFO_PLIST" release
/usr/bin/plutil -lint "$INFO_PLIST"

CODESIGN_ARGS=(--force --deep --strict --options runtime --entitlements "$ENTITLEMENTS_PATH" --sign "$SIGNING_IDENTITY")
if [[ "$SIGNING_IDENTITY" == "-" ]]; then
  CODESIGN_ARGS+=(--timestamp=none)
fi
/usr/bin/codesign "${CODESIGN_ARGS[@]}" "$APP_BUNDLE"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

write_checksum() {
  local artifact_path="$1"
  (cd "$PRODUCT_DIR" && /usr/bin/shasum -a 256 "$(basename "$artifact_path")" > "$(basename "$artifact_path").sha256")
}
if [[ "$MODE" == "zip" || "$MODE" == "all" ]]; then
  rm -f "$ZIP_PATH" "$ZIP_PATH.sha256"
  /usr/bin/ditto -c -k --norsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"
  write_checksum "$ZIP_PATH"
fi
if [[ "$MODE" == "dmg" || "$MODE" == "all" ]]; then
  mkdir -p "$DMG_STAGING_DIR"
  /usr/bin/ditto "$APP_BUNDLE" "$DMG_STAGING_DIR/$APP_BUNDLE_NAME.app"
  ln -s /Applications "$DMG_STAGING_DIR/Applications"
  /usr/bin/hdiutil create -volname "$DISPLAY_NAME $VERSION" -srcfolder "$DMG_STAGING_DIR" -ov -format UDZO "$DMG_PATH"
  write_checksum "$DMG_PATH"
fi

echo "Built local release bundle: $APP_BUNDLE"
[[ "$MODE" == "dmg" ]] || echo "ZIP: $ZIP_PATH"
[[ "$MODE" == "zip" ]] || echo "DMG: $DMG_PATH"
