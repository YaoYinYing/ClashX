# SmartX Roadmap

## Current Direction

SmartX modernization should not keep expanding as a pile of preview panels, singleton patches, and loosely-related controller wrappers. The current branch proved that capability-aware diagnostics, profile artifacts, TUN/DNS visibility, and Smart evidence are valuable, but it also exposed patchwork architecture debt that should be paid down before more UI is added.

SmartX now has three immediate priorities:

1. Stabilize and merge the current diagnostics/capability preview branch.
2. Pay down patchwork architecture debt before adding more UI.
3. Build a sequence of focused PRs that turn prototypes into architecture.

This roadmap reflects that review outcome. It deliberately reorders work around architectural seams instead of around feature demos.

## Roadmap Rules

- Current source code remains the source of truth.
- Memory docs must be updated when implementation changes.
- New work should avoid adding more large view controllers, more global-singleton coupling, more direct string-concatenated endpoints, or more UI that claims architecture that does not exist yet.
- Testing is not a late phase. Every PR should include tests where practical, or a documented test gap when direct coverage is blocked.

## Phase 0: Stabilize Current PR and Merge

Scope:

- close review findings from the current diagnostics/capability preview branch
- keep terminology honest
- remove misleading product wording
- verify build and basic harness coverage
- keep docs aligned with what the branch actually implements

This phase is about merge quality, not feature expansion. The current branch should land only after its claims, labels, safeguards, and review gaps are cleaned up.

Expected outputs:

- branch compiles cleanly in documented flows
- diagnostics actions have appropriate confirmation and safety wording
- artifact/report terminology does not overclaim generated config or sanitization
- SmartX identity text is consistent in new user-facing surfaces
- review findings are captured in memory docs

Current note:

- A focused user-facing identity cleanup PR is acceptable in this phase as long as it does not attempt full bundle/helper/signing migration in the same patch.

Testing gate:

- every fix PR in this phase should run the relevant build and lightweight harness checks
- unsigned CI artifacts in this phase remain manual-testing artifacts only, and the lightweight harness checks are still transitional smoke coverage rather than a high-coverage test strategy

## Phase 1: Endpoint Builder and API Result Unification

Scope:

- introduce a shared controller endpoint builder
- stop spreading raw URL string concatenation across request layers
- unify endpoint result types and error mapping
- split large endpoint dumping-ground behavior out of `ApiRequest`

This phase creates the foundation for future controller work. SmartX should not keep accreting one-off wrappers with inconsistent result semantics.

Expected outputs:

- controller HTTP and WebSocket URL construction is centralized
- endpoint wrappers return consistent result families
- unauthorized, unsupported, unavailable, and transient failures are separated cleanly
- `ApiRequest` stops being the only place every endpoint lands

Testing gate:

- endpoint building and result mapping should have direct utility-level coverage where practical

Current note:

- the first pass of `ControllerEndpointBuilder`, stopped-core result cleanup, and Smart endpoint result unification is now implemented, but `ApiRequest` is still only partially decomposed
- the next small API-domain split has started with `ConnectionAPI`, but stream lifecycle still remains in `ApiRequest` while traffic/log retry ownership is shared with WebSocket delegate state

## Phase 2: Capability Probing System

Scope:

- move from cache-only capability state to active capability probing
- define probe lifecycle and invalidation rules
- tie capabilities to controller identity and endpoint availability
- make capability state explainable to UI and diagnostics layers

The current capability cache is a useful start, but it is not yet a real probing system. This phase turns preview capability handling into architecture.

Expected outputs:

- capability probing is explicit and reusable
- capability state can distinguish unknown, supported, unauthorized, degraded, and unsupported states
- UI does not guess capability from compile-time history or ad hoc failures

Testing gate:

- probe-state transitions and invalidation rules should be covered with focused tests where feasible

Current note:

- SmartX now has a baseline `CoreCapabilityProbe` snapshot flow, but it is still a minimal read-only probe layer rather than the final capability architecture
- `ControllerEndpointBuilder`, `CoreCapabilityProbe`, `SmartXRedactor`, `SmartXManagedOverrideManager`, `LightGBMSettingsViewModel`, `TunLifecycleCoordinator`, `TunConfigValidator`, `DNSConfigValidator`, `DiagnosticsLogReader`, `DiagnosticsArtifactFormatter`, `DiagnosticsProviderFormatter`, `ProfileArtifactManager`, and the smoke harnesses in `Tests/SecurityHarness` are already first-pass groundwork in the current branch, not future introductions
- the helper boundary audit now adds `HelperStatus` plus `HelperDiagnosticsProbe`, but helper status remains diagnostic only and is not a helper-backed TUN capability

## Phase 3: Redaction and Diagnostics Safety

Scope:

- formalize SmartX redaction rules
- apply redaction consistently across copied reports, exported bundles, logs, paths, and controller metadata
- keep diagnostics terminology honest about what is and is not sanitized
- review sensitive-path and secret exposure risks before adding more export surfaces

This phase makes diagnostics safe enough to grow without quietly leaking subscription URLs, tokens, credentials, controller secrets, or unnecessary local path detail.

Expected outputs:

- shared redaction utilities are the norm, not ad hoc formatting
- diagnostics exports and copied reports use the same safety rules
- sanitization claims match actual redaction behavior

Testing gate:

- redaction fixtures or utility tests should be added whenever the rules change

## Phase 4: Diagnostics Dashboard Decomposition

Scope:

- split `DiagnosticsDashboardViewController` into smaller modules
- separate UI composition from API execution, formatting, recovery, and maintenance actions
- create testable utility and view-model seams
- keep diagnostics growth from turning into another monolithic controller

The current dashboard proved product value, but it is already too large. This phase is about structural cleanup before adding more panels.

Expected outputs:

- dashboard responsibilities are decomposed into smaller components
- formatting and maintenance logic are reusable outside the main controller
- diagnostics growth no longer depends on one giant view controller

Testing gate:

- extracted logic should be tested directly rather than only through controller wiring

## Phase 5: Profile Artifact Semantics and Override Groundwork

Scope:

- make profile artifact semantics explicit
- keep “successful reload artifact” and similar labels honest
- define what artifacts do and do not represent
- prepare the groundwork for a SmartX-managed override layer without pretending it already exists

The current artifact flow is still source-copy based. This phase should clean up semantics before SmartX tries to layer more behavior on top.

Expected outputs:

- artifact metadata clearly states whether content is a source copy, generated output, or override-aware material
- last-known-good semantics are documented and consistent
- groundwork exists for later persisted overrides without mutating terminology prematurely

Testing gate:

- artifact metadata and restore semantics should be covered with focused utility-level checks where practical

Current note:

- SmartX now keeps honest `Successful Reload Artifact` and `Last Known Good Config` aliases, but the artifact is still a loaded source copy rather than a true generated effective config
- Artifact metadata now distinguishes requested SmartX overrides from emitted SmartX overrides so source-copy artifacts do not overclaim transformed output

## Phase 6: SmartX Managed Override Layer

Scope:

- design a persisted SmartX-managed override layer
- stop relying on scattered runtime `RawConfig` mutation as the long-term model
- define how Smart settings, local adjustments, and future profile transforms should be represented
- keep override ownership explicit and inspectable

“Smart override” should mean a real SmartX-managed layer, not only whatever runtime patch happened to be applied last.

Expected outputs:

- SmartX owns a coherent override model
- override provenance is inspectable
- future config generation can build on explicit override inputs

Testing gate:

- override serialization, merge rules, and provenance logic should be tested as standalone logic

Current note:

- SmartX now has an initial persisted managed-override file for LightGBM settings under `.smartx/overrides`, but it is groundwork only and not a full effective-config generator
- `EffectiveConfigGenerator` currently remains an explicit unsupported boundary, records requested-versus-emitted override provenance separately, and current profile artifacts remain source-copy or successful-reload artifacts until a real generator writes a transformed config

## Phase 7: TUN-First Lifecycle

Scope:

- move beyond a guarded `tun.enable` config patch
- design preflight, enable, verify, rollback, disable, and recovery flow
- define what SmartX can support on macOS honestly
- keep helper presence distinct from actual TUN readiness

This phase is where SmartX earns the term “TUN lifecycle.” Until then, the UI should remain explicit that current support is partial.

Expected outputs:

- TUN operations are modeled as lifecycle steps rather than one config toggle
- failure and recovery paths are explicit
- unsupported or incomplete environments are surfaced honestly

Testing gate:

- lifecycle-state logic and failure transitions should be tested where direct system integration is not practical

Current note:

- SmartX now has an initial guarded `TunLifecycleCoordinator`, but embedded-core TUN remains explicitly unsupported and privileged TUN architecture is still a later prerequisite
- helper-aware TUN messaging is now in place, but external-controller TUN still stays on the controller API path and future helper-backed TUN still needs a separate command contract
- SmartX now also routes guarded config patching through narrower `ConfigAPI` helpers, but that is still external-controller lifecycle hardening rather than full TUN architecture

## Phase 8: DNS/TUN Validation Module

Scope:

- extract heuristic validation out of UI controllers
- build a shared validation module for DNS and TUN settings
- document supported checks, warning severity, and unsupported cases
- make validation reusable across settings, diagnostics, and future config generation flows

The current warnings are useful but incomplete. This phase turns them into a real validation module instead of keeping them as controller-local heuristics.

Expected outputs:

- DNS/TUN validation rules are centralized
- warning generation is testable

Current note:

- SmartX now has reusable `TunConfigValidator` and `DNSConfigValidator` utilities, but they are still a first-pass rule set rather than a full config-workspace validation system
- UI consumes validation results instead of hardcoding rule logic

Testing gate:

- validation rules should have direct fixtures or unit-style coverage

## Phase 9: Config Workspace

Scope:

- build the real config workspace model
- support explicit source, override, merge, and generated outputs
- define rollback and recovery semantics around generated effective config
- replace filename-era assumptions with a reproducible workspace pipeline

This phase is the larger config architecture that earlier artifact work only prepares for. It should not be confused with the current source-copy artifact model.

Expected outputs:

- generated effective config becomes an honest term backed by a real pipeline
- profile transforms are reproducible and inspectable
- rollback works against defined workspace artifacts rather than ad hoc copies

Testing gate:

- workspace transforms, rollback behavior, and artifact outputs should be covered directly

## Phase 10: Test Coverage and Legacy Hardening as a Continuous Gate

Scope:

- keep expanding coverage across diagnostics, capabilities, endpoints, artifacts, Smart logic, and TUN/DNS validation
- reduce dependence on inherited legacy behaviors that are hard to reason about
- harden migration edges and compatibility paths as ongoing work
- enforce that new architecture PRs do not regress safety or clarity

This is listed as a phase only because it needs explicit ownership, not because testing should wait until the end. Testing and legacy hardening are required in every phase and every focused PR.

Expected outputs:

- each architecture PR adds or updates appropriate coverage
- legacy compatibility paths become more explicit and less magical over time
- future SmartX work is gated by build health, test signal, and honest terminology

## What This Roadmap Does Not Mean

This roadmap does not authorize another large feature blob. It does not say “finish all SmartX UI first, then clean it up later.” It does not treat preview panels as completed architecture. It also does not treat testing as something to postpone until after the product shape is settled.

The intended sequencing is small PRs, each focused on one architectural improvement, one safety improvement, or one tightly-scoped user-facing follow-up built on those seams.
