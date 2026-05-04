# SmartX Update Plan: Smart-First Mihomo-Compatible Runtime

## Executive Summary

SmartX should remain a Smart-first macOS mihomo-compatible client. The normal product path is a bundled SmartX release that already includes an embedded Smart core through the existing Go c-archive bridge in `ClashX/goClash/`.

Ordinary users should not need to understand Smart core, ordinary mihomo, alpha forks, or a core taxonomy. The product-layer single core is the embedded Smart runtime. Smart-specific behavior should be treated as an optional Smart capability layer on top of a mihomo-compatible runtime baseline. Future migration back to ordinary mihomo should be enabled by capability-based graceful degradation and a clean core migration boundary, not by exposing user-visible multi-core choices.

SmartX does not need user-visible multi-core support. SmartX needs maintainer-visible core migration boundaries.

## Product Principle

The product-layer rule is simple:

- SmartX has one product identity.
- SmartX has one normal shipped runtime: the bundled Smart-first embedded runtime.
- SmartX should not add a normal user-facing core selector.
- External controller paths and alternate runtime experiments may exist for development, diagnostics, or compatibility work, but they should not become the center of the main UX.

This matches the current branch shape:

- `README.md` presents SmartX as a native macOS client with an embedded Vernesong Smart mihomo fork.
- `ClashX/goClash/main.go` still initializes one local core home and one active config path.
- `ClashX/ViewControllers/Settings/CoreSettingViewController.swift` and `ClashX/ViewControllers/Connections/SmartDashboardViewController.swift` are capability-driven preview surfaces, not a multi-runtime selection UI.

The product should stay simple for users even if the architecture remains careful for maintainers.

## Architecture Principle

The internal rule is different from the product rule:

- App code should target a mihomo-compatible runtime baseline.
- Smart-only behavior should live behind an optional Smart capability layer.
- UI should consume capability state, not compile-time assumptions about a specific fork.
- Smart endpoint assumptions should not keep spreading through large controllers or one-off request helpers.
- Core migration work should stay localized to the Core Runtime Boundary and Core Adapter Boundary.

In current code, the beginnings of that boundary already exist:

- `ClashX/goClash/go.mod`, `ClashX/goClash/main.go`, and `ClashX/goClash/build_clash_universal.py` define the embedded runtime source and build path.
- `ClashX/General/Utils/ControllerEndpointBuilder.swift` centralizes controller URL construction.
- `ClashX/General/Managers/CoreCapability.swift` and `ClashX/General/Managers/CoreCapabilityProbe.swift` define capability state instead of hard-coding support assumptions into every screen.
- `ClashX/General/ApiRequest.swift` already distinguishes `success`, `unsupported`, `unauthorized`, and `failed`, but it is still too large and still mixes baseline mihomo endpoints with Smart-only wrappers.

The codebase should keep moving toward architecture-layer core migration support while preserving a product-layer single core.

## Capability Classification

Capabilities should be classified by baseline compatibility, optional Smart extension behavior, and platform-sensitive risk.

### A. Mihomo baseline capabilities

These should be treated as baseline or near-baseline features for a mihomo-compatible runtime:

| Capability | Current evidence | Expected treatment |
| --- | --- | --- |
| version read | `ApiRequest.requestCoreVersionResult`, `CoreCapability.versionRead` | baseline |
| config read | `ApiRequest.requestControllerConfig`, `CoreCapability.configRead` | baseline |
| config patch/reload | `ApiRequest.updateConfig`, `CoreCapability.configPatch`, `CoreCapability.configReload` | baseline but guarded |
| proxy groups | `ApiRequest.getMergedProxyData`, `ClashProxy` model | baseline |
| proxy providers | `ApiRequest.requestProxyProvidersDiagnostics`, `CoreCapability.proxyProviders` | baseline |
| rule providers | `ApiRequest.requestRuleProvidersDiagnostics`, `CoreCapability.ruleProviders` | baseline |
| rules / policy groups | `requestPolicyGroups`, `requestPolicyGroup`, `requestPolicyGroupDelay` | baseline |
| connections | `ClashConnection`, `ConnectionsViewModel` | baseline |
| logs | stream support in `ApiRequest`, log viewer helpers in diagnostics | baseline |
| traffic | `ApiRequest` stream delegate and dashboard usage | baseline |
| memory | `requestMemorySnapshot`, `CoreCapability.memorySnapshot` | baseline where supported |
| DNS query | `requestDNSQuery`, `CoreCapability.dnsQuery` | guarded baseline diagnostics |
| DNS cache flush | `resetDNSCache`, `CoreCapability.dnsCacheFlush` | guarded baseline diagnostics |
| GEO update | `reloadGeoDatabase`, `updateGeoAssets`, `CoreCapability.geoUpdate` | guarded baseline maintenance |
| UI update | `updateDashboardAssets`, `CoreCapability.uiUpgrade` | guarded maintenance |
| restart | `restartCore`, `CoreCapability.restart` | guarded maintenance |
| debug GC / pprof helper | `runDebugGC`, `copy pprof URLs`, `CoreCapability.debugGC`, `CoreCapability.debugPprof` | optional baseline diagnostics, not ordinary UX |

These should remain usable even if Smart-specific functions are absent.

### B. Smart extension capabilities

These are Smart-only or Smart-biased features and must be modeled as optional capabilities:

| Capability | Current evidence | Expected treatment |
| --- | --- | --- |
| Smart groups | `ClashProxyType.smart`, Smart Dashboard group filtering | optional Smart capability layer |
| Smart weights | `ApiRequest.requestSmartWeights`, `CoreCapability.smartWeights` | optional and probe-driven |
| Smart cache flush | `ApiRequest.flushSmartCache`, `CoreCapability.smartCacheFlush` | optional and probe-driven |
| Smart connection block | `ApiRequest.blockSmartConnection`, `CoreCapability.smartConnectionBlock` | optional and probe-driven |
| LightGBM model upgrade | `ApiRequest.updateSmartLightGBMModel`, `CoreCapability.lightGBMUpgrade` | optional and probe-driven |
| LightGBM override | `LightGBMSettingsViewModel`, `SmartXManagedOverrideManager`, `Settings.syncSmartLightGBMOptionsToCore()` | optional Smart capability layer |
| Smart model file status | `Paths.smartLightGBMModelPath`, Smart dashboard and Core settings status | optional Smart diagnostics |
| Smart weight data status | `Paths.smartWeightDataPath` and Smart-facing status surfaces | optional Smart diagnostics |
| Smart target / Smart block metadata | `ClashConnection.Metadata.smartTarget` / `smartBlock` | optional data enrichment |
| Smart decision explanation | `ConnectionDetailViewModel` inference layer | optional preview diagnostics, not a guaranteed core trace |

These capabilities should never be assumed to exist just because the product ships a Smart-first embedded runtime. They must still degrade cleanly when running against an ordinary mihomo-compatible runtime or an incomplete external controller.

### C. Platform-sensitive capabilities

These are especially sensitive because they depend on macOS privileges, helper boundaries, or routing semantics:

| Capability | Current evidence | Expected treatment |
| --- | --- | --- |
| TUN lifecycle | `TunLifecycleCoordinator`, `CoreSettingViewController`, `TunConfigValidator` | guarded and still partial |
| DNS hijack behavior | `ClashConfig.DNS`, `DNSConfigValidator`, diagnostics DNS tools | guarded and platform-sensitive |
| macOS helper integration | `ProxyConfigHelper/`, helper trust metadata, `README.md` helper notes | guarded platform integration |
| system proxy modification | `ProxyConfigHelper` and app helper wiring | supported boundary, separate from TUN |
| route ownership and rollback | not fully implemented; current docs keep wording honest | not yet complete, must remain explicit |

These should never be presented as simple toggles without lifecycle, validation, and failure behavior.

## Graceful Degradation Model

If the runtime is ordinary mihomo or a Smart endpoint is missing, SmartX should degrade by capability state rather than by controller failure or blank UI.

Required behavior:

- Smart Dashboard should show unsupported or disabled state rather than fail.
- LightGBM update controls should be disabled when `lightGBMUpgrade` is unsupported or unauthorized.
- Smart cache operations should be disabled when `smartCacheFlush` is unavailable.
- Smart connection block should be disabled when `smartConnectionBlock` is unavailable.
- Connection details should omit Smart target and Smart block explanation sections when metadata is absent.
- Baseline mihomo-compatible functions should continue to work.

The current branch already points in this direction:

- `CoreEndpointAvailability` distinguishes `available`, `unavailable`, `unauthorized`, `unsupported`, `unknown`, and `degraded`.
- `CapabilityCache` stores those states for UI and diagnostics reuse.
- `SmartDashboardViewController` disables Smart surfaces when `smartWeights` or `lightGBMUpgrade` are unsupported or unauthorized.
- `CoreSettingViewController` explicitly separates helper support from TUN support and now treats unverified TUN updates as unverified rather than as success.
- `DiagnosticsDashboardViewController` already hides or disables actions based on capability state instead of assuming support.

This model should become the standard rule:

- `unknown`: not probed yet
- `available`: probed and supported
- `unsupported`: runtime does not implement it
- `unauthorized`: runtime rejected credentials or authorization
- `unavailable`: controller/core is stopped or unreachable
- `degraded`: endpoint exists but returned a transient or partial failure

## Core Migration Boundary

Future Smart-to-mihomo migration should mostly affect a small number of adapter boundaries instead of the entire UI.

The Core Runtime Boundary and Core Adapter Boundary should isolate at least these areas:

### 1. Go module source and replace strategy

- `ClashX/goClash/go.mod`
- `ClashX/goClash/upgrade_core.py`

This is where the current Vernesong Smart fork is wired through `require github.com/metacubex/mihomo` plus `replace => github.com/vernesong/mihomo`. A future migration should primarily change this boundary, not every UI surface.

### 2. Core version and commit metadata injection

- `ClashX/goClash/build_clash_universal.py`
- `ClashX/goClash/main.go`
- `ClashX/Info.plist`
- `AboutViewController`

Version/build metadata must stay explicit so SmartX can record the exact embedded core source and version.

### 3. Build scripts and ldflags

- `build_clash_universal.py`
- `install_dependency.sh`
- `.github/workflows/pr-ci.yml`
- `.github/workflows/post-merge-dmg.yml`
- `scripts/codex-build-debug.sh`

Build and packaging should depend on one runtime boundary instead of scattering core-specific assumptions across CI and release steps.

### 4. Controller endpoint construction

- `ClashX/General/Utils/ControllerEndpointBuilder.swift`

All new or touched controller endpoints should use this boundary so a future controller-base or path-policy change does not require broad rewrites.

### 5. Capability probes

- `ClashX/General/Managers/CoreCapability.swift`
- `ClashX/General/Managers/CoreCapabilityProbe.swift`

These files should become the place where runtime support is explained and cached by controller identity and version metadata.

### 6. Smart endpoint wrappers

- `ClashX/General/ApiRequest.swift`

Smart wrappers such as Smart weights, Smart cache flush, connection block, and LightGBM upgrade should be isolated from baseline mihomo domain clients.

### 7. LightGBM config override

- `ClashX/General/Managers/Settings.swift`
- `ClashX/General/Managers/LightGBMSettingsViewModel.swift`
- `ClashX/General/Managers/SmartXManagedOverrideManager.swift`
- `ClashX/goClash/main.go`

This is already a real Smart-specific adaptation seam. It should stay explicit rather than turning into hidden config mutation scattered across unrelated code.

### 8. Smart resource paths

- `ClashX/Macro/Paths.swift`

Smart model, weights, override, and profile-artifact paths should remain easy to audit and migrate.

### 9. Diagnostics metadata

- `ProfileArtifactManager`
- `DiagnosticsReportBuilder`
- `DiagnosticsBundleExporter`
- `SmartXRedactor`

Diagnostics should describe runtime and capability state honestly while preserving redaction guarantees.

### 10. Release manifest and corresponding-source discipline

- `README.md`
- `docs/memory/02-build-and-release.md`
- `docs/memory/09-security-signing-and-license.md`
- workflows and release scripts

Migration must keep source, runtime identity, and release discipline coherent.

Changing Smart core to ordinary mihomo later should mostly affect these boundaries, not the entire UI tree.

## Current Codebase Alignment

The current branch already has several foundations that align with this plan:

- Vernesong Smart fork wiring through `ClashX/goClash/go.mod`
- Go c-archive bridge in `ClashX/goClash/main.go`
- Smart LightGBM override path through app settings, override persistence, and Go-side raw-config mutation
- `ControllerEndpointBuilder`
- `CoreCapability`
- `CoreCapabilityProbe`
- Smart Dashboard
- Core Settings page
- Diagnostics Dashboard
- Profile artifact layer
- `DiagnosticsBundleExporter`
- `SmartXRedactor`
- provider health history
- helper scripts and lightweight smoke harnesses in `Tests/SecurityHarness`

The same inspection also shows why these foundations should be hardened rather than expanded as another feature blob:

- `ApiRequest.swift` is still a dumping ground for both baseline and Smart-only endpoints.
- `CoreCapabilityProbe` is still a minimal read-only probe layer and does not yet cover the full capability matrix.
- `CoreSettingViewController.swift`, `SmartDashboardViewController.swift`, and `DiagnosticsDashboardViewController.swift` still carry large controller responsibilities even after some helper extraction.
- `ProfileArtifactManager` is still source-copy oriented rather than a true generated effective config pipeline.
- `ConnectionDetailViewModel` provides Smart decision explanation by inference from current observable state, not from a dedicated core-side explanation endpoint.
- `build_clash_universal.py` and `upgrade_core.py` still reflect an operationally fragile core-upgrade path.
- `ProxyConfigHelper/` still represents legacy helper identity and trust-policy migration work that is separate from runtime capability architecture.

The right next step is not more product surface. The right next step is to make the existing runtime, capability, override, diagnostics, and release seams coherent.

## Update Phases

### Phase 0: Stabilize Current SmartX Foundation

Goals:

- keep build scripts and CI reliable
- align docs with actual implementation
- keep SmartX terminology honest
- avoid new feature expansion until current preview surfaces are stable

Concrete repo anchors:

- `scripts/ensure-xcworkspace.sh`
- `scripts/codex-build-debug.sh`
- `scripts/codex-test-focused.sh`
- `.github/workflows/pr-ci.yml`
- `docs/memory/`

This phase should keep merge quality high and avoid feature drift.

### Phase 1: API Layer and Endpoint Boundary

Goals:

- split `ApiRequest` into smaller domain clients
- require `ControllerEndpointBuilder` for all new or touched controller paths
- unify result types and error mapping
- distinguish unsupported, unauthorized, unavailable, degraded, and failed

Likely slices:

- config/runtime client
- Smart extension client
- diagnostics/maintenance client
- provider/policy client

`ApiRequest` should stop being the permanent home for every endpoint.

### Phase 2: Capability Probe Completion

Goals:

- expand `CoreCapabilityProbe`
- key capability cache by controller identity plus core version and metadata
- probe Smart endpoints safely
- probe generic mihomo endpoints separately
- avoid mutating user state during probes unless using an explicit guarded write-and-restore flow

This phase should complete the capability-based graceful degradation model.

### Phase 3: Smart Extension Layer

Goals:

- isolate Smart-specific API wrappers
- model Smart weights, cache, LightGBM, Smart block, and Smart target as optional extension capabilities
- make Smart Dashboard consume capability state instead of fork assumptions
- ensure ordinary mihomo fallback disables Smart features cleanly

This is where the optional Smart capability layer becomes an explicit architecture surface instead of a set of opportunistic additions.

### Phase 4: Profile Workspace and Override Layer

Goals:

- evolve from selected YAML filenames to a profile workspace
- define Remote, Local, Merge, Script, Generated Effective, and Last-known-good profiles
- keep subscription sources read-only
- store local adjustments as overlays
- generate reproducible effective configs
- validate before reload
- roll back on failure

Current profile artifacts and managed override groundwork should lead into this phase, not be mistaken for its completion.

### Phase 5: TUN and DNS as Structured Models

Goals:

- keep current TUN support honest as limited config patching
- design TUN lifecycle: preflight, enable, verify, rollback, disable, recover
- model DNS as a first-class structure
- distinguish macOS-supported fields from Linux/Android-only fields
- add validation before writes

This phase should not pretend config visibility equals runtime support.

### Phase 6: Diagnostics and Observability

Goals:

- decompose `DiagnosticsDashboardViewController`
- build structured route explanation where practical
- add memory, traffic, provider, and Smart history surfaces where they are genuinely useful
- improve DNS query workflow
- improve provider and rule provenance
- keep diagnostics bundles redacted by design

Diagnostics should remain useful for maintainers without turning into a new monolithic controller or a sensitive-data leak.

### Phase 7: Release, Signing, and Supply Chain

Goals:

- finalize SmartX bundle/helper identity migration
- remove or deliberately own inherited analytics and crash reporting
- configure Developer ID signing, notarization, stapling, and update signing if used
- pin dashboard and resource assets
- record core source, commit, and build metadata
- keep AGPL corresponding-source discipline

This phase is necessary for a real SmartX release, not just for a working preview branch.

## Non-goals

This plan does not mean:

- building a public core marketplace
- forcing users to understand core variants
- exposing Smart-vs-mihomo terminology in normal workflows
- creating a user-facing multi-core selector
- adding more large controllers before extracting boundaries
- treating current preview panels as final architecture
- pretending config visibility equals TUN runtime support
- letting Smart-only failures break baseline mihomo-compatible functionality

The plan is intentionally about maintainer-visible core migration boundaries, not user-visible runtime complexity.

## Acceptance Criteria

SmartX should be considered aligned with this plan when:

- ordinary users can use the bundled Smart runtime without making core choices
- Smart-only controls are enabled only when capability probes pass
- ordinary mihomo-compatible runtime can run baseline features with Smart features disabled
- `ApiRequest` is no longer a dumping ground for all endpoints
- capability state is visible to UI and diagnostics
- profile workspace can explain what produced the running config
- TUN and DNS writes are validated and recoverable
- diagnostics exports redact secrets, subscription URLs, proxy credentials, and sensitive paths
- build and release metadata record the exact embedded core source and version
- future Smart-to-mihomo migration mainly touches adapter, probe, and build boundaries

## Implementation Guidance for Future PRs

Future PRs should stay small and focused:

- one PR for one boundary or one feature group
- update `docs/memory/` whenever implementation changes
- include tests, or document why direct tests are not practical
- prefer utility-level and model-level tests over only UI wiring
- do not add new large controllers without decomposition
- do not claim support until code actually has lifecycle, validation, and failure behavior

Concrete maintainership rule:

- If a PR touches runtime capability behavior, update `CoreCapability`, `CoreCapabilityProbe`, and the relevant memory docs together.
- If a PR touches Smart-only behavior, verify that baseline mihomo-compatible behavior still degrades cleanly.
- If a PR touches diagnostics or exported artifacts, confirm `SmartXRedactor`, `DiagnosticsReportBuilder`, and `DiagnosticsBundleExporter` still apply the intended redaction path.
- If a PR touches release or runtime source wiring, keep `README.md`, build scripts, workflows, and corresponding-source notes aligned.

SmartX should stay Smart-first in product terms, mihomo-compatible in runtime terms, and migration-ready in architecture terms.
