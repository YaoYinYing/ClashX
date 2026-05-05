#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="$ROOT_DIR/.codex-logs"
LOG_FILE="$LOG_DIR/xcodebuild-debug.log"
WORKSPACE_HELPER="$ROOT_DIR/scripts/ensure-xcworkspace.sh"
DERIVED_DATA_PATH="$LOG_DIR/derivedData-debug"
EXPECTED_APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug/SmartX.app"

cd "$ROOT_DIR"
mkdir -p "$LOG_DIR"
: > "$LOG_FILE"
rm -rf "$DERIVED_DATA_PATH"

workspace_error_is_inconclusive() {
  grep -Eq \
    "local xcodebuild resolution was blocked by simulator or cache environment issues|CoreSimulatorService connection became invalid|simdiskimaged|Operation not permitted|unable to load standard library|ModuleCache|ManifestLoading/.*\\.dia" \
    "$LOG_FILE"
}

workspace_ready=0
if bash "$WORKSPACE_HELPER" >> "$LOG_FILE" 2>&1; then
  workspace_ready=1
else
  if SMARTX_ENSURE_WORKSPACE_REPAIR=1 bash "$WORKSPACE_HELPER" >> "$LOG_FILE" 2>&1; then
    workspace_ready=1
  fi
fi

if [ "$workspace_ready" -ne 1 ]; then
  if workspace_error_is_inconclusive; then
    echo "BUILD INCONCLUSIVE"
  else
    echo "BUILD FAILED"
  fi
  echo "Full log: .codex-logs/xcodebuild-debug.log"
  echo "Expected app: $EXPECTED_APP_PATH"
  if workspace_error_is_inconclusive; then
    echo "Reason: Local xcodebuild resolution was blocked by simulator or cache environment issues."
    echo "Suggested direct fallback:"
    echo "  CLANG_MODULE_CACHE_PATH=/private/tmp/swift-module-cache SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/swiftpm-module-cache xcodebuild -workspace \"$PWD/ClashX.xcworkspace\" -scheme ClashX -configuration Debug -destination 'platform=macOS' -derivedDataPath \"$DERIVED_DATA_PATH\" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build"
    exit 2
  fi
  echo "Reason: Workspace is not ready for xcodebuild."
  echo "Suggested repair:"
  echo "  bundle install"
  echo "  bundle exec pod install"
  echo "  xcodebuild -list -workspace \"$PWD/ClashX.xcworkspace\""
  echo "If the workspace is still broken, run:"
  echo "  SMARTX_REGENERATE_WORKSPACE=1 bash scripts/ensure-xcworkspace.sh"
  exit 1
fi

set +e
xcodebuild \
  -workspace "$ROOT_DIR/ClashX.xcworkspace" \
  -scheme ClashX \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  -quiet \
  build \
  > "$LOG_FILE" 2>&1
status=$?
set -e

if [ "$status" -eq 0 ]; then
  if [ ! -d "$EXPECTED_APP_PATH" ]; then
    echo "BUILD FAILED"
    echo "Full log: .codex-logs/xcodebuild-debug.log"
    echo "Expected app: $EXPECTED_APP_PATH"
    echo "Reason: xcodebuild completed without producing SmartX.app."
    exit 1
  fi
  echo "BUILD SUCCEEDED"
  echo "Full log: .codex-logs/xcodebuild-debug.log"
  echo "Expected app: $EXPECTED_APP_PATH"
  exit 0
fi

if workspace_error_is_inconclusive; then
  echo "BUILD INCONCLUSIVE"
  echo "Full log: .codex-logs/xcodebuild-debug.log"
  echo "Expected app: $EXPECTED_APP_PATH"
  echo "Reason: Local xcodebuild failed under simulator or cache environment restrictions."
  exit 2
fi

echo "BUILD FAILED"
echo "Full log: .codex-logs/xcodebuild-debug.log"
echo "Expected app: $EXPECTED_APP_PATH"
echo
echo "Relevant diagnostics:"
grep -E "error:|warning:|fatal error|Undefined symbols|duplicate symbol|No such file|Command SwiftCompile failed|Command CompileSwiftSources failed|Ld " "$LOG_FILE" | tail -160

exit "$status"
