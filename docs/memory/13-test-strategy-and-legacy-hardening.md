# SmartX Test Strategy and Legacy Hardening

## Current State

SmartX still does not have a dedicated Xcode unit-test bundle wired into the project. That means new infrastructure work must either:

- land with direct XCTest coverage if a target exists
- or use documented pure-logic smoke harnesses without copying production logic

The current repository is still in the second state.

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
- CI does not yet run these harnesses automatically

The long-term target remains a real test bundle with focused unit coverage for endpoint building, capability transitions, and controller result mapping.
