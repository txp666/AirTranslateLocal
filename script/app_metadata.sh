#!/usr/bin/env bash

# Keep the executable target and existing local permission identity stable.
APP_NAME="${APP_NAME:-AirTranslate}"
DISPLAY_NAME="${DISPLAY_NAME:-AirTranslate Local}"
APP_BUNDLE_NAME="${APP_BUNDLE_NAME:-$DISPLAY_NAME}"
ARTIFACT_NAME="${ARTIFACT_NAME:-AirTranslate-Local}"
BUNDLE_ID="${BUNDLE_ID:-com.txp.AirTranslateLocal}"
VERSION="${VERSION:-2.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-200}"
MIN_SYSTEM_VERSION="${MIN_SYSTEM_VERSION:-26.0}"
CATEGORY="${CATEGORY:-public.app-category.productivity}"
COPYRIGHT_TEXT="${COPYRIGHT_TEXT:-Copyright © 2026 himomohi and AirTranslate Local contributors.}"

# These values become path components in generated output. Do not let an
# override redirect artifact replacement outside the output directories.
for metadata_component in APP_NAME APP_BUNDLE_NAME ARTIFACT_NAME VERSION BUILD_NUMBER; do
  case "${!metadata_component}" in
    ''|.|..|*/*|*$'\n'*|*$'\r'*)
      printf 'Invalid filename component in %s.\n' "$metadata_component" >&2
      return 2 2>/dev/null || exit 2
      ;;
  esac
done
unset metadata_component
