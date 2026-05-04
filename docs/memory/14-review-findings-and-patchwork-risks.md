# SmartX Review Findings and Patchwork Risks

## Current Findings Snapshot

SmartX has improved its foundation work, but several surfaces are still explicitly transitional.

- The LightGBM override now has a persisted SmartX-managed file, but it is still only groundwork for later effective-config generation.
- The current branch now has a narrow `EffectiveConfigGenerator` boundary, but it still reports unsupported until a safe YAML emit path exists and must not be treated as proof of generated-config support.
- Hidden SmartX override bootstrap side effects were reduced by removing migration writes from low-level Settings getters, but override migration is still a sensitive path because it bridges UserDefaults compatibility data and the managed JSON file.
- Profile artifact terminology is now more honest in new code and UI, but the compatibility `generated-effective.*` paths still exist until a real profile pipeline lands.
- TUN and DNS validation now live in reusable validators, and TUN toggling now has a named lifecycle coordinator, but embedded-core TUN remains unsupported and privileged TUN architecture is still missing.
- Diagnostics log viewing is safer because it now tails large rolling files instead of re-reading them whole every refresh cycle, and artifact/provider formatting moved into small helpers, but the Diagnostics dashboard remains structurally too large.
- `ApiRequest` is now partially decomposed into `DiagnosticsAPI`, `ProviderAPI`, `SmartAPI`, and `ConfigAPI`, but the compatibility facade still remains broader than it should be.

## Patchwork Risks To Keep Visible

- Do not let the managed override file be described as a full generated effective config pipeline.
- Do not let preserved future-schema override files be mistaken for a successful persisted save when SmartX only applied settings in memory.
- Do not let the initial `TunLifecycleCoordinator` be described as full TUN support.
- Do not treat the modern-only CI policy as proof of signed or notarized release readiness.
- Do not add new Smart dashboard or diagnostics logic by copying LightGBM save code or controller-specific validation checks back into view controllers.
- Do not grow `DiagnosticsDashboardViewController` further without extracting another helper or view-model seam to offset the added behavior.

## Follow-up Direction

- Promote the new smoke harnesses into a real Xcode test target when the repo is ready for one.
- Continue decomposing diagnostics helpers out of the dashboard controller.
- Insert SmartX storage isolation and privileged TUN architecture work before any roadmap phase that would otherwise imply those problems are solved.
