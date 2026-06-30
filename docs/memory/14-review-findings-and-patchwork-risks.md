# SmartX Review Findings and Patchwork Risks

## Current Findings Snapshot

SmartX has improved its foundation work, but several surfaces are still explicitly transitional.

- The LightGBM override now has a persisted SmartX-managed file, but it is still only groundwork for later effective-config generation.
- The current branch now has a narrow `EffectiveConfigGenerator` boundary with structured provenance, but it still reports unsupported until a safe YAML emit path exists and must not be treated as proof of generated-config support; requested overrides and emitted overrides are now separate facts.
- Redactor and remote-profile decode coverage is now backed by both smoke harnesses AND the SmartXTests XCTest target (38 cases, 11 classes).
- Hidden SmartX override bootstrap side effects were reduced by removing migration writes from low-level Settings getters, but override migration is still a sensitive path because it bridges UserDefaults compatibility data and the managed JSON file.
- Profile artifact terminology is now more honest in new code and UI, but the compatibility `generated-effective.*` paths still exist until a real profile pipeline lands.
- TUN and DNS validation now live in reusable validators, TUN toggling now has a named lifecycle coordinator with preflight/patch/verify/rollback, and embedded-core TUN is now supported via file-based YAML update (ConfigYAMLEditor + Go bridge reload). Privileged helper-backed TUN architecture is still missing.
- The branch now has a helper boundary audit with `HelperStatus` and `HelperDiagnosticsProbe`, but that status is diagnostic only and must not be described as proof of helper-backed TUN or successful helper installation.
- The branch now also has a typed helper command contract model and registry, but reserved TUN commands must not be described as implemented helper-backed TUN behavior.
- The branch now also has a typed TUN lifecycle diagnostics boundary with operation-aware preflight semantics plus automatic rollback on verification failure; controller-config verification plus evidence layers still must not be described as route verification, DNS hijack verification, packet-flow verification, or full system-level TUN verification.
- The audited helper install flow now blocks the legacy shell fallback and returns a structured guardrail failure when helper trust is weak; the legacy code still exists as residue and should stay treated as historical risk, not supported architecture.
- Diagnostics log viewing is safer: `DiagnosticsLogReader` tails large files, `LogViewerViewModel` (extracted Phase 4) manages state, `DiagnosticsArtifactFormatter`/`DiagnosticsProviderFormatter` handle formatting, and `DiagnosticsMaintenanceCoordinator` handles dangerous actions. Dashboard is 781 lines (down from 854).
- `ApiRequest` is partially decomposed into domain clients; 6 thin wrapper methods deleted (PR #21). Remaining wrappers have active callers.
- `ProfileArtifactManager` and the smoke harnesses under `Tests/SecurityHarness` are first-pass groundwork, complemented by the SmartXTests XCTest bundle (38 tests).

## Patchwork Risks To Keep Visible

- Do not let the managed override file be described as a full generated effective config pipeline.
- Do not let requested SmartX overrides be described as emitted/generated overrides when the generator still returns an unsupported result.
- Do not let preserved future-schema override files be mistaken for a successful persisted save when SmartX only applied settings in memory.
- Do not let the initial `TunLifecycleCoordinator` be described as full TUN support.
- Do not let passive diagnostics snapshots be described as post-toggle verification, and do not let disable-path warnings be treated as enable-path hard blockers.
- Do not let helper diagnostic status be described as a verified privileged-helper install unless a real audited runtime verification path exists.
- Do not let reserved helper TUN command names be described as executable helper capabilities in the current branch.
- Do not let controller-config verification be described as full system-level TUN verification.
- Do not treat the legacy AppleScript shell-install fallback as a valid future helper or TUN contract.
- Do not treat the modern-only CI policy as proof of signed or notarized release readiness.
- Do not treat a locally skipped Xcode build or test step as evidence of a broken workspace when the actual blocker is simulator-service or cache-permission access in the host environment.
- Do not add new Smart dashboard or diagnostics logic by copying LightGBM save code or controller-specific validation checks back into view controllers.
- Do not grow `DiagnosticsDashboardViewController` further without extracting another helper or view-model seam to offset the added behavior.
- Do not treat unsigned DMG Finder layout metadata as a release-readiness gate; best-effort layout and clean fallback packaging are separate concerns.

## Follow-up Direction

- Promote the new smoke harnesses into a real Xcode test target when the repo is ready for one.
- Continue decomposing diagnostics helpers out of the dashboard controller.
- Keep future helper-backed TUN work behind a separate explicit helper command contract instead of extending the current system-proxy helper ad hoc.
- Keep future helper-backed TUN work typed, allowlisted, and free of arbitrary shell execution or generic root proxies.
- Insert SmartX storage isolation and privileged TUN architecture work before any roadmap phase that would otherwise imply those problems are solved.
