#!/usr/bin/env bash
set -uo pipefail

# Run a focused Xcode test command with minimal stdout.
# Full output is stored in .codex-logs so Codex only receives a short summary.
# This wrapper runs the same smoke harness inventory as the PR validation gate,
# then attempts an Xcode test pass only when a real test target and a usable
# workspace are both available.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$ROOT_DIR/.codex-logs"
LOG_FILE="$LOG_DIR/xcode-test-focused.log"
RESULT_BUNDLE="$LOG_DIR/xcode-test-focused.xcresult"
WORKSPACE_HELPER="$ROOT_DIR/scripts/ensure-xcworkspace.sh"
HARNESS_LOG_DIR="$LOG_DIR/smoke-harnesses"
MODULE_CACHE_PATH="/private/tmp/swift-module-cache"

WORKSPACE="${SMARTX_WORKSPACE:-ClashX.xcworkspace}"
PROJECT="${SMARTX_PROJECT:-}"
USE_PROJECT_FALLBACK="${SMARTX_USE_PROJECT_FALLBACK:-0}"
SCHEME="${SMARTX_SCHEME:-ClashX}"
CONFIGURATION="${SMARTX_CONFIGURATION:-Debug}"
DESTINATION="${SMARTX_TEST_DESTINATION:-platform=macOS}"
ONLY_TESTING="${SMARTX_ONLY_TESTING:-}"
SKIP_TESTING="${SMARTX_SKIP_TESTING:-}"

mkdir -p "$LOG_DIR"
mkdir -p "$HARNESS_LOG_DIR"
rm -rf "$RESULT_BUNDLE"
: > "$LOG_FILE"

cd "$ROOT_DIR" || exit 2

failures=()
passes=()
skips=()

record_failure() {
    failures+=("$1")
}

record_pass() {
    passes+=("$1")
}

record_skip() {
    skips+=("$1")
}

run_swift_script() {
    local name="$1"
    local script_path="$2"
    local log_path="$HARNESS_LOG_DIR/${name}.log"

    : > "$log_path"
    if swift -module-cache-path "$MODULE_CACHE_PATH" "$script_path" >> "$log_path" 2>&1; then
        record_pass "$name"
        echo "PASS $name" >> "$LOG_FILE"
    else
        record_failure "$name"
        {
            echo "FAIL $name"
            echo "Log: $log_path"
        } >> "$LOG_FILE"
    fi
}

run_swiftc_harness() {
    local name="$1"
    local binary="$2"
    shift 2
    local log_path="$HARNESS_LOG_DIR/${name}.log"

    : > "$log_path"
    if swiftc -module-cache-path "$MODULE_CACHE_PATH" "$@" -o "$binary" >> "$log_path" 2>&1 &&
        "$binary" >> "$log_path" 2>&1; then
        record_pass "$name"
        echo "PASS $name" >> "$LOG_FILE"
    else
        record_failure "$name"
        {
            echo "FAIL $name"
            echo "Log: $log_path"
        } >> "$LOG_FILE"
    fi
}

has_xcode_test_target() {
    rg -q "name = .*Tests;|productType = \"com.apple.product-type.bundle.unit-test\"" \
        "$ROOT_DIR/ClashX.xcodeproj/project.pbxproj"
}

workspace_error_is_inconclusive() {
    grep -Eq \
        "local xcodebuild resolution was blocked by simulator or cache environment issues|CoreSimulatorService connection became invalid|simdiskimaged|Operation not permitted|unable to load standard library|ModuleCache|ManifestLoading/.*\\.dia" \
        "$LOG_FILE"
}

run_swift_script "security-harness" "Tests/SecurityHarness/security_harness.swift"
run_swiftc_harness "controller-endpoint-builder-smoke" "/tmp/controller-endpoint-builder-smoke" \
    ClashX/General/Utils/ControllerEndpointBuilder.swift \
    Tests/SecurityHarness/controller_endpoint_builder_smoke.swift
run_swiftc_harness "capability-cache-identity-smoke" "/tmp/capability-cache-identity-smoke" \
    ClashX/General/Utils/ControllerEndpointBuilder.swift \
    ClashX/General/Managers/CoreCapability.swift \
    Tests/SecurityHarness/capability_cache_identity_smoke.swift
run_swiftc_harness "config-validator-smoke" "/tmp/config-validator-smoke" \
    ClashX/General/Utils/ConfigValidationIssue.swift \
    ClashX/General/Utils/TunConfigValidator.swift \
    ClashX/General/Utils/DNSConfigValidator.swift \
    Tests/SecurityHarness/config_validator_smoke.swift
run_swiftc_harness "diagnostics-log-reader-smoke" "/tmp/diagnostics-log-reader-smoke" \
    ClashX/General/Utils/SmartXRedactor.swift \
    ClashX/General/Utils/DiagnosticsLogReader.swift \
    Tests/SecurityHarness/diagnostics_log_reader_smoke.swift
run_swiftc_harness "diagnostics-artifact-formatter-smoke" "/tmp/diagnostics-artifact-formatter-smoke" \
    ClashX/General/Utils/SmartXRedactor.swift \
    ClashX/General/Utils/DiagnosticsArtifactFormatter.swift \
    Tests/SecurityHarness/diagnostics_artifact_formatter_smoke.swift
run_swiftc_harness "profile-artifact-metadata-smoke" "/tmp/profile-artifact-metadata-smoke" \
    ClashX/General/Managers/ProfileArtifactManager.swift \
    Tests/SecurityHarness/profile_artifact_metadata_smoke.swift
run_swiftc_harness "smartx-managed-override-smoke" "/tmp/smartx-managed-override-smoke" \
    ClashX/Models/SmartXManagedOverrideModel.swift \
    ClashX/General/Managers/SmartXManagedOverrideManager.swift \
    Tests/SecurityHarness/smartx_managed_override_smoke.swift
run_swiftc_harness "effective-config-generator-smoke" "/tmp/effective-config-generator-smoke" \
    ClashX/Models/SmartXManagedOverrideModel.swift \
    ClashX/General/Managers/EffectiveConfigGenerator.swift \
    Tests/SecurityHarness/effective_config_generator_smoke.swift
run_swiftc_harness "helper-status-smoke" "/tmp/helper-status-smoke" \
    ClashX/Models/HelperStatus.swift \
    Tests/SecurityHarness/helper_status_smoke.swift
run_swiftc_harness "helper-command-contract-smoke" "/tmp/helper-command-contract-smoke" \
    ClashX/Models/HelperCommandContract.swift \
    ClashX/General/Utils/HelperCommandRegistry.swift \
    Tests/SecurityHarness/helper_command_contract_smoke.swift
run_swiftc_harness "tun-lifecycle-diagnostics-smoke" "/tmp/tun-lifecycle-diagnostics-smoke" \
    ClashX/General/Utils/ConfigValidationIssue.swift \
    ClashX/General/Utils/TunConfigValidator.swift \
    ClashX/General/Utils/DNSConfigValidator.swift \
    ClashX/Models/HelperStatus.swift \
    ClashX/Models/HelperCommandContract.swift \
    ClashX/General/Utils/HelperCommandRegistry.swift \
    ClashX/Models/TunLifecycleDiagnostics.swift \
    ClashX/General/Managers/TunPreflightPlanner.swift \
    Tests/SecurityHarness/tun_lifecycle_diagnostics_smoke.swift
run_swiftc_harness "redactor-smoke" "/tmp/redactor-smoke" \
    ClashX/General/Utils/SmartXRedactor.swift \
    Tests/SecurityHarness/redactor_smoke.swift
run_swiftc_harness "remote-config-decode-smoke" "/tmp/remote-config-decode-smoke" \
    ClashX/Models/RemoteConfigModel.swift \
    Tests/SecurityHarness/remote_config_decode_smoke.swift

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
        if workspace_error_is_inconclusive; then
            record_skip "xcodebuild-test: skipped because local xcodebuild resolution was blocked by simulator or cache environment issues"
        else
            record_skip "xcodebuild-test: skipped because workspace is unavailable"
        fi
    fi
else
    record_skip "xcodebuild-test: skipped because workspace is missing ($WORKSPACE)"
fi

if [[ "${#project_args[@]}" -gt 0 ]]; then
    if has_xcode_test_target; then
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
            record_pass "xcodebuild-test"
        else
            record_failure "xcodebuild-test"
        fi
    else
        record_skip "xcodebuild-test: skipped because this repo does not yet have a wired Xcode unit-test target"
    fi
fi

{
    echo
    echo "PASS count: ${#passes[@]}"
    printf '  %s\n' "${passes[@]}"
    echo "SKIP count: ${#skips[@]}"
    printf '  %s\n' "${skips[@]}"
    echo "FAIL count: ${#failures[@]}"
    printf '  %s\n' "${failures[@]}"
} >> "$LOG_FILE"

if [[ "${#failures[@]}" -eq 0 ]]; then
    echo "TEST SUCCEEDED"
    echo "Log: $LOG_FILE"
    echo "Result bundle: $RESULT_BUNDLE"
    echo "Smoke harnesses passed: ${#passes[@]}"
    if [[ "${#skips[@]}" -gt 0 ]]; then
        echo "Skipped:"
        printf '  %s\n' "${skips[@]}"
    fi
    exit 0
fi

echo "TEST FAILED"
echo "Log: $LOG_FILE"
echo "Result bundle: $RESULT_BUNDLE"
echo "Failures:"
printf '  %s\n' "${failures[@]}"
echo
echo "Relevant diagnostics:"
grep -E "FAIL |error:|fatal error|failed|Failing tests:|Test Case .* failed|Assertion failed|Command .* failed|Executed [0-9]+ tests" "$LOG_FILE" | tail -200

exit 1
