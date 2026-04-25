# SmartX Mihomo API and Capability Memory

## Current API Surface

The `smartx` branch already talks to the mihomo controller in more places than the original ClashX branch, but the current API layer is still endpoint-centric rather than capability-centric. The main integration point is [`ClashX/General/ApiRequest.swift`](../../ClashX/General/ApiRequest.swift), with view controllers such as [`ClashX/ViewControllers/Connections/SmartDashboardViewController.swift`](../../ClashX/ViewControllers/Connections/SmartDashboardViewController.swift) and [`ClashX/ViewControllers/Settings/CoreSettingViewController.swift`](../../ClashX/ViewControllers/Settings/CoreSettingViewController.swift) consuming the results.

### configs

Current config-facing methods include:

- `requestConfig`
- `requestConfigUpdate(configName:)`
- `requestConfigUpdate(configPath:)`
- `updateOutBoundMode`
- `updateLogLevel`
- `updateAllowLan`
- `updateTun`
- `requestCoreVersion`

The implementation uses two modes:

- direct embedded-core access through exported Go bindings such as `clashGetConfigs` and `clashUpdateConfig`
- HTTP controller access through `/configs`, `/version`, and related endpoints

`CoreSettingViewController` also does its own `/configs` read with Alamofire to avoid blank UI when the controller is present but some decode path fails.

### proxies

Current proxy APIs include:

- `requestProxyGroupList` for `/proxies`
- `updateProxyGroup` for `PUT /proxies/:name`
- `getAllProxyList`
- `getMergedProxyData`
- `getProxyDelay`

The proxy model in [`ClashX/Models/ClashProxy.swift`](../../ClashX/Models/ClashProxy.swift) already recognizes newer mihomo proxy and group types such as `Smart`, `Wireguard`, `Hysteria`, `Hysteria2`, `Tuic`, `AnyTLS`, `Masque`, `TrustTunnel`, and `Vless`.

### providers

Current provider APIs include:

- `requestProxyProviderList` for `/providers/proxies`
- `requestExternalProviderNames`
- `updateProvider`
- `healthCheck`

Provider decoding in [`ClashX/Models/ClashProvider.swift`](../../ClashX/Models/ClashProvider.swift) is intentionally tolerant of current mihomo naming differences such as lowercase values and missing provider names.

There is still a legacy split between proxy providers and rule providers. `requestExternalProviderNames` only requests `/providers/rules` under `#if PRO_VERSION`, which no longer matches the real mihomo capability boundary.

### rules

Current rule API coverage is minimal:

- `getRules` for `/rules`

There is no parallel capability or discovery layer for rule providers, script support, or newer rule-related endpoints.

### connections

Current connection APIs include:

- `getConnections`
- `closeConnection`
- `closeAllConnection`
- `blockSmartConnection`

[`ClashX/Models/ClashConnection.swift`](../../ClashX/Models/ClashConnection.swift) has already been extended to carry smart-specific metadata such as:

- `smartBlock`
- `smartTarget`
- GeoIP arrays
- ASN strings

This is enough for a Smart dashboard and richer connection inspection, but it is still layered on top of the existing snapshot-centric connection model.

### logs and traffic

Current stream APIs include:

- `/logs` through WebSocket in `requestLog`
- `/traffic` through WebSocket in `requestTrafficInfo`

`ApiRequest` implements retry timers and reconnect backoff for both streams. There is no current `/memory` integration even though mihomo documents it alongside `/logs` and `/traffic`.

### TUN updates

Current TUN handling is intentionally narrow:

- `updateTun(enable:)` only performs `PATCH /configs` with `{"tun":{"enable":...}}`
- [`ClashX/Models/ClashConfig.swift`](../../ClashX/Models/ClashConfig.swift) only models a subset of the `tun` block: `enable`, `device`, `stack`, `dns-hijack`, and `auto-route`
- `CoreSettingViewController` gates TUN UI separately from helper installation state

This is config-patching support, not end-to-end TUN lifecycle support.

### smart weights

Current Smart APIs include:

- `requestSmartWeights()` for `/group/weights`
- `requestSmartWeights(group:)` for `/group/:name/weights`

`SmartDashboardViewController` uses these endpoints with merged proxy data to render Smart group rankings and currently selected nodes.

### smart cache

Current Smart cache APIs include:

- `flushSmartCache()` for `/cache/smart/flush`
- `flushSmartCache(configName:)` for `/cache/smart/flush/:config`
- `blockSmartConnection(_:)` for `/connections/smart/:id`

These are SmartX-specific integrations and are not part of the generic mihomo controller surface.

### LightGBM update

Current LightGBM update coverage is:

- `updateSmartLightGBMModel()` for `POST /upgrade/lgbm`

The result is normalized into `SmartEndpointResult` with three buckets:

- `.success`
- `.unsupported`
- `.failed`

This is used by both `SmartDashboardViewController` and `CoreSettingViewController` to keep the UI honest when the current controller does not expose the endpoint.

### core version

Current version handling is:

- `requestCoreVersion()` for `GET /version`
- embedded bundle metadata via `Settings.embeddedCoreVersion`, `embeddedCoreCommit`, `embeddedCoreBranch`, and `embeddedCoreBuildTime` in [`ClashX/General/Managers/Settings.swift`](../../ClashX/General/Managers/Settings.swift)

That means SmartX already has two version concepts:

- runtime controller version from `/version`
- bundled embedded-core metadata from `Info.plist`

## Missing or Partial API Areas

Using the current mihomo API docs as a conceptual reference, SmartX still has clear gaps relative to a mature modern client.

### `/memory` websocket or polling

The official API groups `/memory` with `/logs` and `/traffic`, but `ApiRequest.swift` currently implements only the latter two. SmartX therefore has no direct memory telemetry for the embedded core or an external controller.

### `/cache/dns/flush`

SmartX implements `/cache/fakeip/flush` in `resetFakeIpCache`, but not `/cache/dns/flush`. That means cache maintenance coverage is asymmetric even though mihomo exposes both.

### `/configs/geo`

There is no client method for `POST /configs/geo`. GEO database refresh still appears to be handled outside the general controller API layer.

### `/restart`

There is no API helper for `POST /restart`, so SmartX cannot explicitly request a core restart through the controller layer.

### `/upgrade`

There is no general `POST /upgrade` helper for kernel updates. SmartX currently has only the Smart-specific `POST /upgrade/lgbm` path.

### `/upgrade/ui`

There is no `POST /upgrade/ui` helper even though the branch still depends on downloaded dashboard assets.

### `/upgrade/geo`

There is no `POST /upgrade/geo` helper.

### `/group` and `/group/:name`

SmartX uses Smart-specific `/group/weights` endpoints, but it does not expose the documented generic policy-group API surface:

- `GET /group`
- `GET /group/:name`
- `DELETE /group/:name`
- `GET /group/:name/delay`

This matters because future cores may support richer group metadata even when they do not support Smart weights.

### `/providers/rules` without `PRO_VERSION` gating

Rule-provider discovery still depends on the historical `PRO_VERSION` macro in `requestExternalProviderNames`. For modern mihomo controllers, this should be treated as endpoint capability, not as product-tier capability.

### `/dns/query`

There is no DNS query helper for `GET /dns/query`. That limits future DNS diagnostics and makes DNS support harder to surface in the UI.

### `/debug/gc`

There is no API helper for `PUT /debug/gc`.

### `/debug/pprof` browser helpers

There is no helper or developer tooling path for opening or explaining `/debug/pprof` outputs. That is reasonable for now, but it is still a gap relative to modern mihomo observability.

## Capability Map Design

The current client mostly assumes features from branch history, compile-time macros, or individual HTTP status codes. That is already becoming brittle. SmartX should move toward an explicit capability map that describes what the active core can do, independent of whether it is embedded or external.

### CoreCapability

`CoreCapability` should be a Swift-side enumeration or identifier set that represents user-facing features rather than raw endpoints. Example categories:

- configRead
- configPatch
- configReload
- proxyProviders
- ruleProviders
- logsStream
- trafficStream
- memoryStream
- tunConfigRead
- tunGuardedUpdate
- smartWeights
- smartCacheFlush
- smartConnectionBlock
- lightGBMUpgrade
- dnsCacheFlush
- dnsQuery
- geoUpdate
- uiUpgrade
- coreUpgrade
- restart
- debugGC
- debugPprof

The important point is that a capability should mean “this client can safely expose this feature,” not merely “an endpoint name exists in docs.”

### CoreEndpointAvailability

`CoreEndpointAvailability` should capture how confident SmartX is about each endpoint. Suggested states:

- available
- unavailable
- unauthorized
- unsupported
- unknown
- degraded

This is more expressive than a single boolean and helps the UI distinguish “controller stopped,” “secret rejected,” and “endpoint not implemented.”

### CoreFeatureProbe

`CoreFeatureProbe` should define how SmartX tests capabilities. Different features need different probes:

- passive probe from `/version`
- passive probe from `/configs`
- optimistic write probe with rollback, such as current guarded TUN patch behavior
- status-code-based probe for upgrade endpoints
- WebSocket connect probe for stream endpoints
- model-based probe when response shape is the real compatibility risk

The key rule is that probes should be safe. They should not mutate user state unless the feature explicitly supports a guarded write-and-restore pattern.

### CapabilityCache

`CapabilityCache` should hold the probe results for the active controller identity. Cache keys should likely include:

- controller URL
- auth secret identity, or a secret-hash surrogate
- embedded vs external mode
- core version string
- optional branch/commit metadata when available

The cache should expire when:

- controller mode changes
- version changes
- authentication changes
- a probe returns a contradictory result

This avoids repeatedly probing unsupported endpoints while still allowing capability changes after a core switch or upgrade.

## Why Capability Detection Matters

`smartx` is no longer a single fixed-core client. The branch already distinguishes:

- embedded core mode via `Settings.isUsingEmbeddedCore`
- external controller mode via `ConfigManager.apiUrl` and `RemoteControlManager.selectConfig`

The future branch direction is even broader:

- embedded Smart core
- external mihomo stable
- external alpha core
- user-supplied controller/core

Because of that, UI decisions should be driven by detected capabilities instead of legacy assumptions such as:

- “Pro feature”
- “embedded means full support”
- “presence of a `tun` block means TUN is operational”
- “Smart endpoints exist everywhere”

The current `CoreSettingViewController` already moves in this direction for TUN and LightGBM. The next step is to generalize that pattern across the API layer.

## PRO_VERSION Cleanup

Legacy `PRO_VERSION` assumptions are now one of the biggest architectural mismatches in the branch.

### Rule providers

In [`ClashX/General/ApiRequest.swift`](../../ClashX/General/ApiRequest.swift), `/providers/rules` is still requested only under `#if PRO_VERSION`. That made sense in the older ClashX product split, but it conflicts with modern mihomo behavior where rule providers are normal controller features.

### Script assumptions

[`ClashX/Models/ClashConfig.swift`](../../ClashX/Models/ClashConfig.swift) still puts `.script` mode behind `#if PRO_VERSION`. That is another example where product-tier history may not match current core capability. If the active core reports script mode through `/configs`, the client should decide from capability and response data, not compile-time branding.

### Practical cleanup direction

The branch should gradually replace `PRO_VERSION` UI/API feature gating with:

- runtime capability checks
- endpoint availability checks
- response-shape checks
- explicit unsupported-state UI

That cleanup does not need to happen in one PR, but the memory docs should record that the old macro boundary is no longer a trustworthy feature boundary.

## Error Handling Policy

A mature mihomo API layer should treat failures by category instead of collapsing them into “request failed.”

### Unsupported endpoints

When an endpoint returns a strong unsupported signal, such as `404` or a known compatibility `400`, SmartX should:

- mark the feature as unsupported in the capability cache
- disable the related control
- show explanatory UI instead of a blank area

The current LightGBM update flow in `CoreSettingViewController` is already close to this model.

### Failed endpoints

When a supported endpoint fails transiently, SmartX should:

- keep the feature in a degraded state
- preserve previous UI state when writes fail
- log status code and controller message when safe
- avoid inventing success

The current guarded TUN update pattern is the right direction.

### Authentication errors

Authentication failures should be surfaced distinctly from unsupported features. A controller that returns `401` or `403` is not the same as a controller that lacks an endpoint.

### Controller unavailable

When the controller is stopped or unreachable, SmartX should:

- keep placeholder UI visible
- report “not connected” or “controller unavailable”
- avoid probing deeper endpoints until base connectivity recovers

`CoreSettingViewController` already does this better than earlier iterations by preserving visible fallback rows.

### Stale core state

When SmartX falls back to cached app state because `/configs` or `/version` is unavailable, the UI should say that explicitly. Cached state is useful, but it is not proof that the active controller still matches the cached config.

## Acceptance Criteria

SmartX has a mature mihomo API layer when all of the following are true:

- The active controller mode is explicit: embedded, external, or unavailable.
- Feature availability is derived from runtime capability detection rather than `PRO_VERSION` or historical assumptions.
- Unsupported endpoints disable only the affected controls, not the entire page or dashboard.
- Authentication failures, transport failures, unsupported features, and stale cached state are reported differently.
- Smart-specific endpoints are treated as optional capabilities, not universal mihomo behavior.
- Rule providers are no longer hidden behind product-tier macros when the active controller exposes them.
- Stream APIs cover logs, traffic, and memory, or the missing pieces are explicitly tracked as unsupported.
- Diagnostic tooling can explain why a feature is disabled without leaking config content, subscription URLs, credentials, or secrets.
- The UI can survive switching among embedded Smart core, external stable/alpha cores, and user-supplied controllers without hard-coded feature assumptions.

## Source of Truth

This document is descriptive, not normative. The current implementation is defined by the source files in this repository, especially [`ClashX/General/ApiRequest.swift`](../../ClashX/General/ApiRequest.swift) and the associated models and view controllers. Update this memory document when the API layer or capability strategy changes.
