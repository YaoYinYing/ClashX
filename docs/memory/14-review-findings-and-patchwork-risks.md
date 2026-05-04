# SmartX Review Findings and Patchwork Risks

## Current Findings Snapshot

SmartX has improved its foundation work, but several surfaces are still explicitly transitional.

- The LightGBM override now has a persisted SmartX-managed file, but it is still only groundwork for later effective-config generation.
- Profile artifact terminology is now more honest in new code and UI, but the compatibility `generated-effective.*` paths still exist until a real profile pipeline lands.
- TUN and DNS validation now live in reusable validators, and TUN toggling now has a named lifecycle coordinator, but embedded-core TUN remains unsupported and privileged TUN architecture is still missing.
- Diagnostics log viewing is safer because it now tails large rolling files instead of re-reading them whole every refresh cycle, but the Diagnostics dashboard remains structurally too large.

## Patchwork Risks To Keep Visible

- Do not let the managed override file be described as a full generated effective config pipeline.
- Do not let the initial `TunLifecycleCoordinator` be described as full TUN support.
- Do not add new Smart dashboard or diagnostics logic by copying LightGBM save code or controller-specific validation checks back into view controllers.
- Do not grow `DiagnosticsDashboardViewController` further without extracting another helper or view-model seam to offset the added behavior.

## Follow-up Direction

- Promote the new smoke harnesses into a real Xcode test target when the repo is ready for one.
- Continue decomposing diagnostics helpers out of the dashboard controller.
- Insert SmartX storage isolation and privileged TUN architecture work before any roadmap phase that would otherwise imply those problems are solved.
