#!/usr/bin/env bash
set -uo pipefail

# Collect read-only project diagnostics with a short stdout summary.
# This script helps Codex find the right entry point without dumping the repository.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$ROOT_DIR/.codex-logs"
LOG_FILE="$LOG_DIR/project-diagnose.log"
WORKSPACE_FILE="$ROOT_DIR/ClashX.xcworkspace/contents.xcworkspacedata"

mkdir -p "$LOG_DIR"
: > "$LOG_FILE"

cd "$ROOT_DIR" || exit 2

log_section() {
    {
        echo
        echo "## $1"
    } >> "$LOG_FILE"
}

run_optional() {
    {
        echo
        echo "\$ $*"
    } >> "$LOG_FILE"
    "$@" >> "$LOG_FILE" 2>&1
    return 0
}

log_section "Repository"
run_optional pwd
run_optional git rev-parse --show-toplevel
run_optional git rev-parse --abbrev-ref HEAD
run_optional git rev-parse --short HEAD
run_optional git status --short

log_section "Xcode environment"
run_optional xcode-select -p
run_optional xcrun --find xcodebuild
run_optional xcodebuild -version

log_section "Xcode containers"
find . \
    -maxdepth 4 \
    \( -name '*.xcworkspace' -o -name '*.xcodeproj' \) \
    -not -path './Pods/*' \
    -not -path './Vendor/*' \
    -not -path './Carthage/*' \
    -not -path './.git/*' \
    | sort >> "$LOG_FILE" 2>&1

log_section "Workspace XML Preview"
if [[ -f "$WORKSPACE_FILE" ]]; then
    sed -n '1,80p' "$WORKSPACE_FILE" >> "$LOG_FILE" 2>&1
else
    echo "Missing workspace XML: $WORKSPACE_FILE" >> "$LOG_FILE"
fi

log_section "Workspace readiness"
{
    echo
    echo "\$ bash scripts/ensure-xcworkspace.sh"
    bash scripts/ensure-xcworkspace.sh
} >> "$LOG_FILE" 2>&1 || true

log_section "xcodebuild list"
run_optional xcodebuild -list -workspace "$ROOT_DIR/ClashX.xcworkspace"
run_optional xcodebuild -list -project "$ROOT_DIR/ClashX.xcodeproj"

log_section "Ruby and CocoaPods environment"
run_optional ruby -v
run_optional which ruby
run_optional bundle -v
run_optional which bundle
run_optional pod --version
run_optional which pod
run_optional bundle exec ruby -v
run_optional bundle exec pod --version

global_pod_version="$(pod --version 2>/dev/null || true)"
bundler_pod_version="$(bundle exec pod --version 2>/dev/null || true)"
if [[ -n "$global_pod_version" && -n "$bundler_pod_version" && "$global_pod_version" != "$bundler_pod_version" ]]; then
    log_section "Bundler note"
    echo "Global CocoaPods differs from Bundler CocoaPods. Prefer bundle exec pod install for this repository." >> "$LOG_FILE"
fi

log_section "Top-level directories"
find . \
    -maxdepth 2 \
    -type d \
    -not -path './.git*' \
    -not -path './Pods*' \
    -not -path './Vendor*' \
    -not -path './Carthage*' \
    -not -path './DerivedData*' \
    -not -path './.codex-logs*' \
    | sort >> "$LOG_FILE" 2>&1

log_section "Key files"
find . \
    -maxdepth 4 \
    \( \
        -name 'AGENTS.md' \
        -o -name 'Podfile' \
        -o -name 'Cartfile' \
        -o -name 'Package.swift' \
        -o -name 'Info.plist' \
        -o -name '*.entitlements' \
        -o -name '*.xcconfig' \
        -o -name '*.appcast' \
        -o -name '*.yml' \
        -o -name '*.yaml' \
    \) \
    -not -path './Pods/*' \
    -not -path './Vendor/*' \
    -not -path './Carthage/*' \
    -not -path './.git/*' \
    | sort >> "$LOG_FILE" 2>&1

log_section "Potential generated or external directories"
find . \
    -maxdepth 2 \
    -type d \
    \( \
        -name 'Pods' \
        -o -name 'Vendor' \
        -o -name 'Carthage' \
        -o -name 'DerivedData' \
        -o -name 'build' \
    \) \
    | sort >> "$LOG_FILE" 2>&1

echo "PROJECT DIAGNOSIS SUCCEEDED"
echo "Root: $ROOT_DIR"
echo "Selected Xcode: $(xcode-select -p 2>/dev/null || echo unknown)"
echo "Detected Xcode containers:"
find . \
    -maxdepth 3 \
    \( -name '*.xcworkspace' -o -name '*.xcodeproj' \) \
    -not -path './Pods/*' \
    -not -path './Vendor/*' \
    -not -path './Carthage/*' \
    -not -path './.git/*' \
    | sort \
    | sed 's#^\./#- #'
echo "Log: $LOG_FILE"
