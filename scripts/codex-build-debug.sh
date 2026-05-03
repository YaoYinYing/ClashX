#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKSPACE_DIR="$ROOT_DIR/ClashX.xcworkspace"
WORKSPACE_DATA="$WORKSPACE_DIR/contents.xcworkspacedata"
LOG_DIR="$ROOT_DIR/.codex-logs"
LOG_FILE="$LOG_DIR/xcodebuild-debug.log"

cd "$ROOT_DIR"
mkdir -p "$LOG_DIR"

if [ ! -d "$WORKSPACE_DIR" ]; then
  echo "BUILD FAILED"
  echo "Full log: .codex-logs/xcodebuild-debug.log"
  echo "Reason: Missing workspace directory at ClashX.xcworkspace."
  exit 1
fi

if [ ! -f "$WORKSPACE_DATA" ]; then
  echo "BUILD FAILED"
  echo "Full log: .codex-logs/xcodebuild-debug.log"
  echo "Reason: Missing workspace contents file at ClashX.xcworkspace/contents.xcworkspacedata."
  exit 1
fi

set +e
xcodebuild \
  -workspace "$WORKSPACE_DIR" \
  -scheme ClashX \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  -quiet \
  build \
  > "$LOG_FILE" 2>&1
status=$?
set -e

if [ "$status" -eq 0 ]; then
  echo "BUILD SUCCEEDED"
  echo "Full log: .codex-logs/xcodebuild-debug.log"
  exit 0
fi

if grep -Fq "is not a workspace file" "$LOG_FILE"; then
  echo "BUILD INCONCLUSIVE"
  echo "Full log: .codex-logs/xcodebuild-debug.log"
  echo "Reason: xcodebuild reported that the workspace is not a workspace file, but the workspace directory and contents.xcworkspacedata exist. This may be an environment-specific non-interactive xcodebuild issue."
  echo "Fallback command:"
  echo "xcodebuild -workspace ClashX.xcworkspace -scheme ClashX -configuration Debug CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO -quiet build"
  exit "$status"
fi

echo "BUILD FAILED"
echo "Full log: .codex-logs/xcodebuild-debug.log"
echo
echo "Relevant diagnostics:"
grep -E "error:|warning:|fatal error|Undefined symbols|duplicate symbol|No such file|Command SwiftCompile failed|Command CompileSwiftSources failed|Ld " "$LOG_FILE" | tail -160

exit "$status"
