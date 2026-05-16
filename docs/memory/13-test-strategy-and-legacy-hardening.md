# SmartX Test Strategy and Legacy Hardening

## Current State

SmartX still does not have a dedicated Xcode unit-test bundle wired into the project. That means new infrastructure work must either:

- land with direct XCTest coverage if a target exists
- or use documented pure-logic smoke harnesses without copying production logic

The current repository is still in the second state.

## Current CI Lanes

PR CI now uses one unsigned Debug build lane plus a shared validation gate:

- Modern lane: `macos-26` + Xcode `26.x`
- Validation gate: helper fail-closed build-settings check plus pure-logic smoke harnesses

Every PR uploads an unsigned SmartX app zip artifact and `.ci-logs` for the Modern lane.

Artifact upload does **not** imply:

- signing is valid
- notarization is valid
- helper installation works
- runtime compatibility is proven on the target OS

## What This PR Added

For the controller API foundation and SmartX hardening work, SmartX now has several pure-logic harnesses under [`Tests/SecurityHarness`](../../Tests/SecurityHarness):

- `controller_endpoint_builder_smoke.swift`: direct production compile of `ControllerEndpointBuilder.swift`.
- `capability_cache_identity_smoke.swift`: direct production compile of `ControllerEndpointBuilder.swift` plus `CoreCapability.swift`.
- `smartx_managed_override_smoke.swift`: production compile of `SmartXManagedOverrideManager.swift` with lightweight stubs for unrelated app infrastructure.
- `config_validator_smoke.swift`: direct production compile of `ConfigValidationIssue.swift`, `TunConfigValidator.swift`, and `DNSConfigValidator.swift`.
- `diagnostics_log_reader_smoke.swift`: direct production compile of `SmartXRedactor.swift` and `DiagnosticsLogReader.swift`.
- `diagnostics_artifact_formatter_smoke.swift`: production compile of `SmartXRedactor.swift` and `DiagnosticsArtifactFormatter.swift` with small compile-only stubs for unrelated metadata types.
- `profile_artifact_metadata_smoke.swift`: direct production compile of `ProfileArtifactManager.swift`.
- `effective_config_generator_smoke.swift`: production compile of `SmartXManagedOverrideModel.swift` plus `EffectiveConfigGenerator.swift` with lightweight stubs for unrelated app infrastructure, and the result must remain explicitly unsupported until a safe YAML emitter exists.
- `helper_status_smoke.swift`: direct production compile of `HelperStatus.swift`.
- `helper_command_contract_smoke.swift`: direct production compile of `HelperCommandContract.swift` plus `HelperCommandRegistry.swift`.
- `tun_lifecycle_diagnostics_smoke.swift`: production compile of `TunLifecycleDiagnostics.swift` plus `TunPreflightPlanner.swift` with lightweight stubs for unrelated app/runtime types.
- `redactor_smoke.swift`: direct production compile of `SmartXRedactor.swift`.
- `remote_config_decode_smoke.swift`: direct production compile of `RemoteConfigModel.swift`.
- `security_harness.swift`: mirrored compatibility smoke only, not a direct production compile.

These harnesses compile the production files directly with lightweight stubs for app-global state. That keeps the tested logic real while avoiding a second copied implementation.
High coverage has not been achieved in this branch, and XCTest migration remains follow-up work.

## How To Run

Local commands:

- `swiftc ClashX/General/Utils/ControllerEndpointBuilder.swift Tests/SecurityHarness/controller_endpoint_builder_smoke.swift -o /tmp/controller-endpoint-builder-smoke && /tmp/controller-endpoint-builder-smoke`
- `swiftc ClashX/General/Utils/ControllerEndpointBuilder.swift ClashX/General/Managers/CoreCapability.swift Tests/SecurityHarness/capability_cache_identity_smoke.swift -o /tmp/capability-cache-identity-smoke && /tmp/capability-cache-identity-smoke`
- `swiftc ClashX/Models/SmartXManagedOverrideModel.swift ClashX/General/Managers/SmartXManagedOverrideManager.swift Tests/SecurityHarness/smartx_managed_override_smoke.swift -o /tmp/smartx-managed-override-smoke && /tmp/smartx-managed-override-smoke`
- `swiftc ClashX/General/Utils/ConfigValidationIssue.swift ClashX/General/Utils/TunConfigValidator.swift ClashX/General/Utils/DNSConfigValidator.swift Tests/SecurityHarness/config_validator_smoke.swift -o /tmp/config-validator-smoke && /tmp/config-validator-smoke`
- `swiftc ClashX/General/Utils/SmartXRedactor.swift ClashX/General/Utils/DiagnosticsLogReader.swift Tests/SecurityHarness/diagnostics_log_reader_smoke.swift -o /tmp/diagnostics-log-reader-smoke && /tmp/diagnostics-log-reader-smoke`
- `swiftc ClashX/General/Utils/SmartXRedactor.swift ClashX/General/Utils/DiagnosticsArtifactFormatter.swift Tests/SecurityHarness/diagnostics_artifact_formatter_smoke.swift -o /tmp/diagnostics-artifact-formatter-smoke && /tmp/diagnostics-artifact-formatter-smoke`
- `swiftc ClashX/General/Managers/ProfileArtifactManager.swift Tests/SecurityHarness/profile_artifact_metadata_smoke.swift -o /tmp/profile-artifact-metadata-smoke && /tmp/profile-artifact-metadata-smoke`
- `swiftc ClashX/Models/SmartXManagedOverrideModel.swift ClashX/General/Managers/EffectiveConfigGenerator.swift Tests/SecurityHarness/effective_config_generator_smoke.swift -o /tmp/effective-config-generator-smoke && /tmp/effective-config-generator-smoke`
- `swiftc ClashX/Models/HelperStatus.swift Tests/SecurityHarness/helper_status_smoke.swift -o /tmp/helper-status-smoke && /tmp/helper-status-smoke`
- `swiftc ClashX/Models/HelperCommandContract.swift ClashX/General/Utils/HelperCommandRegistry.swift Tests/SecurityHarness/helper_command_contract_smoke.swift -o /tmp/helper-command-contract-smoke && /tmp/helper-command-contract-smoke`
- `swiftc ClashX/General/Utils/ConfigValidationIssue.swift ClashX/General/Utils/TunConfigValidator.swift ClashX/General/Utils/DNSConfigValidator.swift ClashX/Models/HelperStatus.swift ClashX/Models/HelperCommandContract.swift ClashX/General/Utils/HelperCommandRegistry.swift ClashX/Models/TunLifecycleDiagnostics.swift ClashX/General/Managers/TunPreflightPlanner.swift Tests/SecurityHarness/tun_lifecycle_diagnostics_smoke.swift -o /tmp/tun-lifecycle-diagnostics-smoke && /tmp/tun-lifecycle-diagnostics-smoke`
- `swiftc ClashX/General/Utils/SmartXRedactor.swift Tests/SecurityHarness/redactor_smoke.swift -o /tmp/redactor-smoke && /tmp/redactor-smoke`
- `swiftc ClashX/Models/RemoteConfigModel.swift Tests/SecurityHarness/remote_config_decode_smoke.swift -o /tmp/remote-config-decode-smoke && /tmp/remote-config-decode-smoke`
- `swift -module-cache-path /private/tmp/swift-module-cache Tests/SecurityHarness/security_harness.swift`

These are meant for utility-level verification when changing endpoint composition or capability identity handling.

## Remaining Gaps

- There is still no real XCTest coverage for controller endpoint construction, capability probing, override persistence, diagnostics log tailing, config-validation transitions, or effective-config generation behavior.
- The smoke harnesses do not exercise the full app target, Alamofire request execution, or AppKit controller wiring.
- The effective-config smoke now verifies shared production model wiring, but it still does not prove a generated effective-config pipeline because the generator remains explicitly unsupported.
- The helper-status smoke does not prove `SMJobBless`, launchd registration, XPC trust, or privileged-helper installation. It only protects the diagnostic model boundary.
- The helper-command-contract smoke does not prove helper XPC execution, system proxy mutation, helper blessing, or any TUN lifecycle. It only protects the typed contract and reserved-command boundary.
- The TUN lifecycle diagnostics smoke does not prove route verification, utun creation, packet flow, DNS runtime verification, or helper-backed TUN execution. It only protects the typed diagnostics boundary and controller-config-only verification model.
- `CoreCapabilityProbe` currently depends on the app request layer and would benefit from later extraction into more directly testable probe helpers.

## Why The Harnesses Are Temporary

The current approach is useful because it verifies the production files directly, but it is still a stopgap:

- harness stubs only cover the pure-logic seams, not the full runtime environment
- failure reporting is shell-level, not Xcode test reporting
- CI now runs these harnesses automatically in the unsigned validation gate, but they are still smoke coverage rather than a real XCTest bundle
- unsigned PR artifacts remain manual-testing artifacts only; they do not imply signing or notarization readiness
- DMG Finder layout metadata remains best-effort for unsigned CI artifacts; a clean fallback DMG without `.DS_Store` is acceptable and should not be treated as packaging failure

## Legacy Compatibility Boundary

- This branch no longer keeps a dedicated macOS `10.14` compile lane in CI, and SmartX no longer claims active macOS `10.14` support after the CI failure on `CryptoKit.SHA256`.

The long-term target remains a real test bundle with focused unit coverage for endpoint building, capability transitions, and controller result mapping.
