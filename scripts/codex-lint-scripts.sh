#!/usr/bin/env bash
set -uo pipefail

# Lint repository shell scripts with minimal stdout.
# Prefer ShellCheck. Fall back to bash -n when ShellCheck is unavailable.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$ROOT_DIR/.codex-logs"
LOG_FILE="$LOG_DIR/script-lint.log"

mkdir -p "$LOG_DIR"
: > "$LOG_FILE"

cd "$ROOT_DIR" || exit 2

script_files=()

if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    while IFS= read -r file; do
        [[ -n "$file" ]] && script_files+=("$file")
    done < <(
        git ls-files '*.sh' \
            ':(exclude)Pods/**' \
            ':(exclude)Vendor/**' \
            ':(exclude)Carthage/**' \
            ':(exclude).codex-logs/**'
    )
else
    while IFS= read -r file; do
        [[ -n "$file" ]] && script_files+=("$file")
    done < <(
        find Scripts -type f -name '*.sh' 2>/dev/null
    )
fi

if [[ "${#script_files[@]}" -eq 0 ]]; then
    echo "SCRIPT LINT SKIPPED"
    echo "No shell scripts found."
    echo "Log: $LOG_FILE"
    exit 0
fi

{
    echo "Scripts checked:"
    printf '  %s\n' "${script_files[@]}"
    echo
} >> "$LOG_FILE"

if command -v shellcheck >/dev/null 2>&1; then
    shellcheck "${script_files[@]}" >> "$LOG_FILE" 2>&1
    status=$?

    if [[ "$status" -eq 0 ]]; then
        echo "SCRIPT LINT SUCCEEDED"
        echo "Checker: shellcheck"
        echo "Files: ${#script_files[@]}"
        echo "Log: $LOG_FILE"
        exit 0
    fi

    echo "SCRIPT LINT FAILED"
    echo "Checker: shellcheck"
    echo "Files: ${#script_files[@]}"
    echo "Log: $LOG_FILE"
    echo
    echo "Relevant diagnostics:"
    tail -160 "$LOG_FILE"
    exit "$status"
fi

status=0
{
    echo "ShellCheck is unavailable. Falling back to bash -n."
    echo
} >> "$LOG_FILE"

for file in "${script_files[@]}"; do
    bash -n "$file" >> "$LOG_FILE" 2>&1
    file_status=$?
    if [[ "$file_status" -ne 0 ]]; then
        status=1
        echo "Syntax check failed: $file" >> "$LOG_FILE"
    fi
done

if [[ "$status" -eq 0 ]]; then
    echo "SCRIPT LINT SUCCEEDED"
    echo "Checker: bash -n fallback"
    echo "Files: ${#script_files[@]}"
    echo "Log: $LOG_FILE"
    exit 0
fi

echo "SCRIPT LINT FAILED"
echo "Checker: bash -n fallback"
echo "Files: ${#script_files[@]}"
echo "Log: $LOG_FILE"
echo
echo "Relevant diagnostics:"
tail -160 "$LOG_FILE"
exit "$status"