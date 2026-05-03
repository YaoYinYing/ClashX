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
- `/memory` through polling in `requestMemorySnapshot`

`ApiRequest` implements retry timers and reconnect backoff for the log and traffic streams. Memory diagnostics currently use a simpler polling helper and diagnostics panel rather than a persistent stream.

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

### `/memory` websocket vs polling

SmartX now exposes `/memory` through `requestMemorySnapshot(...)` and the Diagnostics dashboard, but it still does not implement a dedicated memory WebSocket or a historical memory timeline.

### `/cache/dns/flush`

SmartX now exposes `/cache/dns/flush` through `resetDNSCache(...)` alongside the existing fake-IP cache flush path.

### `/configs/geo`

SmartX now exposes `POST /configs/geo` through `reloadGeoDatabase(...)`. This is currently used as a diagnostics/recovery action rather than as part of a larger GEO asset-management workflow.

### `/restart`

SmartX now exposes `POST /restart` through `restartCore(...)`.

### `/upgrade`

There is no general `POST /upgrade` helper for kernel updates. SmartX currently has only the Smart-specific `POST /upgrade/lgbm` path.

### `/upgrade/ui`

SmartX now exposes `POST /upgrade/ui` through `updateDashboardAssets(...)`.

### `/upgrade/geo`

SmartX now exposes `POST /upgrade/geo` through `updateGeoAssets(...)`.

### `/group` and `/group/:name`

SmartX now exposes the documented generic policy-group API surface in addition to Smart-specific `/group/weights` endpoints:

- `GET /group`
- `GET /group/:name`
- `DELETE /group/:name`
- `GET /group/:name/delay`

The current wrappers return raw JSON diagnostics rather than dedicated Swift models, but they are enough to probe capability and inspect controller responses.

### `/providers/rules` without `PRO_VERSION` gating

Rule-provider discovery still depends on the historical `PRO_VERSION` macro in `requestExternalProviderNames`. For modern mihomo controllers, this should be treated as endpoint capability, not as product-tier capability.

### `/dns/query`

SmartX now exposes `GET /dns/query` through `requestDNSQuery(...)` and surfaces it in the Diagnostics dashboard.

### `/debug/gc`

SmartX now exposes `PUT /debug/gc` through `runDebugGC(...)`.

### `/debug/pprof` browser helpers

There is no helper or developer tooling path for opening or explaining `/debug/pprof` outputs. That is reasonable for now, but it is still a gap relative to modern mihomo observability.

## Capability Map Design

The current client mostly assumes features from branch history, compile-time macros, or individual HTTP status codes. That is already becoming brittle. SmartX has now started this transition with a lightweight capability cache, but the broader probe architecture is still incomplete.

### CoreCapability

[`ClashX/General/Managers/CoreCapability.swift`](../../ClashX/General/Managers/CoreCapability.swift) now provides a first-pass `CoreCapability` enum that represents user-facing features rather than raw endpoints. Current categories include:

- configRead
- configPatch
- configReload
- proxyProviders
- ruleProviders
- logsStream
- trafficStream
- memorySnapshot
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
- restart
- debugGC
- debugPprof

The important point is that a capability should mean “this client can safely expose this feature,” not merely “an endpoint name exists in docs.”

### CoreEndpointAvailability

`CoreEndpointAvailability` is now implemented and currently uses these states:

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

`CapabilityCache` now holds in-memory probe results for the active controller identity. The current identity includes:

- controller URL
- auth secret identity, or a secret-hash surrogate
- embedded vs external mode
- controller running state

The current cache resets when the active identity changes. It does not yet key on core version or branch metadata, so this is still an intermediate implementation.

The cache should eventually expire when:

- controller mode changes
- version changes
- authentication changes
- a probe returns a contradictory result

This already avoids repeatedly probing obviously unsupported or unauthorized endpoints in the UI, while still allowing capability changes after a controller switch.

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

The current implementation now uses capability state in:

- [`ClashX/ViewControllers/Settings/CoreSettingViewController.swift`](../../ClashX/ViewControllers/Settings/CoreSettingViewController.swift) for config, TUN, and LightGBM endpoint state
- [`ClashX/ViewControllers/Connections/SmartDashboardViewController.swift`](../../ClashX/ViewControllers/Connections/SmartDashboardViewController.swift) for Smart weights, cache flush, and LightGBM controls
- [`ClashX/ViewControllers/Connections/DiagnosticsDashboardViewController.swift`](../../ClashX/ViewControllers/Connections/DiagnosticsDashboardViewController.swift) for `/memory`, `/dns/query`, restart, GEO, and debug actions

The next step is to turn this from an opportunistic cache into a fuller probe layer across the API surface.

## PRO_VERSION Cleanup

Legacy `PRO_VERSION` assumptions are now one of the biggest architectural mismatches in the branch.

### Rule providers

[`ClashX/General/ApiRequest.swift`](../../ClashX/General/ApiRequest.swift) no longer hides `/providers/rules` behind `#if PRO_VERSION`. That specific mismatch has been removed.

### Script assumptions

[`ClashX/Models/ClashConfig.swift`](../../ClashX/Models/ClashConfig.swift) now decodes `.script` mode without `#if PRO_VERSION`, and [`ClashX/AppleScript/ProxyModeChangeCommand.swift`](../../ClashX/AppleScript/ProxyModeChangeCommand.swift) switches modes by value instead of relying on a legacy script-only menu item. That removes one more product-tier assumption, even though the broader capability-map work is still pending.

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
