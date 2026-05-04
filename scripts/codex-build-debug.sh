#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="$ROOT_DIR/.codex-logs"
LOG_FILE="$LOG_DIR/xcodebuild-debug.log"
WORKSPACE_HELPER="$ROOT_DIR/scripts/ensure-xcworkspace.sh"

cd "$ROOT_DIR"
mkdir -p "$LOG_DIR"
: > "$LOG_FILE"

workspace_ready=0
if bash "$WORKSPACE_HELPER" >> "$LOG_FILE" 2>&1; then
  workspace_ready=1
else
  if SMARTX_ENSURE_WORKSPACE_REPAIR=1 bash "$WORKSPACE_HELPER" >> "$LOG_FILE" 2>&1; then
    workspace_ready=1
  fi
fi

if [ "$workspace_ready" -ne 1 ]; then
  echo "BUILD FAILED"
  echo "Full log: .codex-logs/xcodebuild-debug.log"
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
  echo "BUILD FAILED"
  echo "Full log: .codex-logs/xcodebuild-debug.log"
  echo "Reason: xcodebuild rejected a structurally valid workspace after CocoaPods readiness checks."
  echo "This is now a real xcodebuild/workspace resolution failure, not a missing dependency preparation issue."
  exit "$status"
fi

echo "BUILD FAILED"
echo "Full log: .codex-logs/xcodebuild-debug.log"
echo
echo "Relevant diagnostics:"
grep -E "error:|warning:|fatal error|Undefined symbols|duplicate symbol|No such file|Command SwiftCompile failed|Command CompileSwiftSources failed|Ld " "$LOG_FILE" | tail -160

exit "$status"
