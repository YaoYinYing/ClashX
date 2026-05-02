# SmartX Current Implementation

## Summary

The `smartx` branch is currently a ClashX modernization branch that integrates a Vernesong mihomo smart core while preserving the native macOS menu-bar client architecture. The branch keeps the existing macOS app shell, Cocoa UI, settings window, menu-bar workflow, and Objective-C/Swift app structure, but changes the embedded Go core wiring, adds Smart/LightGBM-related client features, expands model decoding for newer mihomo data, and introduces new status/control surfaces such as the Core settings page and Smart dashboard.

This branch is not just a core-version bump. It changes:

- embedded core dependency wiring under [ClashX/goClash](../../ClashX/goClash)
- client-side settings and paths for Smart data under [ClashX/General/Managers/Settings.swift](../../ClashX/General/Managers/Settings.swift) and [ClashX/Macro/Paths.swift](../../ClashX/Macro/Paths.swift)
- API wrappers under [ClashX/General/ApiRequest.swift](../../ClashX/General/ApiRequest.swift)
- model decoding under [ClashX/Models](../../ClashX/Models)
- UI surfaces under [ClashX/ViewControllers/Settings/CoreSettingViewController.swift](../../ClashX/ViewControllers/Settings/CoreSettingViewController.swift), [ClashX/ViewControllers/Connections/SmartDashboardViewController.swift](../../ClashX/ViewControllers/Connections/SmartDashboardViewController.swift), and [ClashX/ViewControllers/Connections/DiagnosticsDashboardViewController.swift](../../ClashX/ViewControllers/Connections/DiagnosticsDashboardViewController.swift)

## Current Code Changes

### Go Core Binding

The embedded Go core is now wired through [ClashX/goClash/go.mod](../../ClashX/goClash/go.mod). The module directly requires `github.com/metacubex/mihomo`, but also includes:

```go
replace github.com/metacubex/mihomo => github.com/vernesong/mihomo ...
```

This works because the Vernesong fork still declares the `github.com/metacubex/mihomo` module path. In practice, the branch is building against the Vernesong fork while keeping import paths compatible with the upstream mihomo module name.

The c-archive build flow remains in place in [ClashX/goClash/build_clash_universal.py](../../ClashX/goClash/build_clash_universal.py):

- it builds `arm64` and `amd64` static archives with `-buildmode=c-archive`
- it writes `goClash.a` plus a merged C header
- it sets version/build-time ldflags against `github.com/metacubex/mihomo/constant`
- it can derive the core version from `MIHOMO_CORE_VERSION` or `go list -m`

[ClashX/goClash/main.go](../../ClashX/goClash/main.go) now imports mihomo packages from the `metacubex/mihomo` path and applies configuration via `hub.ApplyConfig`, not only the older Clash-style executor path. It also:

- sets the home directory to `~/.config/clash`
- reads `config.yaml` directly from that directory
- generates a strong controller secret if one is missing
- constrains local controller binding toward loopback when LAN mode is off
- registers geo and LightGBM updaters when the core reports auto-update enabled

[ClashX/goClash/upgrade_core.py](../../ClashX/goClash/upgrade_core.py) is still a lightweight script that rewrites the version in `go.mod`, runs `go mod download` and `go mod tidy`, and then rebuilds. Because this workflow mutates the required version while also depending on `replace`-based wiring, it should be treated as operationally fragile rather than as a robust release-management mechanism.

### Smart LightGBM Support

Smart LightGBM client settings are stored in [ClashX/General/Managers/Settings.swift](../../ClashX/General/Managers/Settings.swift). The branch currently persists:

- `smartLightGBMOverrideConfig`
- `smartLightGBMModelUrl`
- `smartLightGBMAutoUpdate`
- `smartLightGBMUpdateIntervalHours`

It also defines:

- `defaultSmartLightGBMModelUrl`
- `effectiveSmartLightGBMModelUrl`
- `syncSmartLightGBMOptionsToCore()`

The native app forwards these values into the Go bridge via `clash_setLightGBMOptions(...)`.

The Go side applies those settings in [ClashX/goClash/main.go](../../ClashX/goClash/main.go) through `applySmartLightGBMOverrides(rawCfg *config.RawConfig)`, which mutates:

- `rawCfg.LgbmUrl`
- `rawCfg.LgbmAutoUpdate`
- `rawCfg.LgbmUpdateInterval`

This means the current implementation does not just display Smart settings in the UI; it can override the raw core config before startup and config reload.

Smart resource paths are exposed in [ClashX/Macro/Paths.swift](../../ClashX/Macro/Paths.swift):

- `Paths.smartLightGBMModelPath` points to `~/.config/clash/Model.bin`
- `Paths.smartWeightDataPath` points to `~/.config/clash/smart_weight_data.csv`

These paths indicate the branch expects both a binary LightGBM model and a separate Smart weight data CSV, even if the CSV flow is not yet surfaced everywhere as a first-class UI feature.

### Mihomo API Additions

[ClashX/General/ApiRequest.swift](../../ClashX/General/ApiRequest.swift) adds several wrappers beyond the older ClashX API set.

Current additions include:

- `requestSmartWeights(...)`
- `requestSmartWeights(group:...)`
- `flushSmartCache(...)`
- `blockSmartConnection(...)`
- `updateSmartLightGBMModel(...)`
- `requestCoreVersion(...)`
- `updateTun(enable:...)`
- `requestMemorySnapshot(...)`
- `requestDNSQuery(...)`
- `resetDNSCache(...)`
- `reloadGeoDatabase(...)`
- `restartCore(...)`
- `updateDashboardAssets(...)`
- `updateGeoAssets(...)`
- `runDebugGC(...)`
- `requestPolicyGroups(...)`
- `requestPolicyGroup(name:...)`
- `deletePolicyGroup(name:...)`
- `requestPolicyGroupDelay(name:...)`

The file also adds new response and decoding types:

- `SmartNodeWeight`
- `SmartWeightsResponse`
- `SmartEndpointResult`
- `CoreVersionInfo`

The current API wrapper layer also changes provider handling:

- `requestProxyProviderList(...)` now uses a tolerant decode path and warning log instead of asserting
- `getMergedProxyData(...)` will still return proxy info even if provider data is absent or partially decoded
- config update paths call `Settings.syncSmartLightGBMOptionsToCore()` before applying configs through the Go bridge

`updateTun(enable:)` is currently only a guarded `PATCH /configs` wrapper. It does not create a privileged TUN runtime path by itself.

The branch also now has a lightweight capability cache in [ClashX/General/Managers/CoreCapability.swift](../../ClashX/General/Managers/CoreCapability.swift). It is currently used to remember unsupported or unauthorized controller features across the Core settings page, Smart dashboard, and Diagnostics dashboard, so the UI can degrade cleanly instead of repeatedly retrying endpoints that the active controller clearly does not support.

The config layer also now has a lightweight profile inventory bridge in [ClashX/General/Managers/ConfigManager.swift](../../ClashX/General/Managers/ConfigManager.swift). It does not replace filename-based config switching, but it can now classify selectable configs as `Local` or `Remote`, attach source/cache metadata, and feed that state into the menu UI and diagnostics report.

Remote profile definitions in [ClashX/Models/RemoteConfigModel.swift](../../ClashX/Models/RemoteConfigModel.swift) now also persist first-pass validation and last-fetch state. That status is updated by [ClashX/General/Managers/RemoteConfigManager.swift](../../ClashX/General/Managers/RemoteConfigManager.swift) and surfaced through the profile inventory, diagnostics report, and remote-config table tooltips.

Successful config reloads now also persist first-pass profile artifacts through [ClashX/General/Managers/ProfileArtifactManager.swift](../../ClashX/General/Managers/ProfileArtifactManager.swift). The branch writes a deterministic copy of the loaded config file to generated-effective and last-known-good artifact paths under `~/.config/clash/.smartx/profiles/`, along with JSON metadata describing the selected profile and reload context. The Diagnostics dashboard can also restore the saved last-known-good artifact. This is still based on the legacy “reload a file path” model, not a true layered effective-config generator.

### UI Additions

[ClashX/ViewControllers/Settings/CoreSettingViewController.swift](../../ClashX/ViewControllers/Settings/CoreSettingViewController.swift) is a new status/control surface for SmartX-specific core behavior. It currently exposes:

- core mode, version, and build metadata
- controller state and URL
- config load status
- TUN config status
- DNS config status
- Smart/LightGBM model status and update controls

The page is informative, but it does not fully manage the whole core lifecycle. It reads state from:

- app settings
- cached config state
- `/version`
- `/configs`
- selected model file metadata

It also contains explicit TUN capability gating plus first-pass TUN/DNS validation messaging. For example:

- embedded-core TUN is disabled with a message that SmartX lacks a privileged TUN startup path
- external-controller TUN can only attempt a guarded update when the controller exposes `tun` through `/configs`
- helper/system-proxy capability is explicitly separated from TUN capability
- additional TUN routing/interface fields are shown read-only when present
- structured DNS fields are shown read-only when present
- risky combinations such as `strict-route`, conflicting include/exclude interface filters, suspicious MTU values, invalid-looking CIDRs, `fake-ip` mode, or `respect-rules` without an obvious resolver path are surfaced as warnings instead of being silently ignored

[ClashX/ViewControllers/Connections/SmartDashboardViewController.swift](../../ClashX/ViewControllers/Connections/SmartDashboardViewController.swift) is another new UI surface. It currently exposes:

- Smart proxy groups from merged proxy data
- node weights and rank information
- Smart cache flush actions
- LightGBM model update and local override controls
- basic model-path and model-status display

It is still a management and observability surface layered on top of API wrappers. It does not implement full Smart policy authoring, full background sync orchestration, or a complete error/retry UX for all Smart endpoints.

[ClashX/ViewControllers/Connections/DiagnosticsDashboardViewController.swift](../../ClashX/ViewControllers/Connections/DiagnosticsDashboardViewController.swift) adds a lightweight diagnostics surface to the dashboard. It currently exposes:

- `/memory` polling and raw JSON display
- `/dns/query` requests with raw JSON display
- DNS cache flush
- fake-IP cache flush
- `/restart`
- `/debug/gc`
- `POST /configs/geo`
- `POST /upgrade/geo`
- `POST /upgrade/ui`
- a lightweight file-backed log viewer with level filter, search, pause/resume, and export

It is intentionally simple and capability-driven. It does not yet implement a dedicated memory history view, a polished DNS troubleshooting workflow, or `/debug/pprof` tooling.

### Data Model Additions

[ClashX/Models/ClashConfig.swift](../../ClashX/Models/ClashConfig.swift) now includes a nested `Tun` model with only a subset of mihomo TUN fields:

- `enable`
- `device`
- `stack`
- `dns-hijack`
- `auto-route`

This is enough for status display and limited PATCH flows, but not a full representation of mihomo’s TUN configuration space.

[ClashX/Models/ClashProxy.swift](../../ClashX/Models/ClashProxy.swift) expands proxy typing significantly. It now includes:

- `Smart` as a proxy group type
- newer transport/proxy types such as `Wireguard`, `Hysteria`, `Hysteria2`, `Tuic`, `Mieru`, `AnyTLS`, `TrustTunnel`, `Masque`, `Vless`, and `Sudoku`

It also updates group classification so Smart groups behave like auto groups in the client.

[ClashX/Models/ClashProvider.swift](../../ClashX/Models/ClashProvider.swift) now performs more tolerant dynamic decoding:

- providers are decoded from dynamic keys
- provider `name` can be backfilled from the outer map key
- `ProviderType` and `ProviderVehicleType` recognize unknown values instead of hard-failing

This improves compatibility with provider payloads from newer mihomo cores, but it is still limited to the currently modeled provider fields.

[ClashX/Models/ClashConnection.swift](../../ClashX/Models/ClashConnection.swift) now includes Smart metadata and richer network metadata in connection decoding:

- `sourceGeoIP`
- `destinationGeoIP`
- `sourceIPASN`
- `destinationIPASN`
- `smartBlock`
- `smartTarget`

That means the client can now represent more of the connection metadata emitted by a Smart-capable core, even if not every field is displayed everywhere yet.

### Build and Resource Flow

[install_dependency.sh](../../install_dependency.sh) still drives local setup. It currently:

- builds the Go c-archive via `python3 build_clash_universal.py`
- installs Ruby dependencies and CocoaPods
- downloads a MaxMind database artifact and stores it as `ClashX/Resources/Country.mmdb.gz`
- clones `MetaCubeX/Yacd-meta` into `ClashX/Resources/dashboard`

[Podfile](../../Podfile) still uses CocoaPods rather than moving to a new dependency system. The branch keeps the existing Pod-based desktop app stack, with deployment-target normalization in `post_install`.

[ClashX/Info.plist](../../ClashX/Info.plist) reflects SmartX-era packaging changes, including:

- `LegacyIdentityNotice`
- disabled Sparkle automatic checks
- an invalid placeholder feed URL
- legacy helper signing metadata still present
- legacy iCloud container identifiers still present

This means resource/build flow has changed, but packaging metadata has only been partially modernized.

## Known Limitations

- The current TUN model only covers a subset of mihomo TUN fields in [ClashX/Models/ClashConfig.swift](../../ClashX/Models/ClashConfig.swift).
- DNS is not yet modeled as a first-class client setting in the SmartX UI or Swift config models, even though TUN status refers to DNS hijack-related fields.
- `PRO_VERSION` gates still exist in parts of the branch and may hide features that are ordinary mihomo features rather than truly “Pro-only” features, even though rule-provider discovery and `.script` mode decoding have already been moved away from that boundary.
- Release signing and privileged helper identity still require modernization. [ClashX/Info.plist](../../ClashX/Info.plist) and helper-related metadata still contain legacy identifiers and trust requirements.
- [README.md](../../README.md) still mixes SmartX notes with older ClashX behavior and should not be treated as a fully current implementation reference.
- Reproducibility is limited if dashboard and resources are pulled without pinned revisions. [install_dependency.sh](../../install_dependency.sh) clones `Yacd-meta` by branch and downloads GeoIP data by latest URL.
- The core update script in [ClashX/goClash/upgrade_core.py](../../ClashX/goClash/upgrade_core.py) may be fragile because it rewrites the required version textually while the branch also depends on replace-based module wiring.
- The Smart dashboard and Core settings page expose status and limited control, but they do not prove full production readiness of Smart endpoints, TUN runtime support, or privileged core lifecycle handling.
- Provider decoding is more tolerant than before, but the client model still only captures a narrow provider shape compared with full mihomo provider state.

## Open Questions

- Should the embedded core continue to rely on Go `replace`-based dependency steering, or should the project adopt a more explicit vendoring or release-pin strategy for the Vernesong fork?
- How should Smart LightGBM assets be versioned and updated reproducibly across local development, CI, and release packaging?
- Should `smart_weight_data.csv` become a first-class managed artifact in the UI and diagnostics, or remain an implementation detail under `~/.config/clash`?
- Which newer mihomo config domains beyond TUN should become first-class Swift models rather than remaining pass-through YAML or JSON?
- How much of the current `PRO_VERSION` gating is still intentional in a SmartX world, and how much is legacy carry-over from older ClashX/ClashX Pro assumptions?
- Should the Smart dashboard remain a standalone management surface, or should Smart ranking and weight visibility be integrated into the existing connection and proxy UI?
- What is the long-term release story for Sparkle, iCloud, helper signing, bundle identifiers, and update feeds now that [ClashX/Info.plist](../../ClashX/Info.plist) contains placeholder or legacy values?
- How much of the current Go bridge should remain in `main.go`, and when should branch-specific core behavior be split into better-structured bridge layers?
- Is the current external-controller and embedded-core dual-mode model sufficient for Smart features, or does SmartX eventually need a clearer separation between embedded-core mode and externally managed mihomo mode?

## Source of Truth

This document is descriptive, not normative. The source of truth is the current implementation in the repository, especially the files referenced above. When the implementation changes, this document must be updated to match the code rather than the intended roadmap.
