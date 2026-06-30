# SmartX Review Remediation Plan

30 findings from static review of `main..smartx`. All validated — no false positives.
Organized by fix order (P0 first, dependencies respected).

---

## P0 — Fix immediately (security / correctness)

### 1. TUN contradiction: preflight says unsupported, coordinator does it
**File:** `TunPreflightPlanner.swift:21,63,337`

Preflight marks embedded-core as `embeddedCoreUnsupported` and returns
`"embedded-core TUN is unsupported in this build"`. But `TunLifecycleCoordinator`
now routes embedded-core to `applyEmbeddedTunToggle` which writes YAML + reloads.

Fix: update `TunPreflightPlanner` to distinguish "embedded-core TUN via file-based
update" from "unsupported." Change `embeddedCoreUnsupported` blocker to a warning
when the coordinator can handle it. Update user-facing text from "unsupported" to
"Embedded-core TUN uses config-file update; system-level TUN verification is not
available."

### 2. YAML injection in ConfigYAMLEditor.renderSection
**File:** `ConfigYAMLEditor.swift:72-74`

`renderSection` writes strings as `"\(value)"` with no escaping. A value containing
`"`, `\`, newline, or `: ` can produce invalid YAML or inject keys.

Fix: add `escapeYAMLString(_:)` helper:
- Escape `\` → `\\`, `"` → `\"`
- Reject or escape newlines (`\n` → `\\n`)
- Wrap in quotes only if needed

Also add input validation to TUN/DNS editor text fields to reject control chars.

### 3. Helper signing boundary not closed
**Files:** `Info.plist`, `Helper-Info.plist`, `project.pbxproj`

Mixed identities: `com.doodlenet.ClashX`, `com.west2online.ClashX`, old Team ID.
`check_helper_requirement.py` only checks non-empty — doesn't verify
SMJobBless three-way consistency (app SMPrivilegedExecutables ↔ helper
SMAuthorizedClients ↔ helper plist).

Fix: blocked by identity migration. Document as prerequisite.
Add CI check: verify helper binary embedded plist matches build settings.

### 4. Debug helper fail-open
**File:** `ProxyConfigHelper.m:103-107`

In DEBUG with empty `AllowedClientCodeSigningRequirement`, accepts ANY process.
If helper is installed system-wide (via legacy path), any local process can
modify system proxy.

Fix: add `#if DEBUG` runtime check that also verifies the connecting process
is the SmartX app bundle (match bundle ID) even when signing requirement is
empty. At minimum, verify `NSRunningApplication.bundleIdentifier` matches
expected app bundle ID.

### 5. Log export bypasses sanitization
**File:** `DiagnosticsDashboardViewController.swift:actionExportLogs`

`actionExportLogs` exports `logViewModel.snapshot?.renderedOutput(redactFilePath: true)`.
`renderedOutput` only redacts file paths, not log body content. Contrast with
`DiagnosticsBundleExporter` which runs `SmartXRedactor.sanitizeText`.

Fix: run `SmartXRedactor.sanitizeText()` on export text before writing.
Add `redactContent: true` parameter to `renderedOutput`.

### 6. URL redaction misses path tokens
**File:** `SmartXRedactor.swift:redactURLString`

Only strips user/password, fragment, query values. Subscription tokens in path
(e.g. `/subscribe/<token>`) survive.

Fix: add path-segment redaction heuristic — if a path segment looks like a token
(base64, hex32+, UUID), replace with `<redacted>`. Add test cases for common
subscription URL patterns.

---

## P1 — Fix in next PR (build/test reliability / semantic issues)

### 7. Duplicate file references in project.pbxproj
**Files:** `ControllerEndpointBuilder.swift`, `ConfigValidationIssue.swift`,
`TunConfigValidator.swift`, `SmartXRedactor.swift`, `HelperStatus.swift`

Two sets of PBXFileReference + PBXBuildFile per file (app target + test target
duplication from `add-test-target.rb`).

Fix: deduplicate — keep one PBXFileReference per file, share across targets.
Ruby script or manual pbxproj cleanup.

### 8. Tests/README.md stale
**File:** `Tests/README.md`

Still says "no dedicated Xcode unit-test target." SmartXTests.xctest exists.

Fix: update to describe SmartXTests target, smoke harnesses, how to run both.

### 9. PR CI doesn't run xcodebuild test on SmartXTests
**File:** `.github/workflows/pr-ci.yml`

Smoke harnesses run individually. `xcodebuild test` for SmartXTests is only in
`codex-test-focused.sh`, not in the CI workflow directly.

Fix: add `xcodebuild test -only-testing:SmartXTests` step to both CI jobs
(validation-gate and pr-artifacts).

### 10. Stub-based tests can't verify integration
**Files:** `Tests/SmartXTests/TestStubs.swift`

Known limitation. Stubs test pure logic, not CocoaPods/AppKit/Go bridge.

No code fix — document limitation. Add a `Tests/SmartXTests/README.md` explaining
what the XCTest target covers vs. what requires integration testing.

### 11. Helper CI check too narrow
**File:** `scripts/check_helper_requirement.py`

Only checks build setting text, not binary embedded plist.
Doesn't verify app ↔ helper requirement match.

Fix: add binary check step — extract `__TEXT,__info_plist` from built helper
via `strings`/`plutil`, verify it matches build settings. Add app
`SMPrivilegedExecutables` ↔ helper `SMAuthorizedClients` consistency check.

### 12. Release workflow misleading
**File:** `.github/workflows/main.yml`

Tag/release triggers produce unsigned zip. Name implies release artifact.

Fix: rename workflow to "Unsigned Dev Snapshot." Add prominent comment:
"Not a release. Signing/notarization disabled."

### 13-14. Identity migration + Sparkle残留
**Files:** `Info.plist`, `AppDelegate.swift`, `AutoUpgardeManager.swift`

Blocked by signing identity migration. Document as known.
For #14: verify Sparkle UI is hidden/greyed out, not showing misleading
"Update available" or error states.

### 15-16. generated-effective naming vs. actual semantics
**Files:** `ProfileArtifactManager.swift`, `Paths.swift`

Files named `generated-effective.yaml` but content is `generationMode: source-copy`.
Naming suggests a generated config when it's actually a copy.

Fix: rename paths to `successful-reload-artifact.yaml` and
`last-known-good.yaml`. Keep backward compat by checking both old and new
names on read. Update UI labels.

### 17. YAML string manipulation ceiling
**Files:** `ConfigYAMLEditor.swift`, `TunConfigEditorViewController.swift`,
`DNSConfigEditorViewController.swift`

Known ponytail ceiling. String-based upsert loses comments, breaks on
anchors/complex YAML.

No immediate fix — documented ceiling with upgrade path (YAML library).
Add input validation to reject obviously-dangerous patterns.

### 18. Write-then-reload crash = data loss
**Files:** `TunConfigEditorViewController.swift:applyTunConfigViaConfigFile`,
`TunLifecycleCoordinator.swift:applyEmbeddedTunToggle`

Write file → reload → rollback on failure. If crash/reboot between write
and rollback, original config lost.

Fix: write to temp file → atomic rename of original to backup →
write new → reload → on failure, restore from backup.
Three-step: backup, write, verify.

### 19. Embedded-core TUN messaging inconsistency
**Files:** `TunPreflightPlanner.swift`, `CoreSettingViewController.swift`

Preflight says "unsupported" but UI allows toggle + coordinator does it.

Fix: same as #1. Update all messages to say "file-based TUN update,
system-level verification unavailable" instead of "unsupported."

### 20. Provider health check race
**File:** `DiagnosticsDashboardViewController.swift:actionHealthCheckProviders`

`succeeded.append(provider)` and `failed.append(provider)` in async callbacks
without queue synchronization. Potential data race on `[String]`.

Fix: dispatch all appends to `DispatchQueue.main` or use a serial queue.

---

## P2 — Address in maintenance passes

### 21. DiagnosticsBundleExporter reads full log then truncates
Fix: use `DiagnosticsLogReader` tail-read logic instead of `String(contentsOfFile:)`.

### 22. Log viewer shows unredacted logs
Fix: add "Redact" toggle to log viewer, default off. `actionExportLogs` already
needs redaction (#5); extend to viewer.

### 23. RemoteConfigManager.group.leave() leak
Fix: use `defer { group.leave() }` at start of callback, before any guard/return.

### 24. Remote config error logs expose subscription URL
Fix: redact `config.url` with `SmartXRedactor.redactURLString` before logging.

### 25. Helper restoreProxy payload validation
Fix: add typed validation for proxy dictionary contents (port range, host format).

### 26. Release "Reset Daemon" button blocked
Fix: `removeInstallHelper()` should log a clear message instead of silently
no-opping. UI should show "Reset Daemon requires Debug build."

### 27-28. Build script Info.plist mutation + Go header dependency
Document known behavior. For #28: add pre-build check in Xcode scheme that
verifies `goClash.h` exists before compiling.

### 29. SwiftFormat/SwiftLint in build phase
Move to pre-commit hook or CI-only script phase with "Based on dependency
analysis" checked. Don't run on every Debug build.

### 30. README/docs vs. reality gap
Create `docs/identity-migration-plan.md` documenting which names must stay
(temporary, compatibility) vs. must change (before release). Update README
to reflect current SmartX state.

---

## Fix order

```
PR #24 (P0): #1 TUN contradiction + #19 messaging
              #2 YAML injection + #17 validation hardening
              #4 Debug helper guard
              #5 Log export sanitization
              #6 URL path token redaction

PR #25 (P1): #7 Duplicate pbxproj refs
              #8 Tests README
              #9 CI xcodebuild test
              #11 Helper CI check hardening
              #18 Write-then-reload crash safety
              #20 Provider health check race

PR #26 (P1/P2): #15-16 generated-effective naming
                #21 Log tail reuse
                #23 group.leave leak
                #24 Subscription URL redaction in logs
                #26 Reset Daemon message

Blocked: #3 #13 #14 #30 — identity migration
Known ceiling: #10 #17 — documented ponytail debt
Document: #12 #22 #25 #27 #28 #29
```
