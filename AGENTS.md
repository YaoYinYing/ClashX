
# SmartX Agent Guide

SmartX is a private macOS proxy client derived from ClashX. The project should stay small, auditable, and safe for personal maintenance. Prefer local, minimal, reviewable changes over broad refactors.

This file defines repository-level rules for Codex. More specific `AGENTS.md` files may exist under subdirectories and should override this file for their own scope.

## Project intent

SmartX is maintained as a trusted macOS proxy client for a small private user group. Security, stability, profile compatibility, and predictable release behavior matter more than feature speed.

Do not treat this repository as a place for speculative redesign. When a task can be solved by a narrow patch, use a narrow patch.

## Repository map

- `ClashX/`: main macOS app source, AppKit UI, managers, models, settings, connection dashboard, core bridge call sites, and app-target resources.
- `ClashX/goClash/`: Go c-archive bridge and embedded mihomo or smart core integration.
- `ProxyConfigHelper/`: privileged helper used for macOS system proxy configuration.
- `Tests/`: security harnesses and future XCTest targets.
- `scripts/`: Codex, build, test, and release helper scripts.
- `docs/`: memory documents, roadmap notes, and project goals.
- `ClashX.xcworkspace` and `ClashX.xcodeproj`: Xcode workspace and project metadata.
- `Pods/` and lock files: dependency-managed artifacts; avoid editing unless dependency work is explicit.

If the actual repository layout differs from this map, inspect only the smallest necessary set of files and update this map in a separate patch only when the mismatch affects future maintenance.

## Work style

Before editing, identify the smallest relevant file set.

Do not read the whole repository unless the task is explicitly architectural or the first targeted search fails.

Do not rewrite large files to make small changes.

Do not rename public symbols, files, schemes, bundle identifiers, or user-facing preference keys unless the task explicitly requires migration.

Do not modify generated files, vendored code, dependency lock files, or Xcode project settings unless they are directly involved in the requested change.

Preserve existing Objective-C, Swift, Cocoa, AppKit, and project-specific patterns. Do not introduce SwiftUI, Combine, async rewrites, package-manager changes, or new dependencies unless explicitly requested.

Prefer one focused patch over several opportunistic cleanups.

## Safety rules

Treat proxy configuration, process lifecycle, profile migration, auto-start behavior, privileged helper behavior, update logic, signing, notarization, and credential handling as high-risk areas.

Never print secrets, tokens, proxy passwords, private server addresses, signing identities, provisioning data, or user profile contents unless the user explicitly asks for a redacted diagnostic view.

When inspecting configuration files, redact sensitive values in summaries.

Do not change default network behavior, system proxy behavior, DNS behavior, or auto-launch behavior without stating the user-visible consequence.

Do not make silent migration changes. If profile or preference migration is required, explain the compatibility path and add or update a focused regression test when possible.

## Token discipline

Keep searches narrow.

Prefer `rg`, `git grep`, and targeted file reads over broad directory dumps.

Do not run raw verbose build commands unless a task requires the full build transcript.

Do not paste long logs into the response. Store long logs under `.codex-logs/` and report only the relevant summary.

When a command succeeds, return the success line and the log path only.

When a command fails, return the failure line, the log path, and the smallest useful diagnostic excerpt.

If a log must be inspected, read only the region around the first relevant error.

## Build and verification

Use the project helper scripts below. Do not inline their contents into this document.

For a normal Debug build, use:

```bash
scripts/codex-build-debug.sh
```

If the debug wrapper reports `BUILD INCONCLUSIVE` due to the workspace false-negative, run the printed direct `xcodebuild` fallback in an interactive terminal and report both results.

For a focused unit-test run, use:

```bash
SMARTX_ONLY_TESTING='ClashXTests/ProfileParserTests' scripts/codex-test-focused.sh
```

For release, signing, packaging, notarization, or update-feed checks, use:

```bash
SMARTX_APP_PATH='build/Release/ClashX.app' scripts/codex-release-check.sh
```

or

```bash
SMARTX_RUN_NOTARY=1 SMARTX_NOTARIZATION_ARTIFACT='dist/SmartX.zip' SMARTX_NOTARY_PROFILE='SmartXNotary' scripts/codex-release-check.sh
```

For shell-script checks, use:

```bash
scripts/codex-lint-scripts.sh
```

For dependency or project-structure diagnostics, use:

```bash
scripts/codex-diagnose-project.sh
```

If these scripts do not exist, do not replace them with raw verbose commands by default. State which script is missing and suggest the smallest temporary command needed for the current task.

## Xcode command policy

Do not run raw `xcodebuild` as the default verification command.

Use quiet wrapper scripts that write full output to `.codex-logs/` and print only a short result.

Raw `xcodebuild` may be used only when the wrapper is missing or when the task specifically requires direct Xcode diagnostics.

If raw `xcodebuild` is unavoidable, prefer `-quiet`, disable signing for local builds when appropriate, and redirect full output to a log file.

## Expected log locations

Build logs should be written under:

```text
.codex-logs/xcodebuild-debug.log
```

Focused test logs should be written under:

```text
.codex-logs/xcode-test-focused.log
```

Release check logs should be written under:

```text
.codex-logs/release-check.log
```

Script lint logs should be written under:

```text
.codex-logs/script-lint.log
```

Project diagnostic logs should be written under:

```text
.codex-logs/project-diagnose.log
```

Do not commit `.codex-logs/`.

## Testing expectations

For UI-only changes, build the app target when possible and summarize the affected UI path.

For profile parsing, profile switching, migration, YAML, plist, or config-path changes, run the focused tests for the changed component.

For process lifecycle changes, verify start, stop, restart, crash recovery, and stale process handling when tests or scripts exist.

For release-related changes, run the release check script and state whether bundle identifier, version metadata, signing settings, and update metadata remain consistent.

If tests are unavailable, explain the narrow manual verification path instead of inventing broad test coverage.

## Git discipline

Before editing, inspect the working tree.

Do not overwrite user changes.

Do not stage or commit unless the user explicitly asks.

Keep unrelated formatting changes out of the patch.

After editing, summarize only the changed files and the reason for each change.

## Output format

For normal tasks, respond with:

```text
Changed files:
- path: reason

Verification:
- command: result

Risk:
- remaining risk or "No known remaining risk."
```

For investigation-only tasks, respond with:

```text
Relevant files:
- path: why it matters

Finding:
- concise diagnosis

Next patch:
- smallest safe change
```

For failed verification, respond with:

```text
Verification failed:
- command
- log path
- relevant diagnostic excerpt

Likely cause:
- concise cause

Next step:
- smallest next action
```

## Subdirectory guidance

If work in one area becomes frequent, add a smaller `AGENTS.md` in that subdirectory instead of expanding this root file.

Recommended future locations:

```text
ClashX/AGENTS.md
ProxyConfigHelper/AGENTS.md
Tests/AGENTS.md
scripts/AGENTS.md
```

Each subdirectory guide should stay shorter than this root guide and should contain only rules that are specific to that area.
