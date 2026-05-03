#!/usr/bin/env bash
set -euo pipefail

LOG_DIR=".codex-logs"
LOG_FILE="$LOG_DIR/xcodebuild-debug.log"

mkdir -p "$LOG_DIR"

set +e
xcodebuild \
  -workspace ClashX.xcworkspace \
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
  echo "Full log: $LOG_FILE"
  exit 0
fi

echo "BUILD FAILED"
echo "Full log: $LOG_FILE"
echo
echo "Relevant diagnostics:"
grep -E "error:|warning:|fatal error|Undefined symbols|duplicate symbol|No such file|Command SwiftCompile failed|Command CompileSwiftSources failed|Ld " "$LOG_FILE" | tail -160

exit "$status"