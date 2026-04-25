# SmartX Core Architecture Memory

## Current Architecture

`smartx` currently embeds the Vernesong mihomo smart core through Go c-archive integration. The Go module declared in [ClashX/goClash/go.mod](/Users/yyy/Documents/protein_design/ClashX/ClashX/goClash/go.mod) depends on `github.com/metacubex/mihomo`, but the branch redirects that dependency with:

```go
replace github.com/metacubex/mihomo => github.com/vernesong/mihomo ...
```

This means the embedded core is effectively the Vernesong fork, but imported through the upstream mihomo module path because the fork declares that same path.

The native app embeds the core as a static Go c-archive built by [ClashX/goClash/build_clash_universal.py](/Users/yyy/Documents/protein_design/ClashX/ClashX/goClash/build_clash_universal.py). That script builds `arm64` and `amd64` archives with `-buildmode=c-archive`, merges them with `lipo`, and writes version metadata into [ClashX/Info.plist](/Users/yyy/Documents/protein_design/ClashX/ClashX/Info.plist) in CI environments.

The Swift-to-Go boundary is implemented through exported C-callable symbols in [ClashX/goClash/main.go](/Users/yyy/Documents/protein_design/ClashX/ClashX/goClash/main.go). Current exported functions include:

- `initClashCore`
- `run`
- `verifyClashConfig`
- `clashSetupLogger`
- `clashSetupTraffic`
- `clash_checkSecret`
- `clash_setSecret`
- `clash_setLightGBMOptions`
- `setUIPath`
- `clashUpdateConfig`
- `clashGetConfigs`
- `verifyGEOIPDataBase`
- `clash_getCountryForIp`
- `clash_closeAllConnections`
- `clash_getProggressInfo`

The macOS app uses these through the existing Swift and Objective-C bridge layer. Relevant app-side usage appears in:

- [ClashX/AppDelegate.swift](/Users/yyy/Documents/protein_design/ClashX/ClashX/AppDelegate.swift)
- [ClashX/General/ApiRequest.swift](/Users/yyy/Documents/protein_design/ClashX/ClashX/General/ApiRequest.swift)
- [ClashX/General/Managers/Settings.swift](/Users/yyy/Documents/protein_design/ClashX/ClashX/General/Managers/Settings.swift)

The effective runtime model is:

1. Swift launches the embedded core through `initClashCore()` and `run(...)`.
2. The Go side reads `~/.config/clash/config.yaml`, mutates `RawConfig`, parses it, and applies it in-process.
3. The app reads config either through direct Go bridge calls like `clashGetConfigs()` or through controller HTTP APIs, depending on `Settings.builtInApiMode` and override state.
4. Traffic and log callbacks can be delivered directly from the embedded core to the Swift UI through callback hooks configured in [ClashX/AppDelegate.swift](/Users/yyy/Documents/protein_design/ClashX/ClashX/AppDelegate.swift).

## Embedded Core Strengths

Embedded core integration remains attractive for a ClashX-style macOS client because it preserves the shape of the original application.

Current strengths include:

- Fewer moving parts. The app and core are distributed together rather than coordinated as separate executables.
- Native lifecycle fit. [ClashX/AppDelegate.swift](/Users/yyy/Documents/protein_design/ClashX/ClashX/AppDelegate.swift) can initialize, start, configure, and tear down the core using the same menu-bar app lifecycle it already uses.
- Direct log and traffic callbacks. `clashSetupLogger` and `clashSetupTraffic` allow the app to receive core signals without standing up separate IPC layers.
- Compatibility with existing ClashX architecture. The current app already expects a built-in mode with direct bridge calls and an optional external-controller mode. The embedded smart core keeps that dual-mode pattern intact rather than replacing it.
- Lower coordination overhead for Smart settings. Features such as `clash_setLightGBMOptions` let Swift push LightGBM settings straight into the in-process core configuration path.

## Embedded Core Weaknesses

The current embedded-core model also has structural drawbacks.

- Harder core switching. The core implementation is tied to the app bundle and c-archive build, so switching among stable, alpha, and smart variants is not a simple runtime selection problem.
- Weaker crash isolation. Core faults live inside the app process boundary, which increases the blast radius of core-level instability.
- Difficult hot upgrade path. The app can update resources and configs, but replacing the embedded core binary means rebuilding or redistributing the app.
- Larger app binary and tighter coupling. The application bundle owns more of the runtime stack directly, which increases artifact size and coupling between app and core versions.
- Harder compatibility matrix. The macOS app, embedded Go bridge, and selected mihomo fork/version have to remain mutually compatible at build time, not just at controller-API level.
- More difficult debug boundary. When the core is embedded, it is harder to isolate “Swift app problem” versus “Go core problem” versus “bridge problem” during debugging and crash triage.

## Future Sidecar Option

A future sidecar architecture would run mihomo as a separate executable process, controlled primarily through its external controller API.

In that model:

- ClashX would remain the native macOS shell.
- The core would be launched, supervised, and possibly updated as a separate executable.
- The app would consume controller HTTP/WebSocket APIs rather than in-process Go bridge functions for most runtime behavior.

This approach would make several things easier:

- switching between stable, alpha, and smart cores
- isolating core crashes from the macOS UI process
- updating or swapping cores without rebuilding the app
- aligning with modern mihomo client patterns that treat the core as a managed service rather than a library

It would also fit the branch’s growing use of controller-facing capabilities in [ClashX/General/ApiRequest.swift](/Users/yyy/Documents/protein_design/ClashX/ClashX/General/ApiRequest.swift), where Smart weights, cache flush, core version queries, and TUN config updates already assume an API-oriented interaction model.

That said, sidecar mode would add its own complexity:

- process supervision
- crash recovery and restart policy
- executable distribution and signing
- capability detection across multiple core builds
- filesystem layout and config sharing rules

## Hybrid Strategy

A reasonable migration strategy is hybrid rather than abrupt.

- Phase 1: keep the embedded smart core stable.
  The current branch already has working embedded-core wiring, direct callbacks, and LightGBM override injection. That path should remain the reference implementation until SmartX behavior is stable enough to compare alternatives.

- Phase 2: add metadata and capability detection.
  The app should clearly track which core build is running, which APIs it exposes, and which capabilities are available. Some of this already exists in [ClashX/General/Managers/Settings.swift](/Users/yyy/Documents/protein_design/ClashX/ClashX/General/Managers/Settings.swift) and [ClashX/Info.plist](/Users/yyy/Documents/protein_design/ClashX/ClashX/Info.plist), but it is incomplete.

- Phase 3: add optional external/sidecar core mode.
  Rather than replacing embedded mode immediately, the app could introduce an explicitly supported sidecar mode that uses the external controller API as its primary contract.

- Phase 4: allow users to switch stable, alpha, and smart cores.
  Once metadata, capability detection, and launch/supervision are reliable, the app could expose user-selectable core variants rather than coupling the app bundle to exactly one embedded core.

## Core Metadata

The branch already records some core metadata through [ClashX/Info.plist](/Users/yyy/Documents/protein_design/ClashX/ClashX/Info.plist) and exposes it through [ClashX/General/Managers/Settings.swift](/Users/yyy/Documents/protein_design/ClashX/ClashX/General/Managers/Settings.swift):

- `coreVersion`
- `gitCommit`
- `gitBranch`
- `buildTime`

Current display accessors include:

- `Settings.embeddedCoreVersion`
- `Settings.embeddedCoreCommit`
- `Settings.embeddedCoreBranch`
- `Settings.embeddedCoreBuildTime`

For future architecture work, core metadata should explicitly include:

- core version
- commit
- branch
- build time
- module path
- replacement target

For the current branch, that means recording not only the resolved version but also the fact that:

- the declared module path is `github.com/metacubex/mihomo`
- the replacement target is `github.com/vernesong/mihomo`

That distinction matters because the runtime identity and the Go import identity are not the same thing on `smartx`.

## Open Problems

- Should `smartx` keep `~/.config/clash` as the home directory, as it currently does in `initClashCore()`, or migrate toward a more mihomo-native path such as `~/.config/mihomo`?
- Should embedded and sidecar modes share the same profile directory, or should they use distinct runtime homes to reduce cross-mode state leakage?
- How should SAFE_PATHS and path-validation rules be handled for external configs, imported profiles, and sidecar-managed files? Some safer path work exists elsewhere in the branch, but the core architecture question is still open.
- How should core crash recovery be implemented for embedded mode? Today the app can start the embedded core, but the documentable long-term crash strategy is not yet clear.
- How should incompatible API endpoints be detected? The branch already handles some unsupported Smart and TUN paths pragmatically, but there is not yet a formal capability-negotiation layer.

## Acceptance Criteria

Embedded core mode should be considered verified only when all of the following can be demonstrated:

- the app initializes the embedded core through `initClashCore()` and `run(...)`
- the app can receive controller address and secret from the Go bridge
- direct bridge-dependent functions such as `clashGetConfigs()` or `clashUpdateConfig()` behave consistently in built-in mode
- log and traffic callbacks are observable from the embedded core
- core metadata shown in the UI matches the actual embedded build inputs

Future sidecar mode should be considered verified only when all of the following can be demonstrated:

- the app can launch or connect to a separate mihomo executable process
- controller capability detection distinguishes sidecar mode from embedded mode
- config apply, version query, and Smart capability checks work through controller APIs without relying on the Go bridge
- crash and restart behavior is defined and testable
- stable, alpha, and smart core variants can be distinguished and selected without rebuilding the app
