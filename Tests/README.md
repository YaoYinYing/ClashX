# Tests in this repository

This repository currently has no dedicated Xcode unit-test target. The tests in this folder are **pending integration**.

`Tests/Security/PathSafetyTests.swift` contains XCTest cases for safe config-name validation and config-path containment logic. To enable these tests in Xcode:

1. Add a new macOS Unit Testing Bundle target (e.g. `ClashXTests`).
2. Add `Tests/Security/PathSafetyTests.swift` to that target.
3. Set `@testable import ClashX` for the test target.
4. Run the tests with `xcodebuild test`.

Notes:
- A robust symlink-escape integration test should run on macOS with a writable filesystem sandbox representative of app behavior.
- `PathSafetyTests` currently focuses on deterministic name validation/path APIs and config replacement invariants.
- Manual helper validation case to add during macOS test runs: `http://127.evil.com/proxy.pac` must be rejected by helper PAC validation.
- `Tests/SecurityHarness/security_harness.swift` is a temporary CI smoke test. It mirrors the current suggested-filename validation semantics and does not replace a real XCTest target.
- SmartX redaction currently has no dedicated XCTest target either. For the `codex/goal-may26-01` stabilization PR, the production redactor was kept in app code and the gap remains documented here rather than cloning that logic into another standalone harness.
- A minimal local smoke check for the production redactor is available at `Tests/SecurityHarness/redactor_smoke.swift` and should be run with `swiftc ClashX/General/Utils/SmartXRedactor.swift Tests/SecurityHarness/redactor_smoke.swift -o /tmp/smartx-redactor-smoke && /tmp/smartx-redactor-smoke` when touching diagnostics redaction behavior.
- A minimal local upgrade-compatibility check for persisted remote profiles is available at `Tests/SecurityHarness/remote_config_decode_smoke.swift` and should be run with `swiftc ClashX/Models/RemoteConfigModel.swift Tests/SecurityHarness/remote_config_decode_smoke.swift -o /tmp/remote-config-decode-smoke && /tmp/remote-config-decode-smoke` when changing `RemoteConfigModel` coding behavior.
- A minimal local endpoint-builder smoke check is available at `Tests/SecurityHarness/controller_endpoint_builder_smoke.swift` and should be run with `swiftc ClashX/General/Utils/ControllerEndpointBuilder.swift Tests/SecurityHarness/controller_endpoint_builder_smoke.swift -o /tmp/controller-endpoint-builder-smoke && /tmp/controller-endpoint-builder-smoke` when changing controller URL construction.
- That smoke harness now covers raw dynamic path components with spaces, Chinese characters, slashes, literal percent signs, and the `Proxy A` double-encoding regression.
- A minimal local capability-identity smoke check is available at `Tests/SecurityHarness/capability_cache_identity_smoke.swift` and should be run with `swiftc ClashX/General/Utils/ControllerEndpointBuilder.swift ClashX/General/Managers/CoreCapability.swift Tests/SecurityHarness/capability_cache_identity_smoke.swift -o /tmp/capability-cache-identity-smoke && /tmp/capability-cache-identity-smoke` when changing controller identity or capability-cache sanitization.
- A minimal local SmartX managed-override smoke check is available at `Tests/SecurityHarness/smartx_managed_override_smoke.swift` and should be run with `swiftc ClashX/Models/SmartXManagedOverrideModel.swift ClashX/General/Managers/SmartXManagedOverrideManager.swift Tests/SecurityHarness/smartx_managed_override_smoke.swift -o /tmp/smartx-managed-override-smoke && /tmp/smartx-managed-override-smoke` when changing persisted LightGBM override storage, normalization, future-schema warning behavior, legacy migration behavior, or the no-hidden-write expectation around explicit bootstrap.
- A minimal local config-validator smoke check is available at `Tests/SecurityHarness/config_validator_smoke.swift` and should be run with `swiftc ClashX/General/Utils/ConfigValidationIssue.swift ClashX/General/Utils/TunConfigValidator.swift ClashX/General/Utils/DNSConfigValidator.swift Tests/SecurityHarness/config_validator_smoke.swift -o /tmp/config-validator-smoke && /tmp/config-validator-smoke` when changing the reusable TUN or DNS validation rules.
- A minimal local diagnostics-log-reader smoke check is available at `Tests/SecurityHarness/diagnostics_log_reader_smoke.swift` and should be run with `swiftc ClashX/General/Utils/SmartXRedactor.swift ClashX/General/Utils/DiagnosticsLogReader.swift Tests/SecurityHarness/diagnostics_log_reader_smoke.swift -o /tmp/diagnostics-log-reader-smoke && /tmp/diagnostics-log-reader-smoke` when changing log tailing, filtering, or display limits for diagnostics.
- A minimal local diagnostics-artifact-formatter smoke check is available at `Tests/SecurityHarness/diagnostics_artifact_formatter_smoke.swift` and should be run with `swiftc ClashX/General/Utils/SmartXRedactor.swift ClashX/General/Utils/DiagnosticsArtifactFormatter.swift Tests/SecurityHarness/diagnostics_artifact_formatter_smoke.swift -o /tmp/diagnostics-artifact-formatter-smoke && /tmp/diagnostics-artifact-formatter-smoke` when changing artifact preview redaction behavior in diagnostics.
- A minimal local profile-artifact metadata smoke check is available at `Tests/SecurityHarness/profile_artifact_metadata_smoke.swift` and should be run with `swiftc ClashX/General/Managers/ProfileArtifactManager.swift Tests/SecurityHarness/profile_artifact_metadata_smoke.swift -o /tmp/profile-artifact-metadata-smoke && /tmp/profile-artifact-metadata-smoke` when changing artifact metadata shape or source-copy semantics.
- A minimal local effective-config-generator smoke check is available at `Tests/SecurityHarness/effective_config_generator_smoke.swift` and should be run with `swiftc ClashX/Models/SmartXManagedOverrideModel.swift ClashX/General/Managers/EffectiveConfigGenerator.swift Tests/SecurityHarness/effective_config_generator_smoke.swift -o /tmp/effective-config-generator-smoke && /tmp/effective-config-generator-smoke` when changing the generated-effective-config boundary or the explicit unsupported-until-safe-YAML-emit behavior.
- A minimal local helper-status smoke check is available at `Tests/SecurityHarness/helper_status_smoke.swift` and should be run with `swiftc ClashX/Models/HelperStatus.swift Tests/SecurityHarness/helper_status_smoke.swift -o /tmp/helper-status-smoke && /tmp/helper-status-smoke` when changing helper trust-state naming, helper diagnostic messaging, or helper status serialization.
- `bash scripts/codex-test-focused.sh` now runs the same smoke harness inventory as `.github/workflows/pr-ci.yml`, then records any Xcode test execution as a separate pass, fail, or skip outcome.
- If local `xcodebuild` is blocked by simulator-service or cache-permission issues, `scripts/codex-test-focused.sh` records the Xcode step as skipped instead of misreporting a bad workspace.
- PR CI runs `security_harness.swift`, `controller_endpoint_builder_smoke.swift`, `capability_cache_identity_smoke.swift`, `config_validator_smoke.swift`, `diagnostics_log_reader_smoke.swift`, `diagnostics_artifact_formatter_smoke.swift`, `profile_artifact_metadata_smoke.swift`, `smartx_managed_override_smoke.swift`, `effective_config_generator_smoke.swift`, `helper_status_smoke.swift`, `redactor_smoke.swift`, and `remote_config_decode_smoke.swift`.
- There is not yet a direct standalone smoke harness for `ConnectionAPI` or `DiagnosticsMaintenanceCoordinator`. `ConnectionAPI.swift` currently depends on app models plus Alamofire, and `DiagnosticsMaintenanceCoordinator.swift` depends on app endpoint/result types, so the current lightweight smoke coverage stays focused on the pure `EffectiveConfigGenerator` boundary instead of cloning production logic into test-only shims.
- These harnesses intentionally either compile production files directly, compile production files with small stubs, or keep narrow mirrored legacy coverage. They are still temporary coverage, not a substitute for a real XCTest bundle.

Current temporary-vs-production split:

- `controller_endpoint_builder_smoke.swift`, `redactor_smoke.swift`, `config_validator_smoke.swift`, `diagnostics_log_reader_smoke.swift`, `diagnostics_artifact_formatter_smoke.swift`, and `profile_artifact_metadata_smoke.swift` call production code directly or with minimal compile-only stubs for unrelated app types.
- `smartx_managed_override_smoke.swift` calls production code with small stubs for unrelated app infrastructure.
- `effective_config_generator_smoke.swift` compiles the production `SmartXManagedOverrideModel.swift` plus `EffectiveConfigGenerator.swift` with tiny stubs for unrelated app infrastructure so the branch keeps an honest unsupported result plus provenance boundary until a safe YAML emitter exists.
- `helper_status_smoke.swift` compiles the production `HelperStatus.swift` model directly and only checks serialization plus trust-state messaging. It is diagnostic-model coverage, not a real privileged-helper installation or XPC test.
- `security_harness.swift` remains a temporary mirrored compatibility smoke harness because there is no real XCTest target yet.
- No current smoke harness is intentionally skipped in PR CI. Any future omission should be documented here with the exact reason.
- None of these harnesses replace a dedicated Xcode unit-test bundle; they are focused guardrails until the repo gains one.

New smoke harness coverage added by the SmartX foundation hardening PR:

- `config_validator_smoke.swift` compiles `ConfigValidationIssue.swift`, `TunConfigValidator.swift`, and `DNSConfigValidator.swift` to cover reusable TUN and DNS validation behavior.
- `diagnostics_log_reader_smoke.swift` compiles `SmartXRedactor.swift` and `DiagnosticsLogReader.swift` to cover bounded log tailing, filtering behavior, and redacted export headers.
- `diagnostics_artifact_formatter_smoke.swift` compiles `SmartXRedactor.swift` and `DiagnosticsArtifactFormatter.swift` with tiny metadata/path stubs to cover redacted artifact-preview output in the Diagnostics dashboard.
- `profile_artifact_metadata_smoke.swift` compiles `ProfileArtifactManager.swift` to cover source-copy artifact metadata encoding.
- `smartx_managed_override_smoke.swift` compiles `SmartXManagedOverrideModel.swift` plus `SmartXManagedOverrideManager.swift` with lightweight stubs for unrelated app infrastructure to cover explicit bootstrap, no-hidden-write behavior, future-schema persistence skips, normalization, and migration behavior.
- `effective_config_generator_smoke.swift` compiles `SmartXManagedOverrideModel.swift` plus `EffectiveConfigGenerator.swift` with lightweight stubs to cover the current explicit unsupported result for generated effective config until a safe YAML emitter exists.
- `helper_status_smoke.swift` compiles `HelperStatus.swift` directly to cover helper trust-state names, Codable round trip behavior, and explicit diagnostic-only helper messaging.
- The effective-config smoke must stay honest: it may assert requested override provenance, but it must not claim emitted/generated SmartX overrides until a real safe YAML emitter exists.
- The helper-status smoke must stay honest: it does not prove `SMJobBless`, launchd registration, XPC trust, or real privileged-helper installation.

## CI
- PR CI runs on macOS GitHub Actions via `.github/workflows/pr-ci.yml`.
- CI uses the same `bash install_dependency.sh` path as local setup so dashboard resources, `Country.mmdb.gz`, Pods, and the Go archive are installed the same way in both environments.
- CI builds with code signing disabled (`CODE_SIGNING_ALLOWED=NO`) so it can validate compile/build paths without local certificates.
- PR CI verifies the Release helper client requirement remains fail-closed in a dedicated validation gate before artifact jobs run.
- Every PR now uploads an unsigned Debug app artifact for the current modern build line with Xcode 26.x.
- CI also runs `Tests/SecurityHarness/security_harness.swift`, the endpoint-builder smoke harness, the capability-identity smoke harness, and the config-validator, diagnostics-log-reader, diagnostics-artifact-formatter, profile-artifact-metadata, and SmartX-managed-override smoke harnesses.
- CI also runs the effective-config-generator smoke harness so the branch cannot silently start overclaiming generated effective config support.
- CI does **not** validate notarization, privileged helper installation by SMJobBless, or production signing requirements.
- Local release testing still requires real Apple Developer identities and a follow-up helper identity migration.
- SmartX no longer maintains a dedicated macOS 10.14 CI lane in this branch.

## Workspace readiness
- `ClashX.xcworkspace/contents.xcworkspacedata` is Xcode workspace XML, not a plist.
- `plutil` may reject a valid workspace file because the XML root tag is `Workspace`; that is not evidence of corruption.
- The correct readiness checks are:
  - XML parses successfully
  - the root tag is `Workspace`
  - at least one `FileRef` exists
  - `group:ClashX.xcodeproj` points to an existing `ClashX.xcodeproj`
  - `group:Pods/Pods.xcodeproj` points to an existing `Pods/Pods.xcodeproj` when referenced
  - `xcodebuild -list -workspace "$PWD/ClashX.xcworkspace"` succeeds
- Use `bash scripts/ensure-xcworkspace.sh` before assuming a workspace problem is an Xcode parser bug.
- The normal local repair path is:
  - `bundle install`
  - `bundle exec pod install`
  - `xcodebuild -list -workspace "$PWD/ClashX.xcworkspace"`
- If global Ruby or Homebrew CocoaPods differs from Bundler, prefer `bundle exec pod install` for this repository.
- Project mode is diagnostic only. Do not use `ClashX.xcodeproj` as the normal build or test path, because it can miss Pods integration.
