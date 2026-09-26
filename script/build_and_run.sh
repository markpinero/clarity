#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Clarity"
PREVIOUS_APP_NAME="IrisAlternative"
BUNDLE_ID="com.markpinero.Clarity"
PREVIOUS_BUNDLE_ID="com.markpinero.IrisAlternative"
MIN_SYSTEM_VERSION="13.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_CONFIGURATION="${CLARITY_BUILD_CONFIGURATION:-debug}"
CODESIGN_IDENTITY="${CLARITY_CODESIGN_IDENTITY:-}"
RELEASE_VERSION="${CLARITY_RELEASE_VERSION:-0.1.0-dev}"
DIST_DIR="${CLARITY_DIST_DIR:-$ROOT_DIR/dist}"

if [[ "$MODE" == "--release" || "$MODE" == "release" ]]; then
  BUILD_CONFIGURATION="release"
  RELEASE_VERSION="${CLARITY_RELEASE_VERSION:-0.1.0}"
  DIST_DIR="${CLARITY_DIST_DIR:-$ROOT_DIR/dist/release}"
  CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
else
  CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-Apple Development}"
  if [[ "$CODESIGN_IDENTITY" != Apple\ Development* ]]; then
    echo "Development bundles require an Apple Development signing identity." >&2
    exit 1
  fi
fi

APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
PREVIOUS_APP_BUNDLE="$DIST_DIR/$PREVIOUS_APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ENTITLEMENTS_PLIST="$ROOT_DIR/Clarity.entitlements"
ICON_FILE="$ROOT_DIR/Assets/Clarity.icns"
RELEASE_ARCHIVE="$DIST_DIR/$APP_NAME.zip"

if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

stop_running_app() {
  if ! pgrep -x "$APP_NAME" >/dev/null 2>&1 && ! pgrep -x "$PREVIOUS_APP_NAME" >/dev/null 2>&1; then
    return
  fi

  if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    /usr/bin/osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
  fi
  if pgrep -x "$PREVIOUS_APP_NAME" >/dev/null 2>&1; then
    /usr/bin/osascript -e "tell application id \"$PREVIOUS_BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
  fi
  for _ in {1..30}; do
    if ! pgrep -x "$APP_NAME" >/dev/null 2>&1 && ! pgrep -x "$PREVIOUS_APP_NAME" >/dev/null 2>&1; then
      return
    fi
    sleep 0.1
  done

  echo "$APP_NAME did not terminate cleanly. Use Reset in the app before retrying." >&2
  exit 1
}

stage_app_bundle() {
  swift build -c "$BUILD_CONFIGURATION" --product "$APP_NAME"
  local build_binary
  build_binary="$(swift build -c "$BUILD_CONFIGURATION" --show-bin-path)/$APP_NAME"

  if [[ ! -f "$ICON_FILE" ]]; then
    echo "Missing application icon: $ICON_FILE" >&2
    exit 1
  fi

  rm -rf "$APP_BUNDLE" "$PREVIOUS_APP_BUNDLE"
  mkdir -p "$APP_MACOS" "$APP_RESOURCES"
  cp "$build_binary" "$APP_BINARY"
  cp "$ICON_FILE" "$APP_RESOURCES/Clarity.icns"
  chmod +x "$APP_BINARY"

  cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>Clarity</string>
  <key>CFBundleShortVersionString</key>
  <string>$RELEASE_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$RELEASE_VERSION</string>
  <key>CFBundleIconFile</key>
  <string>Clarity.icns</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSMultipleInstancesProhibited</key>
  <true/>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSLocationUsageDescription</key>
  <string>Clarity uses a one-time coarse location to calculate local sunrise and sunset.</string>
  <key>NSLocationWhenInUseUsageDescription</key>
  <string>Clarity uses a one-time coarse location to calculate local sunrise and sunset.</string>
  <key>NSAppleEventsUsageDescription</key>
  <string>Clarity uses Apple Events for user-configured break automations and compatible application context.</string>
  <key>NSAppleScriptEnabled</key>
  <true/>
  <key>NSCalendarsFullAccessUsageDescription</key>
  <string>Clarity reads calendar events to pause screen breaks while meetings are in progress.</string>
  <key>NSCalendarsUsageDescription</key>
  <string>Clarity reads calendar events to pause screen breaks while meetings are in progress.</string>
  <key>NSCalendarsWriteOnlyAccessUsageDescription</key>
  <string>Clarity does not create calendar events; this description preserves compatibility with macOS calendar authorization.</string>
</dict>
</plist>
PLIST

  if [[ "$CODESIGN_IDENTITY" == "-" ]]; then
    /usr/bin/codesign \
      --force \
      --sign - \
      --requirements "=designated => identifier \"$BUNDLE_ID\"" \
      --entitlements "$ENTITLEMENTS_PLIST" \
      "$APP_BUNDLE" >/dev/null
  else
    /usr/bin/codesign \
      --force \
      --options runtime \
      --timestamp \
      --sign "$CODESIGN_IDENTITY" \
      --entitlements "$ENTITLEMENTS_PLIST" \
      "$APP_BUNDLE" >/dev/null
  fi

  /usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"
  if [[ "$MODE" != "--release" && "$MODE" != "release" ]]; then
    local signing_authority
    signing_authority="$(/usr/bin/codesign -dv --verbose=4 "$APP_BUNDLE" 2>&1 | /usr/bin/sed -n 's/^Authority=//p' | /usr/bin/head -1)"
    if [[ "$signing_authority" != Apple\ Development:* ]]; then
      echo "Development bundle was not signed by an Apple Development certificate." >&2
      exit 1
    fi
  fi
}

package_release() {
  rm -f "$RELEASE_ARCHIVE"
  /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$RELEASE_ARCHIVE"
}

open_app() {
  /usr/bin/open "$APP_BUNDLE"
}

if [[ "$MODE" == "--stage" || "$MODE" == "stage" ]]; then
  stage_app_bundle
  exit 0
fi

if [[ "$MODE" == "--release" || "$MODE" == "release" ]]; then
  stage_app_bundle
  package_release
  echo "Release archive: $RELEASE_ARCHIVE"
  exit 0
fi

stop_running_app
stage_app_bundle

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
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
    for _ in {1..30}; do
      if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
        exit 0
      fi
      sleep 0.1
    done
    echo "$APP_NAME did not launch." >&2
    exit 1
    ;;
  *)
    echo "usage: $0 [run|--stage|--release|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
