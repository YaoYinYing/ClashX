# SmartX Memory Index

## Project Identity

`smartx` is an experimental modernization branch of ClashX. The branch keeps the native macOS ClashX shell, menus, settings, and connection views, while replacing or extending the embedded core integration toward a Vernesong mihomo smart core. The intent is to modernize core behavior and Smart features without rewriting the macOS app shell from scratch.

## Current Branch Scope

Compared with `main`, the current `smartx` branch work includes:

- Go core replacement and build-path changes under [ClashX/goClash/go.mod](../../ClashX/goClash/go.mod), [ClashX/goClash/main.go](../../ClashX/goClash/main.go), and [ClashX/goClash/build_clash_universal.py](../../ClashX/goClash/build_clash_universal.py), moving from Dreamacro Clash integration toward a Vernesong mihomo smart build path.
- Smart LightGBM settings and smart API additions in [ClashX/General/ApiRequest.swift](../../ClashX/General/ApiRequest.swift) and [ClashX/General/Managers/Settings.swift](../../ClashX/General/Managers/Settings.swift).
- TUN/Core settings UI work in [ClashX/ViewControllers/Settings/CoreSettingViewController.swift](../../ClashX/ViewControllers/Settings/CoreSettingViewController.swift), including status presentation, capability gating, and diagnostics.
- Smart dashboard work in [ClashX/ViewControllers/Connections/SmartDashboardViewController.swift](../../ClashX/ViewControllers/Connections/SmartDashboardViewController.swift).
- Updated proxy, provider, config, and connection models in [ClashX/Models/ClashConfig.swift](../../ClashX/Models/ClashConfig.swift), [ClashX/Models/ClashProxy.swift](../../ClashX/Models/ClashProxy.swift), [ClashX/Models/ClashProvider.swift](../../ClashX/Models/ClashProvider.swift), and [ClashX/Models/ClashConnection.swift](../../ClashX/Models/ClashConnection.swift).
- Build, dependency, and packaging adjustments in [ClashX/Info.plist](../../ClashX/Info.plist), [install_dependency.sh](../../install_dependency.sh), and [Podfile](../../Podfile).

This index is intentionally high level. Future topic documents should separate what is already implemented from what is only intended.

## Non-Goals

These memory docs must not claim:

- release readiness
- notarization readiness
- full ClashX Pro compatibility
- signed-distribution readiness
- validated runtime behavior beyond what source code, local builds, logs, or CI actually prove

If any of those become true later, the corresponding memory document must cite the exact evidence.

## Memory Documents

- [01-current-implementation.md](./01-current-implementation.md)
- [02-build-and-release.md](./02-build-and-release.md)
- [03-core-architecture.md](./03-core-architecture.md)
- [04-mihomo-api-and-capabilities.md](./04-mihomo-api-and-capabilities.md)
- [05-tun-and-dns-roadmap.md](./05-tun-and-dns-roadmap.md)
- [06-profile-and-config-enhancement.md](./06-profile-and-config-enhancement.md)
- [07-smart-core-and-lightgbm.md](./07-smart-core-and-lightgbm.md)
- [08-diagnostics-and-observability.md](./08-diagnostics-and-observability.md)
- [09-security-signing-and-license.md](./09-security-signing-and-license.md)
- [10-roadmap.md](./10-roadmap.md)

## Writing Rules for Future Memory Docs

1. Treat current source code as the source of truth.
2. Do not invent successful builds, tests, notarization, or runtime behavior.
3. Separate current implementation, planned work, risks, and open questions.
4. Mention exact file paths when discussing code.
5. Prefer small verifiable claims over broad claims.
6. Do not modify production source code while creating memory documents.
