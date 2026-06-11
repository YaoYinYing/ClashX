# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project identity

SmartX is an experimental macOS proxy client derived from ClashX, integrating the Vernesong Smart fork of mihomo through a Go c-archive bridge. This is a private preview hardening branch — not a production release, not a public fork. It does not provide proxy servers or subscriptions.

## Build and test commands

Before building, ensure Go, Ruby 3.2.4 (via rbenv), Bundler, and CocoaPods are set up. See README.md for setup details.

```bash
# Full dependency setup (Go archive, Pods, dashboard, GeoIP DB)
bash install_dependency.sh

# Open the workspace (always use .xcworkspace, never .xcodeproj)
open ClashX.xcworkspace
```

Always use the wrapper scripts instead of raw `xcodebuild`:

```bash
# Normal Debug build (output to .codex-logs/xcodebuild-debug.log)
scripts/codex-build-debug.sh

# Focused single test run
SMARTX_ONLY_TESTING='ClashXTests/ProfileParserTests' scripts/codex-test-focused.sh

# Release / signing / notarization checks
SMARTX_APP_PATH='build/Release/ClashX.app' scripts/codex-release-check.sh

# Shell-script linting
scripts/codex-lint-scripts.sh

# Project/dependency diagnostics
scripts/codex-diagnose-project.sh

# Workspace XML validation
bash scripts/ensure-xcworkspace.sh
```

For CI: unsigned Debug builds use `CODE_SIGNING_ALLOWED=NO`. Local Debug builds should pass `-quiet`, disable signing, and redirect full output to `.codex-logs/`. Release builds require signing identities that don't yet exist — SmartX is not ready for signed/notarized releases.

## High-level architecture

### Three-tier runtime model

1. **macOS AppKit shell** (`ClashX/`) — menu-bar app, settings windows, connection dashboard, Cocoa UI. Written in Swift with some ObjC bridging.
2. **Embedded Go core** (`ClashX/goClash/`) — Vernesong mihomo fork, compiled as a C static archive (`goClash.a`) via `-buildmode=c-archive`. The Go module declares `github.com/metacubex/mihomo` but uses a `replace` directive to point to `github.com/vernesong/mihomo`. Exported C symbols (`initClashCore`, `run`, `clashUpdateConfig`, `clash_setLightGBMOptions`, etc.) are called from Swift.
3. **Privileged helper** (`ProxyConfigHelper/`) — separate process for system proxy enable/disable only. Installed via SMJobBless (or legacy install path). Does NOT do TUN, DNS hijack, route manipulation, or shell execution.

### Dual controller mode

SmartX supports both **embedded-core mode** (direct Go bridge calls) and **external-controller mode** (HTTP/WebSocket to a separate mihomo process). `Settings.builtInApiMode` and `ConfigManager.apiUrl` determine the active mode. API wrappers in `ClashX/General/ApiRequest.swift` abstract this split but still carry significant legacy debt.

### Key managers (singletons in `ClashX/General/Managers/`)

- **`ConfigManager`** — active config selection, switching, built-in vs external controller mode. Now also has a lightweight profile inventory classifying configs as Local/Remote.
- **`PrivilegedHelperManager`** — helper installation, XPC connection, trust validation. Debug builds allow empty client requirement; Release builds reject it fail-closed.
- **`RemoteConfigManager`** — remote config download, validation, update. Validates filenames with strict allowlisting; falls back to SHA256-based names for invalid suggestions.
- **`TunLifecycleCoordinator`** — guarded TUN toggle lifecycle (external-controller only). Embedded-core TUN remains explicitly unsupported.
- **`CoreCapabilityProbe`** — probes `/version`, `/configs`, `/providers/proxies`, `/providers/rules`, `/memory` for capability detection. Mutating endpoints stay `unknown`/`unsupported` until user-triggered.
- **`ProfileArtifactManager`** — writes source-copy artifacts on successful reload to `~/.config/clash/.smartx/profiles/`. These are NOT generated effective configs — they're loaded source copies.
- **`SmartXManagedOverrideManager`** — persists LightGBM overrides to `.smartx/overrides/smartx-managed.json`. Groundwork only, not a full config generator.

### Key models (`ClashX/Models/`)

- **`ClashConfig`** — partial mihomo config model. TUN model covers ~12 fields (subset of full mihomo TUN surface). DNS model is read-only structured decode.
- **`ClashProxy`** — recognizes newer types: Smart, Wireguard, Hysteria, Hysteria2, Tuic, Vless, Masque, etc.
- **`ClashConnection`** — includes Smart metadata: `smartBlock`, `smartTarget`, GeoIP arrays, ASN strings.
- **`HelperCommandContract`** — typed model defining reserved future TUN commands (`tunPreflight`, `tunEnable`, `tunDisable`, etc.). Currently diagnostic-only; no helper-backed TUN execution exists.
- **`TunLifecycleDiagnostics`** — distinguishes passive snapshots, guarded enable requests, and guarded disable requests. Blocking validation applies only to enable; disable keeps validation warnings as warnings.

### API domain split (in progress)

`ClashX/General/Api/` now contains partial domain clients:
- `ConfigAPI`, `DiagnosticsAPI`, `SmartAPI`, `ProviderAPI`, `PolicyGroupAPI`, `ConnectionAPI`

`ApiRequest` remains the legacy facade. New endpoint work should use domain clients and `ControllerEndpointBuilder` (in `ClashX/General/Utils/`) instead of raw string concatenation.

### Config paths and security

All configs live under `~/.config/clash/`. `SafeConfigName` enforces strict validation before file path construction — no separators, no traversal, no hidden basenames, alphanumeric + ` _-.` only. SmartX artifacts live under `~/.config/clash/.smartx/` (profiles, overrides, diagnostics).

### UI surfaces

- **Settings → Core** (`CoreSettingViewController`) — status/control surface. Must degrade gracefully when core is stopped, `/configs` unavailable, or endpoints unsupported. TUN status reflects config only, not macOS TUN routing reality.
- **Smart Dashboard** (`SmartDashboardViewController`) — proxy group rankings, Smart weights, cache flush, LightGBM controls.
- **Diagnostics Dashboard** (`DiagnosticsDashboardViewController`) — memory snapshot, DNS query, cache flush, restart, GC, log viewer, diagnostics bundle export. Already too large; decomposition planned (Phase 4 roadmap).

### Test structure

Tests live in `Tests/SecurityHarness/` as smoke-level Swift scripts. They validate endpoint building, config validation, redaction, artifact metadata, capability cache identity, TUN lifecycle diagnostics, and route/DNS runtime probes. These are transitional smoke coverage, not high-coverage tests. XCTest targets exist but are minimal.

## Critical rules

### What to preserve
- AppKit + Cocoa patterns. No SwiftUI, Combine, or async/await rewrites unless explicitly requested.
- Existing ObjC, Swift, and project conventions. Match surrounding code style.
- Small focused patches over broad refactors. Don't rewrite large files for small changes.
- Don't rename public symbols, files, schemes, bundle IDs, or user-facing pref keys unless the task explicitly requires migration.

### High-risk areas
Proxy configuration, process lifecycle, profile migration, auto-start, privileged helper behavior, update logic, signing/notarization, credential handling. Never print secrets, tokens, proxy passwords, or signing identities.

### Capability-driven UI
UI decisions should be driven by runtime capability detection (`CoreCapability`), not `PRO_VERSION` macros or compile-time assumptions. Unsupported endpoints should disable only affected controls, not blank the whole page.

### Git discipline
Work on the `smartx` branch. Don't stage/commit unless explicitly asked. Keep unrelated formatting changes out of patches.

### Identity migration is pending
Bundle IDs, helper IDs, Mach service name, SMJobBless requirements, Sparkle feed, and iCloud containers still carry legacy ClashX-era values. Do not treat these as final SmartX identity — a separate signing migration PR is needed.

## Important references

- `docs/memory/` — 10+ memory documents covering implementation, build/release, core architecture, mihomo API, TUN/DNS roadmap, Smart/LightGBM, diagnostics, security, test strategy, and review findings. These are descriptive (not normative) and must be updated when implementation changes.
- `docs/architecture/` — helper boundary audit, helper command contract.
- `AGENTS.md` — root-level rules for AI agents working in this repo (superseded by this file for Claude Code, but still relevant).
