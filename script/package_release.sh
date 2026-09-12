#!/usr/bin/env bash
set -euo pipefail

APP_NAME="LoeBalance"
BUNDLE_ID="cx.loe.LoeBalance"
MIN_SYSTEM_VERSION="13.0"
VERSION="${1:-0.1.0}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_ROOT="$ROOT_DIR/.build-release"
STAGING_ROOT="$ROOT_DIR/.release-staging"
OUTPUT_DIR="$ROOT_DIR/outputs"

write_info_plist() {
  local plist="$1"
  /usr/bin/plutil -convert xml1 -o "$plist" - <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$VERSION</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST
}

package_architecture() {
  local architecture="$1"
  local triple="$2"
  local scratch_path="$BUILD_ROOT/$architecture"
  local staging_path="$STAGING_ROOT/$architecture/$APP_NAME.app"
  local app_contents="$staging_path/Contents"
  local app_macos="$app_contents/MacOS"
  local binary
  local archive="$OUTPUT_DIR/${APP_NAME}-macOS-$architecture.zip"
  local checksum="$OUTPUT_DIR/${APP_NAME}-macOS-$architecture.sha256"
  local temporary_archive
  local temporary_checksum

  swift build --configuration release --triple "$triple" --scratch-path "$scratch_path"
  binary="$(swift build --configuration release --triple "$triple" --scratch-path "$scratch_path" --show-bin-path)/$APP_NAME"

  rm -rf "$staging_path"
  mkdir -p "$app_macos" "$app_contents/Resources"
  cp "$binary" "$app_macos/$APP_NAME"
  chmod +x "$app_macos/$APP_NAME"
  write_info_plist "$app_contents/Info.plist"
  codesign --force --deep --sign - "$staging_path"

  temporary_archive="$(mktemp "${TMPDIR:-/tmp}/$APP_NAME-$architecture.XXXXXX.zip")"
  temporary_checksum="$(mktemp "${TMPDIR:-/tmp}/$APP_NAME-$architecture.XXXXXX.sha256")"
  ditto -c -k --sequesterRsrc --keepParent "$staging_path" "$temporary_archive"
  shasum -a 256 "$temporary_archive" | awk -v name="$(basename "$archive")" '{print $1 "  " name}' > "$temporary_checksum"
  install -m 644 "$temporary_archive" "$archive"
  install -m 644 "$temporary_checksum" "$checksum"

  codesign --verify --deep --strict "$staging_path"
  file "$app_macos/$APP_NAME"
  (cd "$OUTPUT_DIR" && shasum -a 256 -c "$(basename "$checksum")")
  printf 'Created %s\n' "$archive"
}

mkdir -p "$OUTPUT_DIR"
package_architecture "x86_64" "x86_64-apple-macosx13.0"
package_architecture "arm64" "arm64-apple-macosx13.0"
