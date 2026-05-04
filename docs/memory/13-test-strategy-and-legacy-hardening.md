# SmartX Test Strategy and Legacy Hardening

## Current State

SmartX still does not have a dedicated Xcode unit-test bundle wired into the project. That means new infrastructure work must either:

- land with direct XCTest coverage if a target exists
- or use documented pure-logic smoke harnesses without copying production logic

The current repository is still in the second state.

## Current CI Lanes

PR CI now uses two unsigned Debug build lanes plus a shared validation gate:

- Legacy lane: `macos-15` + Xcode `16.4` + `MACOSX_DEPLOYMENT_TARGET=10.14`
- Modern lane: `macos-26` + Xcode `26.x`
- Validation gate: helper fail-closed build-settings check plus pure-logic smoke harnesses

Every PR uploads unsigned SmartX app zip artifacts and `.ci-logs` for the Legacy and Modern lanes.

Artifact upload does **not** imply:

- signing is valid
- notarization is valid
- helper installation works
- runtime compatibility is proven on the target OS

## What This PR Added

For the controller API foundation work, SmartX now has two additional pure-logic harnesses under [`Tests/SecurityHarness`](../../Tests/SecurityHarness):

- `controller_endpoint_builder_smoke.swift` exercises `ControllerEndpointBuilder` against embedded and external controller bases, WebSocket conversion, query items, trailing-slash handling, query/fragment stripping, and userinfo stripping.
- `capability_cache_identity_smoke.swift` checks that `CapabilityCache` controller identity keeps the sanitized controller base and `secret-set` marker without leaking raw controller secrets, URL userinfo, or query strings.

These harnesses compile the production files directly with lightweight stubs for app-global state. That keeps the tested logic real while avoiding a second copied implementation.

## How To Run

Local commands:

- `swiftc ClashX/General/Utils/ControllerEndpointBuilder.swift Tests/SecurityHarness/controller_endpoint_builder_smoke.swift -o /tmp/controller-endpoint-builder-smoke && /tmp/controller-endpoint-builder-smoke`
- `swiftc ClashX/General/Utils/ControllerEndpointBuilder.swift ClashX/General/Managers/CoreCapability.swift Tests/SecurityHarness/capability_cache_identity_smoke.swift -o /tmp/capability-cache-identity-smoke && /tmp/capability-cache-identity-smoke`

These are meant for utility-level verification when changing endpoint composition or capability identity handling.

## Remaining Gaps

- There is still no real XCTest coverage for controller endpoint construction, capability probing, or Smart endpoint result mapping.
- The smoke harnesses do not exercise the full app target, Alamofire request execution, or AppKit controller wiring.
- `CoreCapabilityProbe` currently depends on the app request layer and would benefit from later extraction into more directly testable probe helpers.

## Why The Harnesses Are Temporary

The current approach is useful because it verifies the production files directly, but it is still a stopgap:

- harness stubs only cover the pure-logic seams, not the full runtime environment
- failure reporting is shell-level, not Xcode test reporting
- CI now runs these harnesses automatically, but they are still smoke coverage rather than a real XCTest bundle

## Legacy Compatibility Boundary

- The Legacy CI lane validates that SmartX still compiles with Xcode `16.4` and `MACOSX_DEPLOYMENT_TARGET=10.14`.
- That compile success does **not** prove the app actually runs correctly on a real macOS `10.14` machine.
- GitHub-hosted runners do not provide genuine macOS `10.14` runtime validation, so true legacy runtime checks still require external hardware or a VM.

The long-term target remains a real test bundle with focused unit coverage for endpoint building, capability transitions, and controller result mapping.
