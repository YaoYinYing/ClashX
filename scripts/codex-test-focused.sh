#!/usr/bin/env bash
set -uo pipefail

# Run a focused Xcode test command with minimal stdout.
# Full output is stored in .codex-logs so Codex only receives a short summary.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$ROOT_DIR/.codex-logs"
LOG_FILE="$LOG_DIR/xcode-test-focused.log"
RESULT_BUNDLE="$LOG_DIR/xcode-test-focused.xcresult"

WORKSPACE="${SMARTX_WORKSPACE:-ClashX.xcworkspace}"
PROJECT="${SMARTX_PROJECT:-}"
SCHEME="${SMARTX_SCHEME:-ClashX}"
CONFIGURATION="${SMARTX_CONFIGURATION:-Debug}"
DESTINATION="${SMARTX_TEST_DESTINATION:-platform=macOS}"
ONLY_TESTING="${SMARTX_ONLY_TESTING:-}"
SKIP_TESTING="${SMARTX_SKIP_TESTING:-}"

mkdir -p "$LOG_DIR"
rm -rf "$RESULT_BUNDLE"
: > "$LOG_FILE"

cd "$ROOT_DIR" || exit 2

project_args=()
if [[ -n "$PROJECT" ]]; then
    project_args=(-project "$PROJECT")
elif [[ -d "$WORKSPACE" ]]; then
    project_args=(-workspace "$WORKSPACE")
else
    echo "TEST FAILED"
    echo "Missing workspace: $WORKSPACE"
    echo "Set SMARTX_WORKSPACE or SMARTX_PROJECT."
    exit 2
fi

cmd=(
    xcodebuild
    test
    "${project_args[@]}"
    -scheme "$SCHEME"
    -configuration "$CONFIGURATION"
    -destination "$DESTINATION"
    -resultBundlePath "$RESULT_BUNDLE"
    CODE_SIGNING_ALLOWED=NO
    CODE_SIGNING_REQUIRED=NO
    -quiet
)

if [[ -n "$ONLY_TESTING" ]]; then
    IFS=',' read -r -a only_items <<< "$ONLY_TESTING"
    for item in "${only_items[@]}"; do
        cmd+=("-only-testing:$item")
    done
fi

if [[ -n "$SKIP_TESTING" ]]; then
    IFS=',' read -r -a skip_items <<< "$SKIP_TESTING"
    for item in "${skip_items[@]}"; do
        cmd+=("-skip-testing:$item")
    done
fi

{
    echo "Command:"
    printf '  %q' "${cmd[@]}"
    echo
    echo
} >> "$LOG_FILE"

"${cmd[@]}" >> "$LOG_FILE" 2>&1
status=$?

if [[ "$status" -eq 0 ]]; then
    echo "TEST SUCCEEDED"
    echo "Log: $LOG_FILE"
    echo "Result bundle: $RESULT_BUNDLE"
    exit 0
fi

echo "TEST FAILED"
echo "Log: $LOG_FILE"
echo "Result bundle: $RESULT_BUNDLE"
echo
echo "Relevant diagnostics:"

diagnostics="$(
    grep -E \
        "error:|fatal error|failed|Failing tests:|Test Case .* failed|Assertion failed|Command .* failed|Executed [0-9]+ tests" \
        "$LOG_FILE" | tail -160
)"

if [[ -n "$diagnostics" ]]; then
    echo "$diagnostics"
else
    tail -120 "$LOG_FILE"
fi

exit "$status"