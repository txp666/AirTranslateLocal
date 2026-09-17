#!/usr/bin/env bash
set -euo pipefail

INFO_PLIST="${1:?usage: write_info_plist.sh <Info.plist> <local|release>}"
PLIST_MODE="${2:?usage: write_info_plist.sh <Info.plist> <local|release>}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=app_metadata.sh
source "$SCRIPT_DIR/app_metadata.sh"

if [[ "$PLIST_MODE" != "local" && "$PLIST_MODE" != "release" ]]; then
  echo "usage: write_info_plist.sh <Info.plist> <local|release>" >&2
  exit 2
fi

# plutil escapes names supplied by downstream distributors correctly.
/usr/bin/plutil -create xml1 "$INFO_PLIST"
for entry in \
  "CFBundleDevelopmentRegion=en" \
  "CFBundleDisplayName=$DISPLAY_NAME" \
  "CFBundleExecutable=$APP_NAME" \
  "CFBundleIconFile=AppIcon" \
  "CFBundleIdentifier=$BUNDLE_ID" \
  "CFBundleInfoDictionaryVersion=6.0" \
  "CFBundleName=$DISPLAY_NAME" \
  "CFBundlePackageType=APPL" \
  "CFBundleShortVersionString=$VERSION" \
  "CFBundleVersion=$BUILD_NUMBER" \
  "LSMinimumSystemVersion=$MIN_SYSTEM_VERSION" \
  "NSPrincipalClass=NSApplication" \
  "NSMicrophoneUsageDescription=$DISPLAY_NAME uses microphone audio only when you select Microphone and start translation." \
  "NSSpeechRecognitionUsageDescription=$DISPLAY_NAME uses Apple Speech to recognize captured audio for local translation and live captions."; do
  /usr/bin/plutil -insert "${entry%%=*}" -string "${entry#*=}" "$INFO_PLIST"
done
/usr/bin/plutil -insert NSAppTransportSecurity -dictionary "$INFO_PLIST"
/usr/bin/plutil -insert NSAppTransportSecurity.NSAllowsLocalNetworking -bool true "$INFO_PLIST"

if [[ "$PLIST_MODE" == "release" ]]; then
  /usr/bin/plutil -insert CFBundleSupportedPlatforms -json '["MacOSX"]' "$INFO_PLIST"
  /usr/bin/plutil -insert LSApplicationCategoryType -string "$CATEGORY" "$INFO_PLIST"
  /usr/bin/plutil -insert NSAudioCaptureUsageDescription -string "$DISPLAY_NAME captures system audio only after you start translation." "$INFO_PLIST"
  /usr/bin/plutil -insert NSHumanReadableCopyright -string "$COPYRIGHT_TEXT" "$INFO_PLIST"
  /usr/bin/plutil -insert NSHighResolutionCapable -bool true "$INFO_PLIST"
else
  /usr/bin/plutil -insert NSSystemAudioCaptureUsageDescription -string "$DISPLAY_NAME captures system audio only after you start translation." "$INFO_PLIST"
fi
