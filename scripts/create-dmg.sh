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
  set +e

  if [[ -n "${MOUNT_DEVICE:-}" ]]; then
    hdiutil detach "$MOUNT_DEVICE" -force >/dev/null 2>&1 || true
  fi

  if [[ -n "${MOUNT_POINT:-}" && -d "$MOUNT_POINT" ]]; then
    hdiutil detach "$MOUNT_POINT" -force >/dev/null 2>&1 || true
    diskutil unmount force "$MOUNT_POINT" >/dev/null 2>&1 || true
  fi

  if [[ -n "${MOUNT_ROOT:-}" && -d "$MOUNT_ROOT" ]]; then
    while IFS= read -r mounted_dir; do
      [[ -z "$mounted_dir" ]] && continue
      hdiutil detach "$mounted_dir" -force >/dev/null 2>&1 || true
      diskutil unmount force "$mounted_dir" >/dev/null 2>&1 || true
    done < <(find "$MOUNT_ROOT" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
  fi

  rm -rf "$TMP_ROOT" >/dev/null 2>&1 || true
}
trap cleanup EXIT

mkdir -p "$OUTPUT_DIR" "$STAGING_DIR" "$BACKGROUND_DIR" "$MOUNT_ROOT"
cp -R "$APP_PATH" "$STAGING_DIR/$APP_BUNDLE_NAME"
ln -s /Applications "$STAGING_DIR/Applications"

cat >"$README_PATH" <<EOF
SmartX-${VERSION_TAG}.unsigned.dmg is an unsigned, non-notarized CI artifact. Drag ${APP_BUNDLE_NAME} to Applications for manual testing. Privileged helper behavior may not work in unsigned builds. This is not a release build.
EOF

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

("→" as NSString).draw(
    in: NSRect(x: 290, y: 165, width: 60, height: 60),
    withAttributes: arrowAttributes
)

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

chflags hidden "$MOUNT_POINT/.background" || true

ATTACH_PLIST="$TMP_ROOT/attach.plist"
ATTACH_LOG="$TMP_ROOT/attach.log"

if ! hdiutil attach \
  -plist \
  -readwrite \
  -noverify \
  -noautoopen \
  -mountroot "$MOUNT_ROOT" \
  "$RW_DMG_PATH" >"$ATTACH_PLIST" 2>"$ATTACH_LOG"; then
  echo "hdiutil attach failed." >&2
  cat "$ATTACH_LOG" >&2 || true
  exit 1
fi

read -r MOUNT_DEVICE MOUNT_POINT < <(
  python3 - "$ATTACH_PLIST" <<'PY'
import plistlib
import sys

plist_path = sys.argv[1]

with open(plist_path, "rb") as handle:
    data = plistlib.load(handle)

device = ""
mount_point = ""

for entity in data.get("system-entities", []):
    candidate_device = entity.get("dev-entry", "")
    candidate_mount = entity.get("mount-point", "")

    if candidate_device and not device:
        device = candidate_device

    if candidate_mount:
        mount_point = candidate_mount
        if candidate_device:
            device = candidate_device
        break

print(device, mount_point)
PY
)

if [[ -z "$MOUNT_DEVICE" || -z "$MOUNT_POINT" || ! -d "$MOUNT_POINT" ]]; then
  echo "Failed to discover mounted DMG device or mount point." >&2
  echo "Attach stderr:" >&2
  cat "$ATTACH_LOG" >&2 || true
  echo "Attach plist:" >&2
  cat "$ATTACH_PLIST" >&2 || true
  echo "Mount root contents:" >&2
  find "$MOUNT_ROOT" -mindepth 1 -maxdepth 2 -print >&2 || true
  exit 1
fi

echo "Mounted DMG device: $MOUNT_DEVICE"
echo "Mounted DMG path: $MOUNT_POINT"

chflags hidden "$MOUNT_POINT/.background" || true
rm -rf "$MOUNT_POINT/.fseventsd" "$MOUNT_POINT/.Trashes" "$MOUNT_POINT/.Spotlight-V100" 2>/dev/null || true

APPLESCRIPT_PATH="$TMP_ROOT/layout_dmg.applescript"
APPLESCRIPT_LOG="$TMP_ROOT/applescript.log"

cat >"$APPLESCRIPT_PATH" <<'APPLESCRIPT'
on run argv
  set mountPoint to item 1 of argv
  set appBundleName to item 2 of argv
  set backgroundPath to item 3 of argv

  set mountAlias to POSIX file mountPoint as alias
  set backgroundAlias to POSIX file backgroundPath as alias

  tell application "Finder"
    activate
    open mountAlias
    delay 1

    set containerWindow to window 1
    set current view of containerWindow to icon view
    set toolbar visible of containerWindow to false
    set statusbar visible of containerWindow to false
    set bounds of containerWindow to {100, 100, 740, 520}

    set viewOptions to the icon view options of containerWindow
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 96
    set text size of viewOptions to 14
    set background picture of viewOptions to backgroundAlias

    set position of item appBundleName of containerWindow to {180, 215}
    set position of item "Applications" of containerWindow to {460, 215}

    update without registering applications
    delay 2
    close containerWindow
  end tell
end run
APPLESCRIPT

if osascript "$APPLESCRIPT_PATH" \
  "$MOUNT_POINT" \
  "$APP_BUNDLE_NAME" \
  "$MOUNT_POINT/.background/background.png" \
  >"$APPLESCRIPT_LOG" 2>&1; then
  echo "Finder DMG layout applied."
else
  echo "Warning: Finder DMG layout AppleScript failed; continuing with clean fallback DMG." >&2
  cat "$APPLESCRIPT_LOG" >&2 || true
fi
rm -rf "$MOUNT_POINT/.fseventsd" "$MOUNT_POINT/.Trashes" "$MOUNT_POINT/.Spotlight-V100" 2>/dev/null || true

if [[ ! -f "$MOUNT_POINT/.DS_Store" ]]; then
  echo "Finder did not create .DS_Store; DMG layout cannot be guaranteed." >&2
  echo "AppleScript output:" >&2
  cat "$APPLESCRIPT_LOG" >&2 || true
  exit 1
fi

sync
sleep 1

hdiutil detach "$MOUNT_DEVICE" >/dev/null
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
