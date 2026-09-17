#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="$ROOT_DIR/script"
# shellcheck source=app_metadata.sh
source "$SCRIPT_DIR/app_metadata.sh"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_BUNDLE_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ENTITLEMENTS_PATH="$ROOT_DIR/Resources/AirTranslate.entitlements"
DEBUG_ENTITLEMENTS_PATH="$ROOT_DIR/Resources/AirTranslate.debug.entitlements"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-}"
LOCAL_DESIGNATED_REQUIREMENT="=designated => identifier \"$BUNDLE_ID\" and info[CFBundleName] = \"$DISPLAY_NAME\""

case "$MODE" in
  --build|build|run|--logs|logs|--telemetry|telemetry|--verify|verify) ;;
  --debug|debug) ENTITLEMENTS_PATH="$DEBUG_ENTITLEMENTS_PATH" ;;
  --reset-permissions|reset-permissions)
    /usr/bin/tccutil reset ScreenCapture "$BUNDLE_ID" || true
    /usr/bin/tccutil reset AudioCapture "$BUNDLE_ID" || true
    /usr/bin/tccutil reset Microphone "$BUNDLE_ID" || true
    /usr/bin/tccutil reset SpeechRecognition "$BUNDLE_ID" || true
    echo "Relaunch and approve Screen Recording, System Audio Recording, Microphone (when selected), and Speech Recognition."
    exit 0
    ;;
  --help|-h)
    echo "usage: $0 [run|--build|--debug|--logs|--telemetry|--verify|--reset-permissions]"
    exit 0
    ;;
  *)
    echo "usage: $0 [run|--build|--debug|--logs|--telemetry|--verify|--reset-permissions]" >&2
    exit 2
    ;;
esac

cd "$ROOT_DIR"
swift build
BUILD_BINARY="$(swift build --show-bin-path)/$APP_NAME"

# A sibling upstream app may use the same executable name. Only stop this
# checkout's exact bundle when replacing/relaunching a running development app.
if [[ "$MODE" != --build && "$MODE" != build ]]; then
  while read -r process_id process_path; do
    if [[ "$process_path" == "$APP_BINARY" ]]; then
      kill -TERM "$process_id" 2>/dev/null || true
    fi
  done < <(/bin/ps -axo pid=,comm=)
fi

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
install -m 755 "$BUILD_BINARY" "$APP_BINARY"
for resource in AppIcon.icns local_mlx_watchdog.py setup_local_mlx.sh; do
  install -m 644 "$ROOT_DIR/Resources/$resource" "$APP_RESOURCES/$resource"
done
install -m 644 "$ROOT_DIR/LICENSE" "$APP_RESOURCES/LICENSE"
install -m 644 "$ROOT_DIR/NOTICE" "$APP_RESOURCES/NOTICE"
"$SCRIPT_DIR/write_info_plist.sh" "$INFO_PLIST" local

select_code_sign_identity() {
  if [[ -n "$CODE_SIGN_IDENTITY" ]]; then
    printf '%s\n' "$CODE_SIGN_IDENTITY"
    return
  fi
  /usr/bin/security find-identity -v -p codesigning 2>/dev/null |
    /usr/bin/awk -F'"' '/"Apple Development:|Developer ID Application:|Mac Developer:/{ print $2; exit }'
}

SIGN_IDENTITY="$(select_code_sign_identity)"
if [[ -n "$SIGN_IDENTITY" ]]; then
  /usr/bin/codesign --force --deep --options runtime --entitlements "$ENTITLEMENTS_PATH" --timestamp=none --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
else
  /usr/bin/codesign --force --deep --options runtime --entitlements "$ENTITLEMENTS_PATH" --requirements "$LOCAL_DESIGNATED_REQUIREMENT" --sign - "$APP_BUNDLE"
  echo "Using a stable local designated requirement for macOS privacy grants."
fi
/usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"
echo "Built: $APP_BUNDLE"

open_app() { /usr/bin/open -n "$APP_BUNDLE"; }
case "$MODE" in
  --build|build) ;;
  run) open_app ;;
  --debug|debug) lldb -- "$APP_BINARY" ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    /bin/ps -axo comm= | /usr/bin/grep -Fxq "$APP_BINARY"
    ;;
esac
