#!/usr/bin/env bash
set -uo pipefail

# Run a focused Xcode test command with minimal stdout.
# Full output is stored in .codex-logs so Codex only receives a short summary.
# Standalone SecurityHarness smoke checks are kept separate in PR CI; this
# wrapper only drives the Xcode test target path when one exists.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$ROOT_DIR/.codex-logs"
LOG_FILE="$LOG_DIR/xcode-test-focused.log"
RESULT_BUNDLE="$LOG_DIR/xcode-test-focused.xcresult"
WORKSPACE_HELPER="$ROOT_DIR/scripts/ensure-xcworkspace.sh"
SECURITY_HARNESSES=(
    "Tests/SecurityHarness/security_harness.swift"
    "Tests/SecurityHarness/redactor_smoke.swift"
    "Tests/SecurityHarness/remote_config_decode_smoke.swift"
    "Tests/SecurityHarness/controller_endpoint_builder_smoke.swift"
    "Tests/SecurityHarness/capability_cache_identity_smoke.swift"
    "Tests/SecurityHarness/config_validator_smoke.swift"
    "Tests/SecurityHarness/diagnostics_log_reader_smoke.swift"
    "Tests/SecurityHarness/diagnostics_artifact_formatter_smoke.swift"
    "Tests/SecurityHarness/profile_artifact_metadata_smoke.swift"
    "Tests/SecurityHarness/smartx_managed_override_smoke.swift"
    "Tests/SecurityHarness/effective_config_generator_smoke.swift"
)

WORKSPACE="${SMARTX_WORKSPACE:-ClashX.xcworkspace}"
PROJECT="${SMARTX_PROJECT:-}"
USE_PROJECT_FALLBACK="${SMARTX_USE_PROJECT_FALLBACK:-0}"
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
    workspace_ready=0
    if bash "$WORKSPACE_HELPER" >> "$LOG_FILE" 2>&1; then
        workspace_ready=1
    else
        if SMARTX_ENSURE_WORKSPACE_REPAIR=1 bash "$WORKSPACE_HELPER" >> "$LOG_FILE" 2>&1; then
            workspace_ready=1
        fi
    fi

    if [[ "$workspace_ready" -eq 1 ]]; then
        project_args=(-workspace "$WORKSPACE")
    elif [[ "$USE_PROJECT_FALLBACK" == "1" && -n "$PROJECT" ]]; then
        project_args=(-project "$PROJECT")
    else
        echo "TEST FAILED"
        echo "Log: $LOG_FILE"
        echo "Result bundle: $RESULT_BUNDLE"
        echo "Reason: Workspace is not ready for xcodebuild."
        echo "Suggested repair:"
        echo "  bundle install"
        echo "  bundle exec pod install"
        echo "  xcodebuild -list -workspace \"$PWD/$WORKSPACE\""
        echo "If the workspace is still broken, run:"
        echo "  SMARTX_REGENERATE_WORKSPACE=1 bash scripts/ensure-xcworkspace.sh"
        echo "Project fallback is diagnostic only and requires SMARTX_USE_PROJECT_FALLBACK=1."
        echo "Standalone SecurityHarness inventory:"
        printf '  %s\n' "${SECURITY_HARNESSES[@]}"
        exit 2
    fi
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
    echo "Standalone SecurityHarness inventory:"
    printf '  %s\n' "${SECURITY_HARNESSES[@]}"
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
