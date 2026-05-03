#!/usr/bin/env bash
set -uo pipefail

# Collect read-only project diagnostics with a short stdout summary.
# This script helps Codex find the right entry point without dumping the repository.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$ROOT_DIR/.codex-logs"
LOG_FILE="$LOG_DIR/project-diagnose.log"

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

log_section "Schemes"
while IFS= read -r workspace; do
    [[ -z "$workspace" ]] && continue
    {
        echo
        echo "Workspace: $workspace"
        xcodebuild -list -workspace "$workspace"
    } >> "$LOG_FILE" 2>&1
done < <(
    find . -maxdepth 3 -name '*.xcworkspace' -not -path './Pods/*' -not -path './.git/*' | sort
)

while IFS= read -r project; do
    [[ -z "$project" ]] && continue
    {
        echo
        echo "Project: $project"
        xcodebuild -list -project "$project"
    } >> "$LOG_FILE" 2>&1
done < <(
    find . -maxdepth 3 -name '*.xcodeproj' -not -path './Pods/*' -not -path './.git/*' | sort
)

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