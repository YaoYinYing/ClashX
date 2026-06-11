# SmartX Full TUN Feature Plan

## Scope and goal

Build a complete, honest, macOS-native TUN lifecycle for SmartX that covers preflight, enable (with utun creation, route insertion, DNS hijack), runtime verification, graceful disable, and rollback/recovery. The current branch has an external-controller `PATCH /configs {"tun":{"enable":...}}` guarded toggle — this plan replaces that config-only patch with real system-level TUN orchestration.

This plan is a design document, not a committed implementation schedule. It reflects the current architecture as of June 2026 and the 10-phase roadmap in `docs/memory/10-roadmap.md`.

## What already exists

Before designing new work, the current baseline:

| Layer | Status | What it does |
|-------|--------|--------------|
| `ClashConfig.Tun` | **read-only model** | Decodes 13 fields: `enable`, `device`, `stack`, `dns-hijack`, `auto-route`, `auto-detect-interface`, `strict-route`, `mtu`, `udp-timeout`, `route-address`, `route-exclude-address`, `include-interface`, `exclude-interface` |
| `ClashConfig.DNS` | **read-only model** | Decodes 13 fields: `enable`, `enhanced-mode`, `fake-ip-range`, `fake-ip-filter`, `fake-ip-filter-mode`, `nameserver`, `fallback`, `direct-nameserver`, `respect-rules`, `use-hosts`, `use-system-hosts`, `prefer-h3`, `listen` |
| `TunLifecycleCoordinator` | **external controller only** | Guards a `PATCH /configs` toggle through preflight→patch→re-read→verify. Embedded core returns `.unsupported` immediately. No utun, route, or DNS mutation. |
| `TunPreflightPlanner` | **designed, operational** | Builds structured preflight reports with blockers, warnings, helper trust state. Distinguishes passive snapshots, enable requests, and disable requests. Blocking validation only for enable. |
| `TunConfigValidator` | **designed, operational** | Validates include/exclude-interface conflicts, strict-route warnings, MTU ranges, udp-timeout positivity, CIDR syntax, device naming. Blocking + warning + info severity. |
| `DNSConfigValidator` | **designed, operational** | Validates respect-rules resolver gaps, fake-ip mode warnings, prefer-h3 combinations. Warning-only currently. |
| `TunRuntimeInterfaceProbe` | **read-only evidence** | Enumerates `getifaddrs()`, classifies utun/tun- prefixed interfaces. Reports `tunLikeInterfacePresent` / `noTunLikeInterface` / `unavailable`. |
| `TunRuntimeRouteProbe` | **read-only evidence** | Reads `SCDynamicStore` primary IPv4/IPv6 interfaces. Classifies tun-like route presence. No packet-flow proof. |
| `TunRuntimeDNSProbe` | **read-only evidence** | Reads `SCDynamicStore` DNS resolver config, scoped resolvers, server counts. No DNS hijack proof. |
| `TunLifecycleDiagnostics` | **typed model** | Full Codable model: `TunPreflightOperation`, `TunPreflightBlocker`, `TunVerificationScope`, `TunVerificationOutcome`, `TunRuntimeEvidenceState`, `TunRuntimeVerificationLevel`, etc. |
| `HelperCommandContract` | **typed model, reserved only** | Defines 7 reserved TUN commands (`tunPreflight`, `tunEnable`, `tunDisable`, `tunStatus`, `tunVerifyRoute`, `tunVerifyDNS`, `tunRollback`). All `.availability = .reserved`. No execution path exists. |
| `HelperCommandRegistry` | **registry** | Categorizes commands: implemented (5 system-proxy), reserved (7 TUN), forbidden. Renders diagnostics sections. |
| `HelperStatus` / `HelperDiagnosticsProbe` | **diagnostic only** | Reports helper trust state (unknown, mismatched, not-installed, installed-but-unverified). Does not perform privileged actions. |
| `PrivilegedHelperManager` | **system proxy only** | XPC to `ProxyConfigHelper` for proxy enable/disable/restore/read. SMJobBless install. Legacy shell fallback blocked fail-closed. |
| `ProxyConfigHelper` | **system proxy only** | ObjC privileged process. Reads/writes `SCPreferences` for HTTP/HTTPS/SOCKS proxy. No route, utun, DNS, or shell execution. |
| `CoreSettingViewController` | **UI** | Shows TUN/DNS status, enable checkbox (guarded), validation warnings, helper capability notes. TUN is still config-toggle only. |
| `CoreCapability` / `CoreCapabilityProbe` | **capability cache** | `tunConfigRead`, `tunGuardedUpdate` are probe states. Mutating endpoints stay `unknown`/`unsupported` until triggered. |

## What is missing (the gap)

1. **No utun device creation.** SmartX cannot bring a TUN interface up on macOS. This requires a privileged process with `NETunnel` entitlements or raw `socket(AF_SYSTEM, SOCK_DGRAM, SYSPROTO_CONTROL)` + `SCNetworkInterface` creation.

2. **No route management.** SmartX cannot add/remove routes through the helper. The current helper only touches `SCPreferences` proxy keys.

3. **No DNS hijack setup.** SmartX cannot redirect DNS traffic to the TUN interface at the system level. Mihomo's config-level `dns-hijack` only works once the TUN device exists and routes are in place.

4. **No helper-backed TUN execution path.** All 7 reserved TUN commands have typed descriptors but zero implementation in `ProxyConfigHelper.m` or the XPC protocol.

5. **No embedded-core TUN path.** `TunLifecycleCoordinator` immediately rejects embedded-core mode. The Go core can parse TUN config but has no privileged macOS process to create the device.

6. **No structured TUN/DNS config editor.** Users must hand-edit YAML. The UI only shows read-only status text + a single enable checkbox.

7. **No packet-flow verification.** Route and interface probes are read-only evidence with explicit disclaimers that they are not proof.

8. **No TUN recovery/rollback.** If a TUN enable partially succeeds (device created but routes fail), SmartX has no cleanup path.

## Architectural decisions to make before coding

### Decision 1: TUN privilege model

Three options exist for getting the elevated privileges needed for utun, routes, and DNS hijack on macOS:

**Option A: Extend `ProxyConfigHelper`** — Add typed TUN commands to the existing privileged helper. The helper already has SMJobBless installation and XPC. New XPC methods would handle utun creation, route insertion, DNS resolver configuration. Pro: reuses existing install/infra. Con: grows the helper's privilege surface; the helper was designed for proxy-only.

**Option B: `NetworkExtension` (`NEPacketTunnelProvider`)** — The canonical Apple path. SmartX becomes a VPN provider, mihomo runs inside the extension sandbox. Pro: Apple-supported, no root helper needed for utun, clean lifecycle, iOS/macOS cross-compat. Con: sandbox constraints, IPC complexity, may not fit mihomo's existing process model, extension packaging/signing overhead.

**Option C: Separate `TUNDaemon` helper** — A second privileged helper (or an SMAppService daemon) dedicated to TUN. Keeps proxy helper lean. Pro: separation of concerns. Con: two helpers to install, upgrade, and trust-validate; doubles the SMJobBless complexity.

**Recommendation:** Option A (extend `ProxyConfigHelper`) for the first implementation pass, with a hard constraint that all new TUN methods use the existing typed command contract (`tunPreflight`, `tunEnable`, etc.). This keeps one install flow, one trust boundary, and one XPC connection. The existing audit rules (no shell execution, no arbitrary routes, no generic root) remain intact. If the helper grows too large, split it later — but only after the contract is proven.

### Decision 2: TUN device creation mechanism

On macOS, creating a TUN device from a privileged (non-NetworkExtension) process requires:

1. `socket(AF_SYSTEM, SOCK_DGRAM, SYSPROTO_CONTROL)` to get a control socket
2. `CTLIOCGINFO` + `connect` to the `com.apple.net.utun_control` kernel control
3. The kernel returns the assigned `utunN` name
4. Configure the interface with `SIOCSIFADDR` and `SIOCSIFNETMASK`
5. Configure routes via `SCDynamicStore` or `route(8)`-equivalent syscalls
6. Configure DNS via `SCDynamicStore` or `/etc/resolver/` scoped resolvers

This is well-understood territory — many macOS VPN clients do exactly this. The risk is that Apple could tighten kernel-control access in future macOS releases (they've been pushing toward NetworkExtension for years).

**Recommendation:** Implement raw utun creation in the helper for now, behind the typed `tunEnable` command. Keep the implementation in a single, auditable ObjC file. Document that a future NetworkExtension migration may be necessary if Apple deprecates the utun control socket.

### Decision 3: Route and DNS strategy

Routes and DNS can be managed at three levels:

1. **Let mihomo handle it** — Mihomo already has `auto-route`, `strict-route`, `route-address`, `dns-hijack` config. If SmartX only creates the utun device and configures basic routes to point default traffic through it, mihomo handles the rest via its own TUN stack. This is the simplest approach.

2. **Helper manages all routes** — The helper inserts/deletes specific routes via `SCDynamicStore` or BSD routing socket. This gives SmartX full control but duplicates logic that mihomo already has.

3. **Hybrid** — Helper sets up the baseline (default route → utun, preserve LAN routes, configure DNS → utun). Mihomo handles dynamic routing inside the TUN stack.

**Recommendation:** Level 1 (let mihomo handle it) for the first pass. The helper's job is creating the utun device, assigning an IP, bringing it up, and pointing mihomo at it. Mihomo's existing `auto-route` and `dns-hijack` logic operates once the device exists. This keeps the helper as thin as possible — it creates the device, mihomo uses it.

### Decision 4: Embedded-core TUN

Current state: embedded-core TUN returns `.unsupported` immediately. The Go core can parse TUN config but has no privileged process to create macOS utun devices.

Options:
- **A:** Keep embedded-core TUN unsupported forever. Only external-controller mode gets TUN.
- **B:** Write a TUN device manager in Go (using `golang.org/x/sys/unix`) that the embedded core calls directly, plus a small privileged helper for the actual device creation.
- **C:** Route embedded-core TUN through the same helper as external-controller mode. The Swift layer asks the helper to create a utun device regardless of which mode mihomo runs in.

**Recommendation:** Option C. The TUN device creation is a macOS privilege problem, not a Go vs. controller problem. The same helper can serve both modes. The coordinator already distinguishes embedded vs. external — it just needs the blocking `guard !Settings.isUsingEmbeddedCore` removed once a real helper path exists.

## Implementation phases

### Phase A: Helper contract implementation (foundation)

**Goal:** Turn the 7 reserved TUN commands from typed descriptors into real XPC methods in `ProxyConfigHelper`.

**Files touched:**
- `ProxyConfigHelper/ProxyConfigRemoteProcessProtocol.h` — add 7 TUN method signatures
- `ProxyConfigHelper/ProxyConfigHelper.h` / `.m` — implement the 7 methods
- `ClashX/General/Managers/PrivilegedHelperManager.swift` — add TUN XPC call wrappers
- `ClashX/Models/HelperCommandContract.swift` — update availability from `.reserved` to `.implemented` for completed commands

**Specific work:**

1. **`tunPreflight`** — validate that the host can create a utun device. Check kernel control availability, verify no conflicting TUN interfaces already owned by SmartX, validate that the configured device name is available. Input: typed `TunPreflightRequest` (device name, IP range). Output: `TunPreflightResult` (ok/blocked-by-conflict/unsupported-host/error).

2. **`tunEnable`** — create a utun device, assign address, bring it up. Input: `TunEnableRequest` (device name hint, address CIDR, MTU, DNS server list, routing mode). Output: `TunEnableResult` (assigned utun name, assigned address, created routes summary).

3. **`tunDisable`** — tear down a SmartX-owned utun device, remove routes, restore DNS. Input: `TunDisableRequest` (utun device name). Output: `TunDisableResult` (torn-down interface, restored routes summary, restored DNS summary).

4. **`tunStatus`** — read current state of SmartX-owned TUN interfaces. Input: none (or device name hint). Output: `TunStatusResult` (interface present, address, routes, DNS state, mihomo config match).

5. **`tunVerifyRoute`** — check that expected routes are present on a given utun device. Input: `TunVerifyRouteRequest` (expected route table). Output: `TunVerifyRouteResult` (matches, mismatches, missing routes, unexpected routes).

6. **`tunVerifyDNS`** — check that DNS is correctly directed through the TUN interface. Input: `TunVerifyDNSRequest` (expected resolver config). Output: `TunVerifyDNSResult` (matches, mismatches, resolver state).

7. **`tunRollback`** — tear down whatever partial TUN state exists and restore the pre-TUN networking baseline. Input: `TunRollbackRequest` (last known good state snapshot). Output: `TunRollbackResult` (cleaned-up state, remaining artifacts, recommended next step).

**Helper implementation constraints (non-negotiable):**
- No `system()` / `popen()` / `NSTask` / `Process()` calls
- No raw shell command strings from the app
- No arbitrary route command — only allowlisted route operations through BSD routing socket or `SCDynamicStore`
- All operations must have structured error codes from `HelperCommandErrorCode`
- Must log audit trail for each privileged operation
- Must enforce a hard timeout per command (no hanging XPC calls)
- Must validate all input before touching system state
- Must never accept a user-provided executable path

**Verification:**
- Unit tests for each command's input validation
- Helper integration tests (run helper in test harness, verify utun created/torn down)
- Negative tests (invalid inputs rejected, unauthorized app rejected)
- `SMARTX_ONLY_TESTING='ClashXTests/TunHelperTests' scripts/codex-test-focused.sh`

### Phase B: Lifecycle coordinator upgrade

**Goal:** Replace the current `PATCH /configs` toggle with the full TUN lifecycle through the helper + controller.

**Files touched:**
- `ClashX/General/Managers/TunLifecycleCoordinator.swift` — major rewrite
- `ClashX/General/Managers/TunPreflightPlanner.swift` — extend for real system preflight
- `ClashX/Models/TunLifecycleDiagnostics.swift` — add new states for system-level operations

**New coordinator flow (enable):**
```
preflight(config validation + helper preflight + runtime probe)
  → (blocked?) → return .blockedByValidation / .unsupported
  → helper.tunEnable(device, address, mtu, dns, routes)
    → (helper fails?) → log, attempt rollback, return .failed
    → controller PATCH /configs {"tun":{"enable":true,"device":"utunN",...}}
      → (controller fails?) → helper.tunRollback(), return .failed
      → helper.tunVerifyRoute(expected_routes)
      → helper.tunVerifyDNS(expected_dns)
      → runtime probe confirmation (interface, route, DNS evidence)
        → return .success or .verified or .degraded
```

**New coordinator flow (disable):**
```
preflight(config check + helper status)
  → helper.tunDisable(device)
    → controller PATCH /configs {"tun":{"enable":false}}
      → helper.tunVerifyRoute(routes_removed)
      → runtime probe confirmation (no tun-like interface)
        → return .success or .partiallyDisabled
```

**New coordinator flow (recovery from crash/unexpected state):**
```
probe current state (helper.tunStatus + controller /configs + runtime probes)
  → (state consistent) → report ok
  → (state inconsistent) → offer recovery: restore from last known good or full rollback
    → helper.tunRollback(lastKnownGood)
    → notify user of recovery action
```

**Key changes to `TunLifecycleResult`:**
- Add `.verified` — controller config matches AND system state confirmed
- Add `.degraded` — controller config matches but some runtime verification inconclusive
- Add `.partiallyDisabled` — controller says disabled but tun-like evidence persists
- Add `.recovered` — recovery action completed, state consistent

**Remove the embedded-core hard block** — once the helper can create utun devices, embedded-core mode is no longer intrinsically unsupported. The coordinator should route through the helper regardless of core mode. The Go core parses TUN config; the helper creates the device.

**Verification:**
- Smoke tests covering each lifecycle transition (preflight→enable→verify→disable→verify)
- Failure injection tests (helper fails mid-enable, controller rejects config, route verification fails)
- Recovery tests (partial state cleanup, crash recovery)
- `SMARTX_ONLY_TESTING='ClashXTests/TunLifecycleTests' scripts/codex-test-focused.sh`

### Phase C: Structured TUN/DNS config editor

**Goal:** Replace hand-edited YAML with a structured UI for TUN and DNS settings in Core Settings.

**Files touched:**
- `ClashX/ViewControllers/Settings/CoreSettingViewController.swift` — add editing UI (or a new dedicated view controller)
- `ClashX/Models/ClashConfig.swift` — add mutable config patch generation
- New file: `ClashX/ViewControllers/Settings/TunConfigEditorViewController.swift` (or embed in Core)
- New file: `ClashX/ViewControllers/Settings/DNSConfigEditorViewController.swift`

**TUN editor fields:**
- **Safe/common:** `enable`, `device` (validated against utun pattern), `stack` (system/gvisor/lwip), `auto-route`, `auto-detect-interface`, `mtu` (576–9000 range validation), `udp-timeout`
- **Advanced:** `strict-route` (with macOS warning), `route-address`, `route-exclude-address` (CIDR validated), `include-interface`, `exclude-interface` (conflict warning when both set), `dns-hijack` (with macOS limitation note)
- **Hidden/macOS-irrelevant:** Linux-only fields (auto-redirect, gso, UID/package filters, iproute2 tables) — shown only when user explicitly enables expert mode

**DNS editor fields:**
- **Safe/common:** `enable`, `enhanced-mode` (redir-host/fake-ip), `nameserver` (list editor), `fallback` (list editor), `respect-rules`
- **Advanced:** `fake-ip-range`, `fake-ip-filter`, `fake-ip-filter-mode`, `direct-nameserver`, `use-hosts`, `use-system-hosts`, `prefer-h3` (with respect-rules combination warning), `listen`

**Validation integration:**
- Live validation from `TunConfigValidator` and `DNSConfigValidator` as user edits
- Blocking issues prevent save/apply
- Warnings shown inline with explanation
- "Reset to current config" button
- "Apply and restart TUN" vs "Apply only (TUN remains at current state)"

**Config write path:**
- Serialize edited TUN/DNS blocks to JSON
- `PATCH /configs` with the new partial config
- Verify the controller accepted the config
- If TUN is enabled, trigger the lifecycle coordinator to apply changes (disable→reconfigure→enable or hot-reload)

**Verification:**
- Round-trip: edit → save → read back → assert fields match
- Validation: enter invalid CIDR, assert blocking error
- macOS-specific: assert Linux-only fields hidden by default
- Warning display: set strict-route, assert warning shown
- Conflict detection: set both include-interface and exclude-interface, assert warning

### Phase D: Route verification and DNS hijack verification

**Goal:** Turn the read-only runtime probes into actual verification that proves TUN is working.

**Files touched:**
- `ClashX/General/Utils/TunRuntimeRouteProbe.swift` — add packet-flow evidence
- `ClashX/General/Utils/TunRuntimeDNSProbe.swift` — add hijack evidence
- `ProxyConfigHelper/ProxyConfigHelper.m` — implement `tunVerifyRoute` and `tunVerifyDNS`
- New file: `ClashX/General/Utils/TunPacketFlowProbe.swift`

**Route verification upgrade:**
- Read the full routing table via `SCDynamicStore` or BSD routing socket
- Compare against the expected route set from the TUN config
- Flag: missing default route, missing route-address entries, unexpected exclude-interface bypass
- Classify: full-match, partial-match (list which routes are missing), mismatch, unavailable
- **Packet-flow test:** Helper sends a small UDP probe through the TUN interface, verifies it egresses on the expected utun device. This is the first actual packet-flow proof.

**DNS hijack verification upgrade:**
- Read full `SCDynamicStore` DNS state
- Verify DNS servers are pointing to the TUN interface or mihomo's DNS listener
- Check scoped resolver configuration for specific domains
- **DNS capture test:** Send a DNS query through the system resolver, verify it routes through mihomo's DNS (check `/dns/query` response), not through the original upstream resolver. This proves DNS hijack is working.

**Verification levels after this phase:**
```
- controllerConfigOnly           (existing)
- interfacePresenceOnly           (existing)
- routeTableMatch                 (new)
- dnsResolverMatch                (new)
- packetFlowVerified              (new — premium verification)
```

**Verification:**
- Mock routing table, verify route comparison logic
- Mock DNS state, verify resolver comparison logic
- Integration: enable TUN, run packet flow test, disable TUN, verify no residual routes
- `SMARTX_ONLY_TESTING='ClashXTests/TunVerificationTests' scripts/codex-test-focused.sh`

### Phase E: Recovery and rollback

**Goal:** Graceful failure handling for every TUN lifecycle operation.

**Files touched:**
- `ClashX/General/Managers/TunLifecycleCoordinator.swift` — add recovery orchestration
- New file: `ClashX/General/Managers/TunRecoveryManager.swift`
- `ProxyConfigHelper/ProxyConfigHelper.m` — implement `tunRollback`
- `ClashX/Models/TunLifecycleDiagnostics.swift` — add recovery state model

**Recovery scenarios:**
1. **Helper fails during enable** — utun partially created. Rollback: tear down the partial utun, verify no residual routes.
2. **Controller rejects config after helper enable** — utun created but mihomo doesn't know about it. Rollback: tear down utun, log the mismatch.
3. **Route verification fails after enable** — utun created, mihomo configured, but routes didn't take. Rollback: full teardown + notify user.
4. **DNS hijack verification fails after enable** — TUN works, routing works, DNS didn't redirect. Partial recovery: log, let user decide.
5. **App crashes mid-operation** — On next launch, probe current state, detect partial TUN artifacts, offer recovery.
6. **System sleep/wake** — TUN interface might persist or vanish. On wake, probe and reconcile.

**Rollback guarantees:**
- Must be idempotent (safe to call multiple times)
- Must not leave the system in a worse state than before
- Must preserve the pre-TUN networking baseline
- Must log every action taken for audit

**Verification:**
- Inject failure at each step, verify rollback restores baseline
- Crash simulation: kill app mid-enable, relaunch, verify recovery detects and cleans up
- Sleep/wake cycle test
- `SMARTX_ONLY_TESTING='ClashXTests/TunRecoveryTests' scripts/codex-test-focused.sh`

### Phase F: UI completion and capability wiring

**Goal:** Wire the full TUN lifecycle into the Core Settings UI, Smart Dashboard, and Diagnostics Dashboard with honest capability-driven UI.

**Files touched:**
- `ClashX/ViewControllers/Settings/CoreSettingViewController.swift` — replace checkbox toggle with full lifecycle UI
- `ClashX/ViewControllers/Connections/DiagnosticsDashboardViewController.swift` — add TUN diagnostic actions
- `ClashX/General/Managers/CoreCapabilityProbe.swift` — add TUN capability probing

**Core Settings TUN panel upgrade:**
- Current state: single "Enable TUN" checkbox with guarded toggle
- New state:
  - **Status section:** TUN enabled/disabled, interface name, assigned address, routing mode, DNS state
  - **Control section:** "Start TUN" / "Stop TUN" buttons (not a checkbox) with confirmation
  - **Configuration section:** structured editor (Phase C)
  - **Verification section:** last verification result, route match status, DNS match status, packet-flow status
  - **Recovery section:** "Recover TUN" / "Reset TUN state" button (visible only when state is inconsistent)

**Diagnostics dashboard TUN additions:**
- "Verify TUN State" action (runs full verification)
- Route table viewer (read-only, redacted)
- DNS resolver state viewer (read-only, redacted)
- TUN interface details (address, MTU, packet counters if available)
- "Export TUN Diagnostics" into the existing diagnostics bundle

**Capability detection:**
- `CoreCapability` additions: `tunSystemEnable`, `tunSystemDisable`, `tunRouteVerify`, `tunDNSVerify`, `tunPacketFlowVerify`, `tunRecover`
- Probing: `CoreCapabilityProbe` checks whether helper responds to `tunPreflight` → marks `tunSystemEnable` as `available`
- UI degrades: if helper TUN commands are unavailable, show "Helper-backed TUN not available" with the fallback controller-only toggle

**Verification:**
- UI state matrix: test every combination of (TUN enabled/disabled × helper available/unavailable × controller running/stopped × embedded/external)
- Diagnostics export: verify TUN state included in bundle
- Accessibility: verify all states have descriptive text, not just icon changes

## Risk register

| Risk | Severity | Mitigation |
|------|----------|------------|
| Apple deprecates utun kernel control | High | Isolate utun creation in one ObjC file; document the NetworkExtension migration path |
| Helper privilege escalation via TUN commands | Critical | All TUN commands are typed + allowlisted; no shell execution; audit every input path; CI checks helper binary for forbidden symbols |
| Route misconfiguration breaks user networking | High | Preflight validates routes before applying; rollback restores baseline; never touch non-SmartX routes |
| DNS hijack breaks local DNS resolution | High | Verify DNS works before declaring success; respect existing `/etc/resolver` config; never overwrite user DNS without explicit opt-in |
| Embedded-core + helper TUN race | Medium | The coordinator serializes helper calls and controller calls in a defined order; helper device ownership is exclusive per SmartX instance |
| mihomo TUN stack version incompatibility | Medium | Capability probe checks `/version` for TUN support before attempting; different mihomo versions may need different utun configuration |
| SMJobBless still uses legacy signing IDs | High | This is a prerequisite — identity migration must complete before TUN helper commands ship in a signed build. Debug/unsigned builds can proceed earlier. |

## What this plan does NOT cover

- **NetworkExtension migration:** Documented as a future option but not in scope for the first implementation.
- **Linux/Windows TUN:** SmartX is macOS-only. Linux-only TUN fields stay hidden.
- **Kernel-bypass TUN (DPDK/XDP):** Not applicable to macOS.
- **Split tunneling by app:** Requires NetworkExtension (`NEPacketTunnelProvider` with `includeRoutes`/`excludeRoutes`). Out of scope.
- **IPv6 TUN:** mihomo TUN supports IPv6 but this plan focuses on IPv4 first. IPv6 verification added later.
- **iOS/iPadOS:** Different privilege model entirely. Not in scope.

## Sequence summary

```
Phase A: Helper contract implementation
    ↓ (helper can create/destroy utun, manage routes/DNS)
Phase B: Lifecycle coordinator upgrade
    ↓ (full enable→verify→disable→recover flows work)
Phase C: Structured TUN/DNS config editor
    ↓ (users don't need to hand-edit YAML for TUN/DNS)
Phase D: Route and DNS verification
    ↓ (actual proof that TUN is working, not just config state)
Phase E: Recovery and rollback
    ↓ (graceful failure handling for every edge case)
Phase F: UI completion and capability wiring
    ↓ (users see honest, clear TUN state everywhere)
```

Each phase produces a mergeable PR with its own tests. Phases are sequential (each depends on the previous) but each phase can be reviewed and tested independently before moving to the next.

## Alignment with existing roadmap

This plan maps to the current 10-phase roadmap (`docs/memory/10-roadmap.md`) as follows:

- **Phase 7 (TUN-First Lifecycle):** Covered by this plan's Phases A+B
- **Phase 8 (DNS/TUN Validation Module):** Covered by this plan's Phase C+D
- **Phase 9 (Config Workspace):** Covered by this plan's Phase C (structured editor)
- **Phase 10 (Test Coverage):** Continuous gate throughout this plan

This plan does not duplicate or replace the existing roadmap — it provides the detailed engineering design for the TUN-specific phases that the roadmap sketches at a higher level.
