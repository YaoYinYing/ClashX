# SmartX Diagnostics and Observability Memory

## Current Diagnostics

SmartX already has a meaningful diagnostics base, but it is split across several mechanisms and is still incomplete relative to a modern mihomo client.

### Logs

Current logging has two layers:

- app-side file logging through [`ClashX/Basic/Logger.swift`](../../ClashX/Basic/Logger.swift)
- core/controller log streaming through [`ClashX/General/ApiRequest.swift`](../../ClashX/General/ApiRequest.swift)

`Logger` uses CocoaLumberjack and keeps rolling log files. In Debug it also logs to the OS logger.

`ApiRequest` supports real-time log streaming through `/logs` over WebSocket when SmartX is talking to an HTTP controller. It also supports reconnect backoff for the log stream.

There is a second diagnostic log path in [`ClashX/ViewControllers/Connections/Requests/StructedLogReq.swift`](../../ClashX/ViewControllers/Connections/Requests/StructedLogReq.swift), which connects to `/logs?format=structured&level=...` and parses structured log events into temporary connection-like records.

### Traffic

Current traffic diagnostics also split by controller mode:

- embedded core mode uses direct Go-to-Swift callbacks set in [`ClashX/AppDelegate.swift`](../../ClashX/AppDelegate.swift) via `clash_setTrafficBlock` and `clashSetupTraffic()`
- external controller mode uses `/traffic` over WebSocket in `ApiRequest.requestTrafficInfo()`

This is already an important architectural distinction:

- embedded mode can push traffic directly through the Go bridge
- external mode depends on mihomo controller WebSockets

### Connections

Current connection diagnostics are reasonably strong for an older ClashX-derived client.

The main pieces are:

- [`ClashX/ViewControllers/Connections/Requests/ConnectionsReq.swift`](../../ClashX/ViewControllers/Connections/Requests/ConnectionsReq.swift), which connects to `/connections` over WebSocket
- [`ClashX/ViewControllers/Connections/ViewModels/ConnectionsViewModel.swift`](../../ClashX/ViewControllers/Connections/ViewModels/ConnectionsViewModel.swift), which merges live snapshots with process attribution and structured-log fallbacks
- [`ClashX/ViewControllers/Connections/ConnectionsViewController.swift`](../../ClashX/ViewControllers/Connections/ConnectionsViewController.swift), which renders recent and active connections
- [`ClashX/ViewControllers/Connections/ViewModels/ConnectionDetailViewModel.swift`](../../ClashX/ViewControllers/Connections/ViewModels/ConnectionDetailViewModel.swift), which prepares detail state for the selected connection

SmartX currently supports:

- recent connections view
- active connections view
- close connection action
- Smart block action for eligible connections
- speed and transfer counters
- process lookup via a direct embedded-core process table hook plus AppKit process metadata

### Dashboard behavior

The current dashboard container in [`ClashX/ViewControllers/Connections/DashboardViewController.swift`](../../ClashX/ViewControllers/Connections/DashboardViewController.swift) exposes four modes:

- Recent Connections
- Active Connections
- Smart
- Diagnostics

The Smart view is [`ClashX/ViewControllers/Connections/SmartDashboardViewController.swift`](../../ClashX/ViewControllers/Connections/SmartDashboardViewController.swift), which already surfaces:

- Smart groups
- node weights
- current node
- cache flush actions
- LightGBM model update action
- model file status and path

The Diagnostics view is [`ClashX/ViewControllers/Connections/DiagnosticsDashboardViewController.swift`](../../ClashX/ViewControllers/Connections/DiagnosticsDashboardViewController.swift), which currently surfaces:

- `/memory` polling with raw JSON output
- `/dns/query` requests with raw JSON output
- DNS cache flush
- fake-IP cache flush
- core restart
- debug GC
- `POST /configs/geo`
- `POST /upgrade/geo`
- `POST /upgrade/ui`
- copy-to-pasteboard sanitized diagnostics report generation
- manual restore of the last-known-good profile artifact
- provider diagnostics for proxy/rule providers plus bulk proxy-provider healthcheck requests
- a lightweight in-app log viewer backed by the rolling app log file

These diagnostics actions now also feed a shared capability cache, so unsupported or unauthorized controller endpoints can be disabled after first contact instead of failing repeatedly every time the user opens the panel.

### Direct embedded callbacks vs external controller streams

This distinction should remain explicit in future work:

- embedded core currently uses direct callbacks for logs and traffic in `AppDelegate`
- external controller mode currently uses WebSocket controller APIs for logs, traffic, and connections

That means SmartX diagnostics are already partly capability-dependent even before a formal capability map exists.

## Connection Model

The current connection model lives in [`ClashX/Models/ClashConnection.swift`](../../ClashX/Models/ClashConnection.swift).

The richer connection snapshot type includes:

- `id`
- `chains`
- `metadata`
- `upload`
- `download`
- `start`
- `rule`
- `rulePayload`

### `chains`

`chains` is the proxy chain reported by the controller. It is already shown in the connection detail UI and should remain a core part of route explanation.

### `metadata`

`metadata` currently includes:

- `network`
- `type`
- `sourceIP`
- `destinationIP`
- `sourcePort`
- `destinationPort`
- `host`
- `dnsMode`
- `specialProxy`
- `processPath`

### `rule` and `rulePayload`

The model already records:

- matched rule name in `rule`
- matched rule data in `rulePayload`

The detail view model currently renders them together, but they should eventually become more structured UI.

### `processPath`

`processPath` is already modeled and used for process attribution. `ConnectionsViewModel` also augments the controller metadata with:

- `pid`
- `processName`
- `processImage`

### Source/destination geo information

The current model already supports:

- `sourceGeoIP`
- `destinationGeoIP`

These are not yet fully elevated into top-level UI sections, but they are included in the detail model’s “other text.”

### Source/destination ASN

The current model already supports:

- `sourceIPASN`
- `destinationIPASN`

Again, these are present in the detail pipeline, but not yet treated as a first-class observability feature set.

### `smartBlock`

`smartBlock` is already modeled and surfaced in the detail view model. It is one of the key Smart-specific observability fields.

### `smartTarget`

`smartTarget` is also already modeled and surfaced in the detail view model. The current UI even enables a Smart block action only when a connection is still connecting and `smartTarget` is present.

## Missing Diagnostics

Relative to current mihomo controller capabilities and modern client expectations, SmartX still lacks several observability features.

### memory usage stream history

SmartX now exposes `/memory` through a polling diagnostics panel, but it still does not implement a real-time memory stream or a historical memory timeline.

### DNS query workflow

SmartX now exposes `/dns/query` in the Diagnostics dashboard, but the current UI is still a raw-query tool rather than a polished DNS troubleshooting workflow.

### DNS cache flush

SmartX now exposes `/cache/dns/flush`, but it is still presented as a simple action rather than as part of a broader DNS diagnostic model.

### fake-ip cache flush

SmartX already implements `/cache/fakeip/flush` in `ApiRequest.resetFakeIpCache()`, but it is not yet presented as part of a broader DNS diagnostics toolset.

### debug pprof helpers

SmartX now exposes `/debug/gc` as a diagnostic action and also has a lightweight `/debug/pprof` helper path in the Diagnostics dashboard:

- copy the active controller's pprof URLs to the pasteboard
- include a reminder that Authorization headers must still be added manually when needed

This is still only a developer convenience helper, not a real profiling UI or capture workflow.

### route explanation

The connection detail UI is better than the original raw-field dump now. [`ClashX/ViewControllers/Connections/ViewModels/ConnectionDetailViewModel.swift`](../../ClashX/ViewControllers/Connections/ViewModels/ConnectionDetailViewModel.swift) now formats:

- a structured rule summary with matched rule and payload
- a route summary with selected proxy, hop path, and Smart target when present
- a richer diagnostics summary with start time, duration, process path, Smart block reason, and geo/ASN details

This is still text-first rather than a dedicated route-inspection UI, but it is now materially more explanatory than the old raw chain + payload display.

### rule hit explanation

The model already has enough raw data to show which rule matched, and SmartX now formats the matched rule and payload more clearly in the detail panel. It still does not explain:

- why the rule matched
- whether it came from a provider
- where the payload originated

### provider healthcheck status

`ApiRequest.healthCheck` exists for providers and groups, and the Diagnostics dashboard now exposes a lightweight provider diagnostics section:

- refresh proxy and rule provider lists
- show provider names, type, vehicle type, and proxy counts
- request bulk health checks for HTTP proxy providers
- append timestamped success/failure summaries to the diagnostics output
- persist a capped recent provider-health history under the SmartX diagnostics directory
- include recent provider-health history in the Diagnostics panel and copied/exported reports

This is still not full provider-health history over time, but it is better than having no provider observability surface at all. The current branch keeps a small local JSON-backed history for recent manual healthcheck runs; it does not yet build a continuous background timeline or provider trend analysis.

### smart decision explanation

SmartX can now surface Smart target and Smart block details more clearly inside the connection detail panel, but it still cannot explain the full Smart decision path for one connection in a way users can inspect and trust.

### process attribution

Process attribution exists, but it is still partly heuristic and dependent on:

- embedded process table access
- `NSRunningApplication`
- fallback path lookup

That should be treated as useful but not yet robustly explained or validated.

## Smart Connection Detail

A future SmartX connection detail panel should turn the current raw detail view into a structured diagnostic surface.

Recommended fields:

- process
- host
- destination IP and port
- network type
- matched rule
- rule payload
- chain
- selected proxy
- smart target
- smart block reason
- geo and ASN
- upload/download and speed
- close/block actions

### Mapping from current model

Most of the needed raw data already exists:

- process from `processName`, `pid`, `processImage`, `processPath`
- host from `metadata.host`
- destination from `destinationIP` and `destinationPort`
- network type from `metadata.network` and `metadata.type`
- matched rule from `rule`
- rule payload from `rulePayload`
- chain from `chains`
- selected proxy from the final element or interpreted chain view
- Smart target from `smartTarget`
- Smart block reason from `smartBlock`
- geo and ASN from the existing metadata arrays and strings
- transfer stats from upload/download and speed properties

The design gap is not raw data availability. It is presentation, structure, and explanation.

Current state is improved, but still partial:

- selected proxy and chain path are now summarized explicitly
- Smart target and Smart block are now surfaced in the route/detail text
- geo/ASN data and process path are now grouped into one diagnostic summary
- provider provenance and full decision reasoning are still missing

## Logs

SmartX should eventually have a first-class log viewer instead of treating logs mainly as background files plus raw controller streams.

The branch now has a meaningful first pass in the Diagnostics dashboard:

- reads the current rolling log file managed by `Logger`
- shows the last matching log lines in-app instead of only opening the file externally
- supports level filtering (`All`, `Error`, `Warning`, `Info`, `Debug`)
- supports text search
- supports pause/resume for automatic refresh
- supports export of the filtered plain-text view
- supports export of a sanitized diagnostics bundle for bug reports

Recommended features:

- level filter
- search
- pause/resume
- export
- copy issue report
- include core metadata
- include config name and profile pipeline status

### Why this matters

The current branch already has:

- rolling app logs through `Logger`
- core log streaming through `/logs`
- structured logs through `StructedLogReq`

A dedicated log viewer would unify these rather than leaving them scattered across diagnostics code, files, and transient connection synthesis.

The current implementation is still intentionally narrow:

- it is file-backed rather than a separate live controller-log pane
- it reads the latest rolling file instead of building a structured indexed log store
- plain log export still writes only the filtered text view, while the richer multi-file bundle lives in a separate export path

### Metadata to include

Future exported or copied log reports should include:

- app version/build
- embedded core version or external controller version
- controller mode
- active config/profile name
- profile pipeline status once that system exists

But they should avoid exposing secrets or full configs.

## Issue Report Bundle

SmartX should eventually produce a sanitized diagnostic bundle for bug reports and reproducible troubleshooting.

SmartX now has a first real bundle path through [`ClashX/General/Utils/DiagnosticsBundleExporter.swift`](../../ClashX/General/Utils/DiagnosticsBundleExporter.swift), plus the existing [`ClashX/General/Utils/DiagnosticsReportBuilder.swift`](../../ClashX/General/Utils/DiagnosticsReportBuilder.swift) and Diagnostics dashboard actions. The current bundle includes:

- app and OS metadata
- embedded/external controller mode
- selected config name
- capability-cache state
- resource file presence for `Model.bin`, `smart_weight_data.csv`, and `config.yaml`
- profile artifact presence for generated-effective and last-known-good config copies
- profile artifact metadata for selected profile/source/reload context
- log folder and latest log file path in the report
- a separate redacted recent-log snapshot built from the latest rolling log file
- a small machine-readable manifest with generation time, app build, controller mode, active profile, and active log filename

It intentionally redacts controller secrets by reducing the controller URL to scheme + host + port only.
The bundle exporter also redacts:

- absolute HTTP/HTTPS/WS/WSS URLs down to origin plus `/<redacted>`
- proxy URIs such as `ss://`, `vmess://`, `vless://`, `trojan://`, `hysteria2://`, or `tuic://`
- authorization-style values
- common token/secret/password key-value patterns

Recommended contents:

- build metadata
- core version
- OS version
- selected profile name
- redacted config summary
- recent logs
- endpoint capability map
- resource file status

What still remains:

- richer profile-pipeline metadata once that system exists
- richer and more formally reviewed subscription/source redaction policy beyond the current pattern-based sanitization
- fuller provider trend/history modeling beyond the current capped local manual-run history

Examples of resource file status:

- dashboard asset presence/version if tracked
- GEO database presence
- `Model.bin` presence and size
- Smart weight file presence

### Must not include

The bundle must not include:

- subscription URLs
- secrets
- proxy credentials

It should also avoid including raw controller authorization values, full remote-control URLs, or unredacted profile payloads.

## Acceptance Criteria

Diagnostics can be considered mature only when all of the following are true:

- SmartX has a clear diagnostics model for logs, traffic, connections, and memory.
- Embedded and external-controller observability differences are explicit in the UI and internal capability model.
- Connection detail surfaces rule, chain, process, geo/ASN, and Smart metadata in a structured way.
- DNS diagnostics include query and cache operations, or unsupported states are clearly reported.
- Smart-specific diagnostics can explain weights, Smart target, Smart block reason, and model state.
- Log viewing supports filtering, searching, pausing, and export.
- Issue-report bundles are useful for debugging but consistently redact secrets, subscription sources, and credentials.
- Unsupported controller debug endpoints degrade gracefully instead of failing silently or breaking the whole diagnostics view.
- Provider health and route/rule explanations are visible enough that users can understand why traffic took a given path.

## Source of Truth

This document is descriptive, not normative. The current implementation is defined by the source files in this repository, especially [`ClashX/General/ApiRequest.swift`](../../ClashX/General/ApiRequest.swift), [`ClashX/Models/ClashConnection.swift`](../../ClashX/Models/ClashConnection.swift), [`ClashX/ViewControllers/Connections/`](../../ClashX/ViewControllers/Connections), [`ClashX/Basic/Logger.swift`](../../ClashX/Basic/Logger.swift), and [`ClashX/AppDelegate.swift`](../../ClashX/AppDelegate.swift). Update this memory document when SmartX diagnostics or mihomo observability integration changes.
