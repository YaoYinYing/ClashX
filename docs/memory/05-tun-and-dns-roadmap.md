# SmartX TUN and DNS Roadmap Memory

## Current TUN Support

SmartX currently has limited TUN awareness, not full TUN feature support.

The current Swift-side TUN model lives in [`ClashX/Models/ClashConfig.swift`](../../ClashX/Models/ClashConfig.swift) as `ClashConfig.Tun`. It currently models only these fields:

- `enable`
- `device`
- `stack`
- `dns-hijack`
- `auto-route`

The branch now also decodes several additional TUN fields into the Swift model for read-only inspection:

- `auto-detect-interface`
- `strict-route`
- `mtu`
- `udp-timeout`
- `route-address`
- `route-exclude-address`
- `include-interface`
- `exclude-interface`

The current Core settings UI in [`ClashX/ViewControllers/Settings/CoreSettingViewController.swift`](../../ClashX/ViewControllers/Settings/CoreSettingViewController.swift) can:

- show whether a `tun` section exists
- show limited details for `device`, `stack`, `auto-route`, and `dns-hijack`
- show whether `tun.enable` is currently true or false in config
- attempt a guarded `tun.enable` patch only for an external controller that exposed `tun` through `/configs`
- show additional read-only routing/interface/TUN values when present
- surface validator output from reusable `TunConfigValidator` and `DNSConfigValidator` helpers

The current update path in [`ClashX/General/ApiRequest.swift`](../../ClashX/General/ApiRequest.swift) is intentionally narrow:

- `updateTun(enable:)` only sends `PATCH /configs` with `{"tun":{"enable":...}}`

The current branch now routes that guarded patch through a narrower `ConfigAPI` helper plus `TunLifecycleCoordinator`, but it is still the same external-controller-only config-patch model rather than embedded-core TUN support.

That means the current branch now has an initial guarded TUN lifecycle coordinator around the limited config toggle, but it still does not provide a complete mihomo TUN editor, embedded-core TUN enablement, or a privileged macOS TUN startup architecture.

The current UI is also explicit that:

- embedded-core TUN remains disabled
- helper installation does not imply TUN support
- helper status is now surfaced as a diagnostic-only trust boundary and does not imply helper-backed TUN readiness
- failed TUN updates restore the previous UI state, and unverified TUN updates remain explicitly unverified instead of being treated as success
- SmartX refreshes the UI from controller state when possible after an unverified update, but it still does not implement controller rollback

The branch now also records helper-aware TUN boundary messaging through `TunLifecycleCoordinator`, but that is still messaging only:

- external-controller TUN remains a guarded controller API patch path
- embedded-core TUN remains unsupported
- future helper-backed TUN still requires a separate helper command contract

That helper command contract now exists as a typed model and diagnostics boundary in `HelperCommandContract.swift` plus `HelperCommandRegistry.swift`, but all TUN helper commands remain reserved only. No helper-backed TUN execution path exists.

The branch now also has a typed TUN lifecycle diagnostics boundary in `TunLifecycleDiagnostics.swift` plus `TunPreflightPlanner.swift`, a read-only runtime interface probe in `TunRuntimeInterfaceProbe.swift`, a read-only route-evidence probe in `TunRuntimeRouteProbe.swift`, and a read-only DNS runtime probe in `TunRuntimeDNSProbe.swift`. That boundary can explain blockers, warnings, helper-reserved state, controller-config verification, visible tun-like interface evidence, route-visible interface evidence, and DNS runtime summaries, but route evidence is not packet-flow proof, DNS runtime evidence is not DNS hijack proof, and packet-flow verification remains unimplemented.

## Missing TUN Fields

Based on current mihomo TUN configuration docs, SmartX will eventually need a broader model. The fields below are grouped by whether they are broadly relevant to macOS or mainly relevant to Linux/Android platforms.

### Fields already partially modeled but not fully surfaced

- `stack`
- `device`
- `auto-route`
- `dns-hijack`

These exist in the current Swift model, but the UI only displays them as status text. They are not yet first-class editable fields with validation.

### Important cross-platform or macOS-relevant fields to add

- `auto-detect-interface`
- `strict-route`
- `mtu`
- `udp-timeout`
- `route-address`
- `route-exclude-address`
- `include-interface`
- `exclude-interface`

These fields matter for a future serious TUN client because they affect routing behavior, compatibility, leakage risk, and how well TUN coexists with multiple interfaces or local subnets.

### Linux-specific or Linux-first fields

- `auto-redirect`
- `gso`
- `gso-max-size`
- `route-address-set`
- `route-exclude-address-set`
- `iproute2-table-index`
- `iproute2-rule-index`
- `endpoint-independent-nat`

These should not be treated as ordinary macOS settings. Some are Linux-only, and some depend on Linux routing or firewall infrastructure such as nftables.

### Linux/Android-oriented identity and package filters

- `include-uid`
- `include-uid-range`
- `exclude-uid`
- `exclude-uid-range`
- `include-android-user`
- `include-package`
- `exclude-package`

These are not normal first-wave macOS UI fields. SmartX should not pretend they are portable when they are mostly useful for Linux or Android routing models.

## macOS TUN Rules

For macOS, the TUN roadmap should keep several platform-specific rules explicit.

### Device naming

On macOS, TUN device naming should follow `utun`-style behavior rather than Linux-style assumptions. Even if mihomo allows a `device` field, the UI should present it in macOS terms and avoid teaching Linux naming patterns as if they were valid on macOS.

### DNS hijack expectations

Mihomo’s TUN documentation notes that automatic DNS hijack behavior has platform-specific limits. For macOS, SmartX should explain that LAN-directed DNS traffic is not automatically hijackable in the same way users might expect from other platforms.

That matters because users often assume:

- “TUN enabled” means all DNS is transparently captured
- helper installed means all routing and DNS behaviors are now privileged and complete

Neither assumption is currently true for SmartX.

### Route ownership and privilege

The branch should keep stating that macOS TUN support is a privileged-routing problem, not just a config-file problem. The current helper only manages system proxy state. It does not:

- create `utun` devices
- restart mihomo with elevated privileges
- manage route insertion
- manage DNS hijack outside what mihomo itself can do after startup

Future helper-backed TUN work must use typed allowlisted commands rather than shell scripts or generic root execution.

The branch now also has a read-only helper diagnostics probe and `HelperStatus` model so diagnostics can surface whether the helper boundary looks unknown, mismatched, not installed, or only installed-but-unverified. That probe is diagnostic only and does not perform privileged actions.

### UI messaging

macOS-specific warnings should be shown when enabling advanced TUN options such as:

- `strict-route`
- interface include/exclude rules
- route-address and route-exclude-address
- DNS hijack assumptions

The goal is to avoid a UI that makes Linux-centric TUN fields look trivially safe on macOS.

## Current DNS Support

DNS is not currently modeled as a first-class SmartX settings surface.

The current inspected files show:

- no Swift DNS settings model in `Settings.swift`
- no dedicated DNS model in `ClashConfig.swift`
- no DNS settings UI in `CoreSettingViewController`
- no dedicated DNS storage path in `Paths.swift`
- no separate embedded-core DNS override path in `main.go`

What exists today is mostly indirect:

- the core reads `~/.config/clash/config.yaml` in [`ClashX/goClash/main.go`](../../ClashX/goClash/main.go)
- SmartX can inspect the general config and patch a limited TUN value through `/configs`
- [`ClashX/General/ApiRequest.swift`](../../ClashX/General/ApiRequest.swift) now exposes DNS diagnostics helpers such as `/dns/query` and `/cache/dns/flush`
- [`ClashX/ViewControllers/Connections/DiagnosticsDashboardViewController.swift`](../../ClashX/ViewControllers/Connections/DiagnosticsDashboardViewController.swift) surfaces those helpers for manual diagnostics

The branch now also has a first-pass structured read-only DNS model in [`ClashX/Models/ClashConfig.swift`](../../ClashX/Models/ClashConfig.swift), and the Core settings page surfaces it as status text plus validation notes from the reusable DNS validator. The currently decoded fields include:

- `enable`
- `enhanced-mode`
- `fake-ip-range`
- `fake-ip-filter`
- `fake-ip-filter-mode`
- `nameserver`
- `fallback`
- `direct-nameserver`
- `respect-rules`
- `use-hosts`
- `use-system-hosts`
- `prefer-h3`
- `listen`

So DNS in the current branch is still primarily config-file-driven, not client-setting-driven, but it is no longer completely opaque in the UI.

## Future DNS Model

A future SmartX DNS settings model should cover the main mihomo DNS concepts explicitly rather than treating DNS as opaque YAML.

Recommended fields for a future DNS model:

- `enable`
- `enhanced-mode`
- `fake-ip-range`
- `fake-ip-filter`
- `fake-ip-filter-mode`
- `nameserver`
- `fallback`
- `fallback-filter`
- `nameserver-policy`
- `proxy-server-nameserver`
- `proxy-server-nameserver-policy`
- `direct-nameserver`
- `direct-nameserver-follow-policy`
- `respect-rules`
- `use-hosts`
- `use-system-hosts`
- `cache-algorithm`
- `prefer-h3`

Additional fields likely worth considering later if SmartX expands DNS support further:

- `listen`
- `default-nameserver`
- `fake-ip-range6`
- `fake-ip-ttl`
- IPv6 DNS behavior

The important architectural point is that DNS should become a structured model with validation and capability checks, not a raw text blob hidden inside config files.

## UX Principles

TUN and DNS are dangerous settings. SmartX should treat them as advanced networking controls, not as simple cosmetic toggles.

Recommended UI principles:

- Separate safe defaults from advanced options.
- Separate macOS-supported options from Linux/Android-only options.
- Provide validation before writing config.
- Explain when a feature is only represented in config and not fully managed by the app.
- Do not imply that helper installation equals TUN or DNS readiness.
- Prefer read-only status first, then carefully gated write controls.

For the first serious implementation pass, SmartX should likely group the UI into:

- safe/common settings
- advanced network behavior
- expert or platform-specific settings

## Validation Rules

A future structured TUN/DNS editor should validate aggressively before writing config.

### TUN validation

- `include-interface` and `exclude-interface` should not both be set without an explicit expert override path.
- `strict-route` should show a warning because it can break local workflows and increase compatibility risk.
- `route-address` and `route-exclude-address` should validate CIDR syntax.
- `mtu` should validate sensible numeric ranges.
- `udp-timeout` should validate as a positive integer.
- macOS UI should explain that Linux-only fields such as `auto-redirect`, `gso`, and UID/package filters are unavailable unless expert mode explicitly shows them.

### DNS validation

- `respect-rules` should warn when `proxy-server-nameserver` is empty, because routing-aware DNS without a clear proxy-side resolver setup is risky.
- `fake-ip` mode should explain compatibility implications for software that expects direct real-IP DNS answers.
- `nameserver`, `fallback`, `direct-nameserver`, and related lists should validate supported resolver syntax.
- `nameserver-policy` and `proxy-server-nameserver-policy` should validate mapping structure instead of accepting arbitrary text silently.
- `prefer-h3` should warn when combined with settings that already have known caveats, especially rule-respecting DNS behavior.

### Platform filtering

- macOS-first UI should hide Linux/Android-only fields by default.
- Expert mode may reveal them for config inspection, but SmartX should not present them as normal macOS controls unless the architecture actually supports them.

## Acceptance Criteria

TUN and DNS support can be called mature only when all of the following are true:

- SmartX models more than the current minimal `tun.enable` subset.
- The UI can read and validate the main macOS-relevant TUN fields without requiring users to hand-edit YAML for ordinary cases.
- The app clearly distinguishes config visibility from actual platform capability.
- Embedded-core TUN support has a real privileged architecture, or the UI continues to keep unsupported controls disabled.
- DNS is represented as a structured client model instead of remaining mostly opaque config-file state.
- Unsupported Linux/Android-only fields are clearly hidden, labeled, or placed behind expert mode on macOS.
- Validation prevents obviously dangerous or contradictory combinations before config writes.
- Unsupported endpoints or controller modes degrade gracefully instead of leaving blank UI or false-success states.
- User-facing messages explain DNS hijack and route side effects in platform-specific terms.

## Source of Truth

This document is descriptive, not normative. The current implementation is defined by the source files in this repository, especially [`ClashX/Models/ClashConfig.swift`](../../ClashX/Models/ClashConfig.swift), [`ClashX/ViewControllers/Settings/CoreSettingViewController.swift`](../../ClashX/ViewControllers/Settings/CoreSettingViewController.swift), [`ClashX/General/ApiRequest.swift`](../../ClashX/General/ApiRequest.swift), and [`ClashX/goClash/main.go`](../../ClashX/goClash/main.go). Update this memory document when the TUN or DNS model changes.
