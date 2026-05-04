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

- `controller_endpoint_builder_smoke.swift` exercises `ControllerEndpointBuilder` against embedded and external controller bases, WebSocket conversion, query items, trailing-slash handling, query/fragment stripping, and userinfo stripping.
- `capability_cache_identity_smoke.swift` checks that `CapabilityCache` controller identity keeps the sanitized controller base and `secret-set` marker without leaking raw controller secrets, URL userinfo, or query strings.
- `smartx_managed_override_smoke.swift` exercises explicit bootstrap, no-hidden-write behavior for the effective model URL getter, managed-override persistence, legacy UserDefaults migration, future-schema skip behavior, normalization of invalid model URLs, and interval clamping for the initial LightGBM override groundwork.
- `config_validator_smoke.swift` exercises the reusable TUN and DNS validators without duplicating the production validation rules, including nil-input handling and invalid IPv6 CIDR prefixes.
- `diagnostics_log_reader_smoke.swift` exercises the diagnostics log tail reader so large rolling log files do not require full synchronous reads every refresh cycle.
- `profile_artifact_metadata_smoke.swift` exercises `ProfileArtifactMetadata` encoding so source-copy artifact semantics stay stable while the real generated effective config pipeline is still pending, including the false override/merge/runtime flags that keep the current artifacts honest.
- `effective_config_generator_smoke.swift` exercises the current `EffectiveConfigGenerator` boundary so SmartX keeps an explicit unsupported result until a safe YAML emitter exists for base config plus managed LightGBM override generation.

These harnesses compile the production files directly with lightweight stubs for app-global state. That keeps the tested logic real while avoiding a second copied implementation.
High coverage has not been achieved in this branch, and XCTest migration remains follow-up work.

## How To Run

Local commands:

- `swiftc ClashX/General/Utils/ControllerEndpointBuilder.swift Tests/SecurityHarness/controller_endpoint_builder_smoke.swift -o /tmp/controller-endpoint-builder-smoke && /tmp/controller-endpoint-builder-smoke`
- `swiftc ClashX/General/Utils/ControllerEndpointBuilder.swift ClashX/General/Managers/CoreCapability.swift Tests/SecurityHarness/capability_cache_identity_smoke.swift -o /tmp/capability-cache-identity-smoke && /tmp/capability-cache-identity-smoke`
- `swiftc ClashX/General/Managers/SmartXManagedOverrideManager.swift Tests/SecurityHarness/smartx_managed_override_smoke.swift -o /tmp/smartx-managed-override-smoke && /tmp/smartx-managed-override-smoke`
- `swiftc ClashX/General/Utils/ConfigValidationIssue.swift ClashX/General/Utils/TunConfigValidator.swift ClashX/General/Utils/DNSConfigValidator.swift Tests/SecurityHarness/config_validator_smoke.swift -o /tmp/config-validator-smoke && /tmp/config-validator-smoke`
- `swiftc ClashX/General/Utils/DiagnosticsLogReader.swift Tests/SecurityHarness/diagnostics_log_reader_smoke.swift -o /tmp/diagnostics-log-reader-smoke && /tmp/diagnostics-log-reader-smoke`
- `swiftc ClashX/General/Managers/ProfileArtifactManager.swift Tests/SecurityHarness/profile_artifact_metadata_smoke.swift -o /tmp/profile-artifact-metadata-smoke && /tmp/profile-artifact-metadata-smoke`
- `swiftc ClashX/General/Managers/EffectiveConfigGenerator.swift Tests/SecurityHarness/effective_config_generator_smoke.swift -o /tmp/effective-config-generator-smoke && /tmp/effective-config-generator-smoke`

These are meant for utility-level verification when changing endpoint composition or capability identity handling.

## Remaining Gaps

- There is still no real XCTest coverage for controller endpoint construction, capability probing, override persistence, diagnostics log tailing, config-validation transitions, or effective-config generation behavior.
- The smoke harnesses do not exercise the full app target, Alamofire request execution, or AppKit controller wiring.
- `CoreCapabilityProbe` currently depends on the app request layer and would benefit from later extraction into more directly testable probe helpers.

## Why The Harnesses Are Temporary

The current approach is useful because it verifies the production files directly, but it is still a stopgap:

- harness stubs only cover the pure-logic seams, not the full runtime environment
- failure reporting is shell-level, not Xcode test reporting
- CI now runs these harnesses automatically, but they are still smoke coverage rather than a real XCTest bundle

## Legacy Compatibility Boundary

- This branch no longer keeps a dedicated macOS `10.14` compile lane in CI, and SmartX no longer claims active macOS `10.14` support after the CI failure on `CryptoKit.SHA256`.

The long-term target remains a real test bundle with focused unit coverage for endpoint building, capability transitions, and controller result mapping.
