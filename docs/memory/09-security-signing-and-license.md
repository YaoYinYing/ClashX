# SmartX Security, Signing, and License Memory

## Current License

The repository is currently licensed under the GNU Affero General Public License v3, as shown in [`LICENSE`](../../LICENSE).

### Practical implications

For SmartX distribution, this means modified binaries should stay aligned with:

- corresponding source code
- build scripts
- dependency and packaging instructions needed to reproduce the release

Because this branch already depends on generated artifacts and downloaded resources, release discipline matters. A public SmartX release should keep the following aligned with the shipped binary:

- source tree for the exact release tag or commit
- Go build script and module wiring
- CocoaPods and SwiftPM manifests
- helper metadata and signing configuration
- resource-fetch or resource-pin policy

The memory point is simple: do not let release artifacts drift away from the corresponding source and build logic that produced them.

## Privileged Helper Risk

System proxy modification in SmartX depends on privileged helper behavior.

The relevant components are:

- [`ProxyConfigHelper/ProxyConfigHelper.m`](../../ProxyConfigHelper/ProxyConfigHelper.m)
- [`ProxyConfigHelper/Helper-Info.plist`](../../ProxyConfigHelper/Helper-Info.plist)
- [`ClashX/General/Managers/PrivilegedHelperManager.swift`](../../ClashX/General/Managers/PrivilegedHelperManager.swift)
- [`ClashX/General/Managers/PrivilegedHelperManager+Legacy.swift`](../../ClashX/General/Managers/PrivilegedHelperManager+Legacy.swift)
- [`ClashX/General/Managers/SystemProxyManager.swift`](../../ClashX/General/Managers/SystemProxyManager.swift)

### Current trust boundary

The helper is supposed to do one narrow job:

- read and modify macOS system proxy settings

It should not become a general privileged executor. The helper’s own comments and validation logic already move in that direction:

- it validates the connecting client with code-signing requirements
- it validates PAC URLs to local loopback HTTP(S) only
- it bounds ignore-list size and item length
- it only exposes proxy-setting operations over XPC

That is the correct direction, but the release identity is still inconsistent.

### Identity and signing drift that still exists

Before public distribution, SmartX must align:

- main app bundle identifier
- helper bundle identifier
- Mach service name
- Team ID / Developer ID requirement
- helper `AllowedClientCodeSigningRequirement`
- app `SMAuthorizedClients`
- app `SMPrivilegedExecutables`
- helper `SMAuthorizedClients`
- `SMJobBless` authorization strings and assumptions

The current repository still mixes:

- `com.doodlenet.ClashX`
- `com.west2online.ClashX`
- `com.west2online.ClashX.ProxyConfigHelper`
- legacy Team ID `MEWHFZ92DY`
- old certificate subject strings

That mixture is acceptable for branch memory and local debugging, but not for public release.

## Code Signing and Notarization

Before any public macOS release, SmartX needs a complete Apple distribution chain.

Required items:

- Developer ID certificate
- hardened runtime if needed
- signed app
- signed helper
- notarization
- stapling
- DMG signing if applicable
- Sparkle signing if update feed is used

### Signed app

The main app target must be signed with the final SmartX identity, not a leftover placeholder or historical ClashX identity.

### Signed helper

The privileged helper must be signed consistently with the app and with the final helper authorization requirements. Release helper trust must remain fail-closed.

### Notarization and stapling

Unsigned CI artifacts are useful for testing, but they are not release artifacts. A public build needs:

- notarization submission
- notarization success verification
- stapling to the final app or package artifact

### DMG signing

If SmartX is distributed in a DMG or installer package, that container should also follow a signed, verified release path rather than being treated as a generic zip export.

### Sparkle signing

If Sparkle remains in release scope, update security requires both a properly signed binary and a properly signed update feed.

## Bundle Identity Cleanup

The current branch still contains several inherited identities and metadata that must be reviewed and replaced or removed.

Examples visible in the current repository:

- old ClashX URL-type names in [`ClashX/Info.plist`](../../ClashX/Info.plist)
- old iCloud container `iCloud.com.west2online.ClashX`
- old helper bundle identifier and Mach service name
- old helper authorization strings
- old Sparkle feed URLs in updater code
- old AppCenter integration points
- legacy certificate requirements and Team ID placeholders

This is not just branding cleanup. These values affect:

- helper installation
- updater trust
- entitlements and cloud behavior
- analytics routing
- public release identity

Current note:

- User-facing SmartX branding can be cleaned up independently of the helper/signing migration.
- This repository may temporarily show SmartX in UI, README, and diagnostics while still retaining ClashX-era bundle IDs, helper IDs, Mach service names, and iCloud container identifiers for compatibility.
- That split is intentional until a later signing-migration PR replaces the remaining internal identifiers coherently.

## Privacy Review

SmartX inherits several privacy-sensitive surfaces that require explicit review before public release.

### analytics

The Podfile still includes:

- `AppCenter/Analytics`

`AppDelegate.registCrashLogger()` initializes AppCenter services when `AppCenterSecret` is non-empty. A public SmartX release should not inherit upstream analytics identifiers by accident.

### crash reporters

The Podfile also includes:

- `AppCenter/Crashes`

Crash reporting can be useful, but it must be explicitly owned and documented for SmartX.

### logs

Logs can contain:

- controller addresses
- errors from config reloads
- process names and paths
- helper install failures
- rule and routing hints

Future issue-report tooling must treat logs as potentially sensitive.

### diagnostics bundle

A future diagnostics bundle should be carefully redacted. It should be designed explicitly rather than assembled from raw app state.

### subscription URLs

Remote config URLs are sensitive operational data. They should not be copied into public issue reports or analytics payloads.

### external-controller secret

`ApiRequest.authHeader()` uses the controller secret. That value must never end up in logs, copied diagnostics, or exported support bundles.

### proxy credentials

Proxy credentials can appear in config or controller-managed state and must be treated as secrets.

### system proxy settings

`SystemProxyManager` and the helper can access current proxy state and restore state. That is operationally sensitive and should not be dumped casually into diagnostics.

### process path collection

`ConnectionsViewModel` enriches connections with:

- PID
- process name
- executable path
- icon

That is useful for diagnostics, but it is also privacy-sensitive data and should be handled accordingly in public reporting features.

### Public-release privacy rule

A public SmartX release should avoid inherited analytics identifiers and should require an explicit privacy decision for every telemetry or reporting service kept in scope.

## Update Security

Sparkle and release updates need a clean SmartX security model. The current code still carries inherited update-channel assumptions.

Relevant files:

- [`ClashX/General/Managers/AutoUpgardeManager.swift`](../../ClashX/General/Managers/AutoUpgardeManager.swift)
- [`ClashX/Info.plist`](../../ClashX/Info.plist)

Required future update-security rules:

- signed appcast
- trusted update channel
- no inherited upstream feed
- clear channel naming
- rollback behavior
- no silent major-channel switching

### Why this matters

The current repository still references inherited feeds such as:

- `https://yichengchen.github.io/clashX/appcast.xml`
- AppCenter-backed Sparkle feeds
- `SUFeedURL` placeholder `https://invalid.local/smartx/appcast.xml`

This is appropriate as a “do not use yet” state, but a public SmartX release must replace it with SmartX-owned update infrastructure or remove it from scope.

## Threat Model

SmartX is a local proxy client with a privileged helper and controller surface, so its threat model should stay concrete.

### malicious config

Threat:

- a remote or local config introduces unsafe behavior, hostile rules, or dangerous controller exposure

Current mitigations and needs:

- config verification exists
- path safety checks exist
- profile layering and safer validation are still future work

### leaked secret

Threat:

- controller secret leaks through logs, UI, issue bundles, or external-controller configuration

Needs:

- strict redaction discipline
- no secret logging
- careful support/export tooling

### unsafe external controller exposure

Threat:

- the controller is exposed on LAN or to an unexpected address

Current state:

- allow-LAN controls exist
- the embedded core tries to keep the controller loopback unless explicitly allowed

Still needed:

- clearer public-release threat communication
- capability-aware safety warnings

### tampered dashboard

Threat:

- downloaded dashboard assets are modified upstream or during transport

Current risk:

- dashboard resources are fetched from moving sources in the install flow

Needed:

- pinned versions or vendored assets
- reproducible resource policy

### tampered geo/model resource

Threat:

- MMDB or LightGBM assets are replaced with malicious or corrupted content

Needed:

- pinned sources
- integrity checks or stronger provenance controls

### privileged helper abuse

Threat:

- an attacker abuses the helper trust boundary to modify system proxy settings

Current mitigations:

- client signing validation
- release fail-closed behavior
- limited helper API surface

Remaining risk:

- identity migration is unfinished
- legacy fallback install paths still exist

### auto-update compromise

Threat:

- a compromised update feed or signing path delivers a malicious build

Needed:

- SmartX-owned update channel
- signed appcast
- signed binaries
- explicit channel and rollback policy

## Acceptance Criteria

### Public preview readiness

SmartX is ready for a public preview only when:

- app and helper identities are coherent and no longer mixed with legacy placeholders
- unsigned local-debug helper exceptions are clearly separated from release behavior
- release helper trust remains fail-closed
- inherited AppCenter/AppCenter-backed Sparkle assumptions are either replaced or disabled intentionally
- public preview artifacts are signed and notarized, or the preview is explicitly source-build-only
- diagnostics and logs are reviewed for secret leakage risk
- dashboard and resource supply-chain policy is documented
- README and release notes accurately state the current limitations

### Stable release readiness

SmartX is ready for a stable release only when:

- Developer ID signing is fully configured for app and helper
- notarization and stapling are automated and verified
- helper `SMAuthorizedClients`, `SMPrivilegedExecutables`, Mach service name, and bundle IDs are finalized
- Sparkle or alternative update infrastructure is SmartX-owned and securely signed
- inherited legacy identifiers, feeds, iCloud containers, and analytics metadata are removed or fully migrated
- privacy-sensitive diagnostics are redacted by design
- resource downloads are reproducible and integrity-controlled
- the release process has a corresponding-source discipline consistent with the repository license

## Source of Truth

This document is descriptive, not normative. The current implementation is defined by the source files in this repository, especially [`LICENSE`](../../LICENSE), [`README.md`](../../README.md), [`ClashX/Info.plist`](../../ClashX/Info.plist), [`ClashX/AppDelegate.swift`](../../ClashX/AppDelegate.swift), [`Podfile`](../../Podfile), [`ProxyConfigHelper/`](../../ProxyConfigHelper), [`ClashX/General/Managers/SystemProxyManager.swift`](../../ClashX/General/Managers/SystemProxyManager.swift), [`ClashX/General/Managers/PrivilegedHelperManager.swift`](../../ClashX/General/Managers/PrivilegedHelperManager.swift), and [`ClashX/General/Managers/AutoUpgardeManager.swift`](../../ClashX/General/Managers/AutoUpgardeManager.swift). Update this memory document when SmartX security, signing, or release policy changes.
