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
- `Tests/SecurityHarness/security_harness.swift` is a temporary CI smoke test. It now mirrors the current production SHA256 fallback naming and suggested-filename validation semantics, but it does not replace a real XCTest target.
- SmartX redaction currently has no dedicated XCTest target either. For the `codex/goal-may26-01` stabilization PR, the production redactor was kept in app code and the gap remains documented here rather than cloning that logic into another standalone harness.
- A minimal local smoke check for the production redactor is available at `Tests/SecurityHarness/redactor_smoke.swift` and should be run with `swiftc ClashX/General/Utils/SmartXRedactor.swift Tests/SecurityHarness/redactor_smoke.swift -o /tmp/smartx-redactor-smoke && /tmp/smartx-redactor-smoke` when touching diagnostics redaction behavior.
- A minimal local upgrade-compatibility check for persisted remote profiles is available at `Tests/SecurityHarness/remote_config_decode_smoke.swift` and should be run with `swiftc ClashX/Models/RemoteConfigModel.swift Tests/SecurityHarness/remote_config_decode_smoke.swift -o /tmp/remote-config-decode-smoke && /tmp/remote-config-decode-smoke` when changing `RemoteConfigModel` coding behavior.
- A minimal local endpoint-builder smoke check is available at `Tests/SecurityHarness/controller_endpoint_builder_smoke.swift` and should be run with `swiftc ClashX/General/Utils/ControllerEndpointBuilder.swift Tests/SecurityHarness/controller_endpoint_builder_smoke.swift -o /tmp/controller-endpoint-builder-smoke && /tmp/controller-endpoint-builder-smoke` when changing controller URL construction.
- That smoke harness now covers raw dynamic path components with spaces, Chinese characters, slashes, literal percent signs, and the `Proxy A` double-encoding regression.
- A minimal local capability-identity smoke check is available at `Tests/SecurityHarness/capability_cache_identity_smoke.swift` and should be run with `swiftc ClashX/General/Utils/ControllerEndpointBuilder.swift ClashX/General/Managers/CoreCapability.swift Tests/SecurityHarness/capability_cache_identity_smoke.swift -o /tmp/capability-cache-identity-smoke && /tmp/capability-cache-identity-smoke` when changing controller identity or capability-cache sanitization.
- A minimal local SmartX managed-override smoke check is available at `Tests/SecurityHarness/smartx_managed_override_smoke.swift` and should be run with `swiftc ClashX/General/Managers/SmartXManagedOverrideManager.swift Tests/SecurityHarness/smartx_managed_override_smoke.swift -o /tmp/smartx-managed-override-smoke && /tmp/smartx-managed-override-smoke` when changing persisted LightGBM override storage, normalization, future-schema warning behavior, or legacy migration behavior.
- A minimal local config-validator smoke check is available at `Tests/SecurityHarness/config_validator_smoke.swift` and should be run with `swiftc ClashX/General/Utils/ConfigValidationIssue.swift ClashX/General/Utils/TunConfigValidator.swift ClashX/General/Utils/DNSConfigValidator.swift Tests/SecurityHarness/config_validator_smoke.swift -o /tmp/config-validator-smoke && /tmp/config-validator-smoke` when changing the reusable TUN or DNS validation rules.
- A minimal local diagnostics-log-reader smoke check is available at `Tests/SecurityHarness/diagnostics_log_reader_smoke.swift` and should be run with `swiftc ClashX/General/Utils/SmartXRedactor.swift ClashX/General/Utils/DiagnosticsLogReader.swift Tests/SecurityHarness/diagnostics_log_reader_smoke.swift -o /tmp/diagnostics-log-reader-smoke && /tmp/diagnostics-log-reader-smoke` when changing log tailing, filtering, or display limits for diagnostics.
- A minimal local profile-artifact metadata smoke check is available at `Tests/SecurityHarness/profile_artifact_metadata_smoke.swift` and should be run with `swiftc ClashX/General/Managers/ProfileArtifactManager.swift Tests/SecurityHarness/profile_artifact_metadata_smoke.swift -o /tmp/profile-artifact-metadata-smoke && /tmp/profile-artifact-metadata-smoke` when changing artifact metadata shape or source-copy semantics.
- These harnesses intentionally either compile production files directly, compile production files with small stubs, or keep narrow mirrored legacy coverage. They are still temporary coverage, not a substitute for a real XCTest bundle.

Current temporary-vs-production split:

- `controller_endpoint_builder_smoke.swift`, `redactor_smoke.swift`, `config_validator_smoke.swift`, `diagnostics_log_reader_smoke.swift`, and `profile_artifact_metadata_smoke.swift` call production code directly.
- `smartx_managed_override_smoke.swift` calls production code with small stubs for unrelated app infrastructure.
- `security_harness.swift` remains a temporary mirrored compatibility smoke harness because there is no real XCTest target yet.
- None of these harnesses replace a dedicated Xcode unit-test bundle; they are focused guardrails until the repo gains one.

New smoke harness coverage added by the SmartX foundation hardening PR:

- `config_validator_smoke.swift` compiles `ConfigValidationIssue.swift`, `TunConfigValidator.swift`, and `DNSConfigValidator.swift` to cover reusable TUN and DNS validation behavior.
- `diagnostics_log_reader_smoke.swift` compiles `SmartXRedactor.swift` and `DiagnosticsLogReader.swift` to cover bounded log tailing, filtering behavior, and redacted export headers.
- `profile_artifact_metadata_smoke.swift` compiles `ProfileArtifactManager.swift` to cover source-copy artifact metadata encoding.
- `smartx_managed_override_smoke.swift` compiles `SmartXManagedOverrideManager.swift` with lightweight stubs for unrelated app infrastructure to cover managed-override persistence, normalization, and migration behavior.

## CI
- PR CI runs on macOS GitHub Actions via `.github/workflows/pr-ci.yml`.
- CI uses the same `bash install_dependency.sh` path as local setup so dashboard resources, `Country.mmdb.gz`, Pods, and the Go archive are installed the same way in both environments.
- CI builds with code signing disabled (`CODE_SIGNING_ALLOWED=NO`) so it can validate compile/build paths without local certificates.
- PR CI verifies the Release helper client requirement remains fail-closed in a dedicated validation gate before artifact jobs run.
- Every PR now uploads unsigned Debug app artifacts for two lanes:
  - Legacy: macOS deployment-target compile check with Xcode 16.4 and `MACOSX_DEPLOYMENT_TARGET=10.14`
  - Modern: current unsigned build line with Xcode 26.x
- CI also runs `Tests/SecurityHarness/security_harness.swift`, the endpoint-builder smoke harness, the capability-identity smoke harness, and the new config-validator, diagnostics-log-reader, profile-artifact-metadata, and SmartX-managed-override smoke harnesses.
- CI does **not** validate notarization, privileged helper installation by SMJobBless, or production signing requirements.
- Local release testing still requires real Apple Developer identities and a follow-up helper identity migration.
- The Legacy artifact is only a deployment-target compile check for macOS 10.14. It does **not** prove runtime behavior on a real macOS 10.14 system.
- True macOS 10.14 runtime validation still requires a real 10.14 machine or VM outside GitHub-hosted runners.
