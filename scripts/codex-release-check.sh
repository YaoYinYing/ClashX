#!/usr/bin/env bash
set -uo pipefail

# Run read-only release checks with minimal stdout.
# Notarization is disabled by default and must be explicitly enabled.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$ROOT_DIR/.codex-logs"
LOG_FILE="$LOG_DIR/release-check.log"
BUILD_SETTINGS_FILE="$LOG_DIR/release-build-settings.txt"

WORKSPACE="${SMARTX_WORKSPACE:-ClashX.xcworkspace}"
PROJECT="${SMARTX_PROJECT:-}"
SCHEME="${SMARTX_SCHEME:-ClashX}"
CONFIGURATION="${SMARTX_RELEASE_CONFIGURATION:-Release}"
APP_PATH="${SMARTX_APP_PATH:-}"
UPDATE_FEED="${SMARTX_UPDATE_FEED:-}"
RUN_NOTARY="${SMARTX_RUN_NOTARY:-0}"
NOTARIZATION_ARTIFACT="${SMARTX_NOTARIZATION_ARTIFACT:-}"
NOTARY_PROFILE="${SMARTX_NOTARY_PROFILE:-}"
STAPLE_TARGET="${SMARTX_STAPLE_TARGET:-}"

mkdir -p "$LOG_DIR"
: > "$LOG_FILE"
: > "$BUILD_SETTINGS_FILE"

cd "$ROOT_DIR" || exit 2

failures=0

log_section() {
    {
        echo
        echo "## $1"
    } >> "$LOG_FILE"
}

record_failure() {
    failures=$((failures + 1))
    echo "FAIL: $1" >> "$LOG_FILE"
}

run_logged() {
    log_section "$*"
    "$@" >> "$LOG_FILE" 2>&1
    local status=$?
    if [[ "$status" -ne 0 ]]; then
        record_failure "$*"
    fi
    return "$status"
}

extract_setting() {
    local key="$1"
    awk -F ' = ' -v key="$key" '
        $1 ~ key {
            value = $2
            gsub(/^[ \t]+|[ \t]+$/, "", value)
            print value
            exit
        }
    ' "$BUILD_SETTINGS_FILE"
}

project_args=()
if [[ -n "$PROJECT" ]]; then
    project_args=(-project "$PROJECT")
elif [[ -d "$WORKSPACE" ]]; then
    project_args=(-workspace "$WORKSPACE")
else
    echo "RELEASE CHECK FAILED"
    echo "Missing workspace: $WORKSPACE"
    echo "Set SMARTX_WORKSPACE or SMARTX_PROJECT."
    exit 2
fi

log_section "Xcode environment"
{
    echo "Selected developer directory:"
    xcode-select -p
    echo
    echo "xcodebuild:"
    xcrun --find xcodebuild
    echo
    xcodebuild -version
} >> "$LOG_FILE" 2>&1 || record_failure "Xcode environment check"

log_section "Git state"
{
    git rev-parse --show-toplevel
    git rev-parse --abbrev-ref HEAD
    git rev-parse --short HEAD
    git status --short
} >> "$LOG_FILE" 2>&1 || record_failure "Git state check"

log_section "Release build settings"
xcodebuild \
    "${project_args[@]}" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -showBuildSettings \
    > "$BUILD_SETTINGS_FILE" 2>> "$LOG_FILE"

if [[ "$?" -ne 0 ]]; then
    record_failure "xcodebuild -showBuildSettings"
else
    {
        echo "Relevant build settings:"
        grep -E "PRODUCT_BUNDLE_IDENTIFIER|MARKETING_VERSION|CURRENT_PROJECT_VERSION|DEVELOPMENT_TEAM|CODE_SIGN_STYLE|CODE_SIGN_IDENTITY|ENABLE_HARDENED_RUNTIME|INFOPLIST_FILE" \
            "$BUILD_SETTINGS_FILE" | sort -u
    } >> "$LOG_FILE"
fi

if [[ -n "$APP_PATH" ]]; then
    if [[ -d "$APP_PATH" ]]; then
        run_logged codesign --verify --deep --strict --verbose=2 "$APP_PATH"
        log_section "Code signature details"
        codesign -dv --verbose=4 "$APP_PATH" >> "$LOG_FILE" 2>&1

        log_section "Gatekeeper assessment"
        spctl --assess --type execute --verbose=4 "$APP_PATH" >> "$LOG_FILE" 2>&1
        if [[ "$?" -ne 0 ]]; then
            record_failure "spctl assessment"
        fi
    else
        record_failure "App path does not exist: $APP_PATH"
    fi
else
    log_section "App signature check"
    echo "Skipped. Set SMARTX_APP_PATH to check a built .app bundle." >> "$LOG_FILE"
fi

if [[ -n "$UPDATE_FEED" ]]; then
    log_section "Update feed check"
    if [[ -f "$UPDATE_FEED" ]]; then
        {
            echo "Update feed: $UPDATE_FEED"
            grep -E "sparkle:version|sparkle:shortVersionString|sparkle:edSignature|enclosure|url=|length=" "$UPDATE_FEED" | head -80
        } >> "$LOG_FILE"
    else
        record_failure "Update feed does not exist: $UPDATE_FEED"
    fi
else
    log_section "Update feed check"
    echo "Skipped. Set SMARTX_UPDATE_FEED to inspect an appcast or update feed." >> "$LOG_FILE"
fi

if [[ "$RUN_NOTARY" == "1" ]]; then
    log_section "Notarization"
    if [[ -z "$NOTARIZATION_ARTIFACT" || -z "$NOTARY_PROFILE" ]]; then
        record_failure "SMARTX_RUN_NOTARY=1 requires SMARTX_NOTARIZATION_ARTIFACT and SMARTX_NOTARY_PROFILE"
    elif [[ ! -f "$NOTARIZATION_ARTIFACT" ]]; then
        record_failure "Notarization artifact does not exist: $NOTARIZATION_ARTIFACT"
    else
        run_logged xcrun notarytool submit "$NOTARIZATION_ARTIFACT" --keychain-profile "$NOTARY_PROFILE" --wait
    fi
else
    log_section "Notarization"
    echo "Skipped. Set SMARTX_RUN_NOTARY=1 to submit an artifact." >> "$LOG_FILE"
fi

if [[ -n "$STAPLE_TARGET" ]]; then
    log_section "Stapler validation"
    if [[ -e "$STAPLE_TARGET" ]]; then
        run_logged xcrun stapler validate "$STAPLE_TARGET"
    else
        record_failure "Staple target does not exist: $STAPLE_TARGET"
    fi
fi

bundle_id="$(extract_setting PRODUCT_BUNDLE_IDENTIFIER)"
marketing_version="$(extract_setting MARKETING_VERSION)"
build_version="$(extract_setting CURRENT_PROJECT_VERSION)"
code_sign_style="$(extract_setting CODE_SIGN_STYLE)"
development_team="$(extract_setting DEVELOPMENT_TEAM)"

if [[ "$failures" -eq 0 ]]; then
    echo "RELEASE CHECK SUCCEEDED"
else
    echo "RELEASE CHECK FAILED"
fi

echo "Bundle identifier: ${bundle_id:-unknown}"
echo "Marketing version: ${marketing_version:-unknown}"
echo "Build version: ${build_version:-unknown}"
echo "Code signing style: ${code_sign_style:-unknown}"
echo "Development team: ${development_team:-unknown}"
echo "Log: $LOG_FILE"

if [[ "$failures" -ne 0 ]]; then
    echo
    echo "Relevant diagnostics:"
    grep -E "FAIL:|error:|not valid|rejected|invalid|resource envelope|CSSMERR|spctl|notarization|No such file" "$LOG_FILE" | tail -160
    exit 1
fi

exit 0