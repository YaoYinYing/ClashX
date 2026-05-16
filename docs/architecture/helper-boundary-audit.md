# SmartX Helper Boundary Audit

## Scope

This note documents the current privileged-helper boundary in SmartX after the bounded helper-audit patch from `docs/goals/may26-05.md`.

It is intentionally narrow:

- diagnostic only
- no new helper command surface
- no helper-backed TUN
- no signing or notarization migration
- no bundle identity migration

## Current helper contract

The privileged helper is still a system-proxy helper, not a general root executor.

Relevant files:

- `ProxyConfigHelper/ProxyConfigHelper.m`
- `ProxyConfigHelper/ProxyConfigRemoteProcessProtocol.h`
- `ProxyConfigHelper/Helper-Info.plist`
- `docs/architecture/helper-command-contract.md`
- `ClashX/Models/HelperCommandContract.swift`
- `ClashX/General/Utils/HelperCommandRegistry.swift`
- `ClashX/General/Managers/PrivilegedHelperManager.swift`
- `ClashX/General/Managers/PrivilegedHelperManager+Legacy.swift`
- `scripts/check_helper_requirement.py`

## Current helper identity

- Helper bundle identifier: `com.west2online.ClashX.ProxyConfigHelper`
- Launchd label / Mach service name: `com.west2online.ClashX.ProxyConfigHelper`
- Executable name: `com.west2online.ClashX.ProxyConfigHelper`
- App-side manager classes:
  - `PrivilegedHelperManager`
  - `PrivilegedHelperManager+Legacy`
  - `SystemProxyManager`
- Requirement-check script: `scripts/check_helper_requirement.py`
- Current bundle metadata note:
  - `Helper-Info.plist` uses `$(SMARTX_ALLOWED_CLIENT_REQUIREMENT)` for `AllowedClientCodeSigningRequirement`
  - helper trust remains intentionally split between Debug diagnostics and Release fail-closed checks

## Current helper responsibilities

Privileged helper responsibilities that exist today:

- system proxy enable / disable
- proxy restoration from current app state
- proxy-setting inspection
- helper version reporting for install/update checks
- helper blessing / install attempt through `SMJobBless`
- helper cleanup / reset behavior through the legacy install/remove path

TUN-related behavior that exists today:

- none in the helper command surface
- no privileged TUN startup
- no route ownership
- no helper-backed TUN preflight
- no helper-backed TUN verification or recovery

The live XPC contract remains bounded to proxy-setting operations:

- `getVersion`
- `enableProxyWithPort`
- `disableProxyWithFilterInterface`
- `restoreProxyWithCurrentPort`
- `getCurrentProxySetting`

The helper does not expose a TUN command contract. It does not create `utun` devices, elevate mihomo startup for TUN, or manage privileged route ownership for embedded-core TUN.

The app now also carries a typed helper command contract model and registry for diagnostics and future planning, but that model is descriptive only. It does not add new XPC methods and does not make helper-backed TUN executable.

## Privilege classification

### Privileged and necessary

- helper-side system proxy mutation
- helper-side proxy restoration
- `SMJobBless` install/update attempt for the proxy helper
- helper XPC client validation based on code-signing requirement metadata

### Privileged but legacy or unclear

- `PrivilegedHelperManager+Legacy.swift` AppleScript-driven shell install/remove path
- helper reset behavior that removes helper binaries and launchd plist through shell commands
- mixed legacy identity metadata such as inherited `SMAuthorizedClients` / `SMPrivilegedExecutables`

### Non-privileged and should stay in app

- helper diagnostics reporting
- helper requirement summary / fail-closed status explanation
- TUN status messaging
- diagnostics bundle/report rendering
- controller-side external `/configs` TUN patch path

### Future TUN-related but not implemented

- helper command contract for privileged TUN startup
- helper-aware TUN preflight that can verify real privileged prerequisites
- TUN runtime verification, rollback, and recovery
- any embedded-core TUN install or enable flow

## What this patch adds

This patch adds a read-only helper audit seam:

- `ClashX/Models/HelperStatus.swift`
- `ClashX/General/Managers/HelperDiagnosticsProbe.swift`

The probe reads safe local state only:

- bundled helper metadata
- helper requirement summary
- expected launchd label
- installed helper file presence

It does not:

- trigger `SMJobBless`
- install or uninstall the helper
- request admin authorization
- execute shell commands
- mutate system proxy state
- enable TUN

## Trust states

The new diagnostic model uses these trust states:

- `unknown`
- `unavailable`
- `unsignedDebugBuild`
- `requirementMismatch`
- `notInstalled`
- `installedButUnverified`
- `verified`

Current runtime probing is intentionally conservative. In ordinary app flows this patch typically reports:

- `unsignedDebugBuild` for Debug bundles with an empty helper requirement
- `requirementMismatch` for missing, empty outside Debug, or placeholder-like requirement metadata
- `notInstalled` when bundled metadata exists but the installed helper binary does not
- `installedButUnverified` when file-level evidence exists but no runtime XPC verification was attempted

`verified` is reserved for a future audited verification path and should not be implied by file presence alone.

## Risk inventory

### Generic command execution risk

The legacy helper install/remove path still builds and executes shell scripts with administrator privileges. That path should not grow and should not be reused for future helper/TUN behavior.

This PR now blocks that legacy fallback from being used through the audited install flow. The code remains in the repository as legacy compatibility residue, but the audited helper path fails closed instead of invoking it.

### Unsigned Debug build behavior

Debug builds may intentionally carry an empty helper client requirement for local development. That is acceptable for diagnostics, but it must not be mistaken for production-ready helper trust or successful `SMJobBless` installation behavior.

### Stale ClashX bundle/helper identity risk

The helper still inherits historical ClashX-era identities and authorization metadata. This patch does not migrate them and instead keeps the mismatch visible in diagnostics and docs.

### Launchd label mismatch risk

The app-side manager and helper metadata assume the legacy launchd label remains authoritative. A future identity migration must update that boundary coherently rather than piecemeal.

### Helper requirement mismatch risk

If `SMARTX_ALLOWED_CLIENT_REQUIREMENT` is missing, empty outside Debug, or placeholder-like, helper trust must be treated as mismatched. Release validation already checks this fail-closed path through `scripts/check_helper_requirement.py`.

### Silent helper failure risk

Before this patch, helper trust and helper absence were easier to conflate with general runtime failure. The new `HelperStatus` model and diagnostics probe reduce that ambiguity but do not yet verify live helper installation.

### TUN preflight ambiguity risk

Helper presence used to be easy to overread as possible TUN readiness. This patch makes the opposite boundary explicit: helper status is diagnostic only, external-controller TUN remains a controller API patch path, and embedded-core TUN remains unsupported.

## Current decision

SmartX must treat helper availability as a capability with explicit diagnostics.

SmartX must fail closed when helper identity, requirement, or install status cannot be trusted.

Current fail-closed behavior in this PR is intentionally narrow:

- Release helper requirement validation remains explicit and separate
- helper diagnostics report mismatch or unknown state rather than inferring success
- TUN messaging now states that helper status does not imply TUN support
- helper install now returns a structured guardrail failure when helper trust is weak before `SMJobBless`
- the audited install flow now suppresses the legacy shell-based fallback instead of invoking it
- no new privileged helper action is added when trust is weak

## Legacy risk that remains visible

`PrivilegedHelperManager+Legacy.swift` still contains an AppleScript `do shell script ... with administrator privileges` path that writes and executes a temporary shell script.

This patch does not expand that path and does not treat it as part of the audited helper contract.

It should be considered legacy compatibility behavior, not a model for future helper/TUN work.

Future helper-backed TUN work should proceed only through a separate, explicit helper command contract that is:

- narrowly scoped
- code-signed
- fail-closed
- testable without arbitrary shell execution
- typed at the command, input, output, and error-code level

## Future PR boundary

- PR14: audit and diagnostics only
- PR15: helper command contract
- PR16: helper-aware TUN preflight
- PR17: TUN runtime verification and recovery

## TUN boundary after this patch

`TunLifecycleCoordinator` is now helper-aware in messaging only.

What remains true:

- embedded-core TUN is still unsupported
- external-controller TUN is still only a guarded controller `/configs` patch path
- helper status is diagnostic only
- helper installation does not imply TUN readiness

Future helper-backed TUN requires a separate command contract and should not reuse system-proxy helper assumptions.
