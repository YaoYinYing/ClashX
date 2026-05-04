#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/create-dmg.sh --app-path <path> --version-tag <version> --output-dir <dir>

Required:
  --app-path <path>      Path to the built .app bundle
  --version-tag <tag>    User-facing version tag, e.g. v1.2.3+abcdef12
  --output-dir <dir>     Output directory for DMG artifacts
EOF
}

APP_PATH="${APP_PATH:-}"
VERSION_TAG="${VERSION_TAG:-}"
OUTPUT_DIR="${OUTPUT_DIR:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app-path)
      APP_PATH="$2"
      shift 2
      ;;
    --version-tag)
      VERSION_TAG="$2"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$APP_PATH" || -z "$VERSION_TAG" || -z "$OUTPUT_DIR" ]]; then
  usage >&2
  exit 1
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle does not exist: $APP_PATH" >&2
  exit 1
fi

APP_BUNDLE_NAME="$(basename "$APP_PATH")"
DMG_BASENAME="SmartX-${VERSION_TAG}.unsigned"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/smartx-dmg.XXXXXX")"
STAGING_DIR="$TMP_ROOT/staging"
BACKGROUND_DIR="$STAGING_DIR/.background"
BACKGROUND_PATH="$BACKGROUND_DIR/background.png"
RW_DMG_PATH="$TMP_ROOT/${DMG_BASENAME}.rw.dmg"
MOUNT_ROOT="$TMP_ROOT/mnt"
README_PATH="$OUTPUT_DIR/README.txt"
FINAL_DMG_PATH="$OUTPUT_DIR/${DMG_BASENAME}.dmg"
SHA_PATH="$OUTPUT_DIR/${DMG_BASENAME}.dmg.sha256"
MOUNT_DEVICE=""
MOUNT_POINT=""

cleanup() {
  if [[ -n "$MOUNT_DEVICE" ]]; then
    hdiutil detach "$MOUNT_DEVICE" -force >/dev/null 2>&1 || true
  fi
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

mkdir -p "$OUTPUT_DIR" "$STAGING_DIR" "$BACKGROUND_DIR" "$MOUNT_ROOT"
cp -R "$APP_PATH" "$STAGING_DIR/$APP_BUNDLE_NAME"
ln -s /Applications "$STAGING_DIR/Applications"

cat >"$README_PATH" <<EOF
SmartX-${VERSION_TAG}.unsigned.dmg is an unsigned, non-notarized CI artifact. Drag ${APP_BUNDLE_NAME} to Applications for manual testing. Privileged helper behavior may not work in unsigned builds. This is not a release build.
EOF
cp "$README_PATH" "$STAGING_DIR/README.txt"

BACKGROUND_SWIFT="$TMP_ROOT/generate_dmg_background.swift"
SWIFT_MODULE_CACHE="$TMP_ROOT/swift-module-cache"
cat >"$BACKGROUND_SWIFT" <<'EOF'
import AppKit
import Foundation

let args = CommandLine.arguments
guard args.count == 4 else {
    fputs("usage: swift generate_dmg_background.swift <output-path> <app-path> <bundle-name>\n", stderr)
    exit(1)
}

let outputPath = args[1]
let appPath = args[2]
let bundleName = args[3]
let size = NSSize(width: 640, height: 420)
let image = NSImage(size: size)

image.lockFocus()
let rect = NSRect(origin: .zero, size: size)
NSColor(calibratedRed: 0.96, green: 0.98, blue: 1.0, alpha: 1.0).setFill()
rect.fill()

if let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.91, green: 0.95, blue: 1.0, alpha: 1.0),
    NSColor(calibratedRed: 0.98, green: 0.99, blue: 1.0, alpha: 1.0)
]) {
    gradient.draw(in: rect, angle: 90)
}

let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center

let titleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.boldSystemFont(ofSize: 30),
    .foregroundColor: NSColor(calibratedRed: 0.12, green: 0.16, blue: 0.25, alpha: 1.0),
    .paragraphStyle: paragraph
]
let subtitleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 15, weight: .medium),
    .foregroundColor: NSColor(calibratedRed: 0.26, green: 0.31, blue: 0.39, alpha: 1.0),
    .paragraphStyle: paragraph
]
let arrowAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 56, weight: .bold),
    .foregroundColor: NSColor(calibratedRed: 0.26, green: 0.40, blue: 0.62, alpha: 1.0)
]

("Drag SmartX to Applications" as NSString).draw(in: NSRect(x: 70, y: 335, width: 500, height: 40), withAttributes: titleAttributes)
("Unsigned CI artifact for manual testing" as NSString).draw(in: NSRect(x: 90, y: 302, width: 460, height: 24), withAttributes: subtitleAttributes)

let workspace = NSWorkspace.shared
let appIcon = workspace.icon(forFile: appPath)
let applicationsIcon = workspace.icon(forFile: "/Applications")
appIcon.size = NSSize(width: 96, height: 96)
applicationsIcon.size = NSSize(width: 96, height: 96)

let appIconRect = NSRect(x: 120, y: 145, width: 96, height: 96)
let appsIconRect = NSRect(x: 424, y: 145, width: 96, height: 96)
appIcon.draw(in: appIconRect)
applicationsIcon.draw(in: appsIconRect)
("→" as NSString).draw(in: NSRect(x: 290, y: 158, width: 60, height: 60), withAttributes: arrowAttributes)

(bundleName as NSString).draw(in: NSRect(x: 70, y: 110, width: 200, height: 24), withAttributes: subtitleAttributes)
("Applications" as NSString).draw(in: NSRect(x: 390, y: 110, width: 160, height: 24), withAttributes: subtitleAttributes)

let footerAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 12),
    .foregroundColor: NSColor(calibratedRed: 0.38, green: 0.43, blue: 0.49, alpha: 1.0),
    .paragraphStyle: paragraph
]
("Unsigned and non-notarized. Helper behavior may be limited." as NSString).draw(in: NSRect(x: 80, y: 36, width: 480, height: 20), withAttributes: footerAttributes)

image.unlockFocus()

guard let tiffData = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiffData),
      let pngData = rep.representation(using: .png, properties: [:]) else {
    fputs("failed to render DMG background PNG\n", stderr)
    exit(1)
}

do {
    try pngData.write(to: URL(fileURLWithPath: outputPath))
} catch {
    fputs("failed to write DMG background PNG: \(error)\n", stderr)
    exit(1)
}
EOF
mkdir -p "$SWIFT_MODULE_CACHE"
swift -module-cache-path "$SWIFT_MODULE_CACHE" "$BACKGROUND_SWIFT" "$BACKGROUND_PATH" "$APP_PATH" "$APP_BUNDLE_NAME"

hdiutil create \
  -quiet \
  -srcfolder "$STAGING_DIR" \
  -volname "SmartX ${VERSION_TAG}" \
  -fs HFS+ \
  -format UDRW \
  "$RW_DMG_PATH"

ATTACH_OUTPUT="$TMP_ROOT/attach.log"
hdiutil attach \
  -quiet \
  -readwrite \
  -noverify \
  -noautoopen \
  -mountroot "$MOUNT_ROOT" \
  "$RW_DMG_PATH" >"$ATTACH_OUTPUT"

MOUNT_DEVICE="$(awk '/^\/dev\// {print $1; exit}' "$ATTACH_OUTPUT")"
MOUNT_POINT="$(awk '/^\/dev\// {print substr($0, index($0,$3)); exit}' "$ATTACH_OUTPUT")"
if [[ -z "$MOUNT_DEVICE" || -z "$MOUNT_POINT" ]]; then
  echo "Failed to discover mounted DMG device or mount point." >&2
  exit 1
fi

osascript <<EOF >/dev/null 2>&1 || true
tell application "Finder"
  tell disk "SmartX ${VERSION_TAG}"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {100, 100, 740, 520}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 96
    set text size of opts to 14
    set background picture of opts to file ".background:background.png"
    set position of item "${APP_BUNDLE_NAME}" of container window to {160, 180}
    set position of item "Applications" of container window to {440, 180}
    set position of item "README.txt" of container window to {300, 310}
    update without registering applications
    delay 2
    close
  end tell
end tell
EOF

sync
hdiutil detach -quiet "$MOUNT_DEVICE"
MOUNT_DEVICE=""
MOUNT_POINT=""

hdiutil convert \
  -quiet \
  "$RW_DMG_PATH" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "$FINAL_DMG_PATH"

shasum -a 256 "$FINAL_DMG_PATH" >"$SHA_PATH"

echo "Created DMG: $FINAL_DMG_PATH"
echo "Created SHA256: $SHA_PATH"
