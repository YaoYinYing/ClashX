# SmartX Diagnostics and Observability Memory

## Current Diagnostics

SmartX already has a meaningful diagnostics base, but it is split across several mechanisms and is still incomplete relative to a modern mihomo client.

### Logs

Current logging has two layers:

- app-side file logging through [`ClashX/Basic/Logger.swift`](/Users/yyy/Documents/protein_design/ClashX/ClashX/Basic/Logger.swift)
- core/controller log streaming through [`ClashX/General/ApiRequest.swift`](/Users/yyy/Documents/protein_design/ClashX/ClashX/General/ApiRequest.swift)

`Logger` uses CocoaLumberjack and keeps rolling log files. In Debug it also logs to the OS logger.

`ApiRequest` supports real-time log streaming through `/logs` over WebSocket when SmartX is talking to an HTTP controller. It also supports reconnect backoff for the log stream.

There is a second diagnostic log path in [`ClashX/ViewControllers/Connections/Requests/StructedLogReq.swift`](/Users/yyy/Documents/protein_design/ClashX/ClashX/ViewControllers/Connections/Requests/StructedLogReq.swift), which connects to `/logs?format=structured&level=...` and parses structured log events into temporary connection-like records.

### Traffic

Current traffic diagnostics also split by controller mode:

- embedded core mode uses direct Go-to-Swift callbacks set in [`ClashX/AppDelegate.swift`](/Users/yyy/Documents/protein_design/ClashX/ClashX/AppDelegate.swift) via `clash_setTrafficBlock` and `clashSetupTraffic()`
- external controller mode uses `/traffic` over WebSocket in `ApiRequest.requestTrafficInfo()`

This is already an important architectural distinction:

- embedded mode can push traffic directly through the Go bridge
- external mode depends on mihomo controller WebSockets

### Connections

Current connection diagnostics are reasonably strong for an older ClashX-derived client.

The main pieces are:

- [`ClashX/ViewControllers/Connections/Requests/ConnectionsReq.swift`](/Users/yyy/Documents/protein_design/ClashX/ClashX/ViewControllers/Connections/Requests/ConnectionsReq.swift), which connects to `/connections` over WebSocket
- [`ClashX/ViewControllers/Connections/ViewModels/ConnectionsViewModel.swift`](/Users/yyy/Documents/protein_design/ClashX/ClashX/ViewControllers/Connections/ViewModels/ConnectionsViewModel.swift), which merges live snapshots with process attribution and structured-log fallbacks
- [`ClashX/ViewControllers/Connections/ConnectionsViewController.swift`](/Users/yyy/Documents/protein_design/ClashX/ClashX/ViewControllers/Connections/ConnectionsViewController.swift), which renders recent and active connections
- [`ClashX/ViewControllers/Connections/ViewModels/ConnectionDetailViewModel.swift`](/Users/yyy/Documents/protein_design/ClashX/ClashX/ViewControllers/Connections/ViewModels/ConnectionDetailViewModel.swift), which prepares detail state for the selected connection

SmartX currently supports:

- recent connections view
- active connections view
- close connection action
- Smart block action for eligible connections
- speed and transfer counters
- process lookup via a direct embedded-core process table hook plus AppKit process metadata

### Dashboard behavior

The current dashboard container in [`ClashX/ViewControllers/Connections/DashboardViewController.swift`](/Users/yyy/Documents/protein_design/ClashX/ClashX/ViewControllers/Connections/DashboardViewController.swift) exposes three modes:

- Recent Connections
- Active Connections
- Smart

The Smart view is [`ClashX/ViewControllers/Connections/SmartDashboardViewController.swift`](/Users/yyy/Documents/protein_design/ClashX/ClashX/ViewControllers/Connections/SmartDashboardViewController.swift), which already surfaces:

- Smart groups
- node weights
- current node
- cache flush actions
- LightGBM model update action
- model file status and path

### Direct embedded callbacks vs external controller streams

This distinction should remain explicit in future work:

- embedded core currently uses direct callbacks for logs and traffic in `AppDelegate`
- external controller mode currently uses WebSocket controller APIs for logs, traffic, and connections

That means SmartX diagnostics are already partly capability-dependent even before a formal capability map exists.

## Connection Model

The current connection model lives in [`ClashX/Models/ClashConnection.swift`](/Users/yyy/Documents/protein_design/ClashX/ClashX/Models/ClashConnection.swift).

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

### memory usage stream

Mihomo exposes `/memory` for real-time memory information, but SmartX currently does not implement a memory stream or memory panel.

### DNS query tool

Mihomo exposes `/dns/query`, but SmartX does not yet provide a DNS query UI or API wrapper for interactive diagnostics.

### DNS cache flush

Mihomo exposes `/cache/dns/flush`, but SmartX currently only implements fake-IP cache flush.

### fake-ip cache flush

SmartX already implements `/cache/fakeip/flush` in `ApiRequest.resetFakeIpCache()`, but it is not yet presented as part of a broader DNS diagnostics toolset.

### core restart

Mihomo exposes `/restart`, but SmartX does not currently expose a restart diagnostic or recovery action through the API layer.

### core debug pprof helpers

Mihomo documents `/debug/gc` and `/debug/pprof` for debug builds or debug-level kernel runs, but SmartX has no helper UI for garbage collection, pprof browsing, or safe developer workflows around those endpoints.

### route explanation

The current connection UI shows chain, rule, and payload, but it does not yet explain the route decision in a structured, user-friendly way.

### rule hit explanation

The model already has enough raw data to show which rule matched, but not yet enough polished UI to explain:

- why the rule matched
- whether it came from a provider
- where the payload originated

### provider healthcheck status

`ApiRequest.healthCheck` exists for providers and groups, but there is no diagnostics panel that shows provider healthcheck history or status over time.

### smart decision explanation

SmartX can show weights and some Smart metadata, but it still cannot explain the full Smart decision path for one connection in a way users can inspect and trust.

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

## Logs

SmartX should eventually have a first-class log viewer instead of treating logs mainly as background files plus raw controller streams.

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

Recommended contents:

- build metadata
- core version
- OS version
- selected profile name
- redacted config summary
- recent logs
- endpoint capability map
- resource file status

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

This document is descriptive, not normative. The current implementation is defined by the source files in this repository, especially [`ClashX/General/ApiRequest.swift`](/Users/yyy/Documents/protein_design/ClashX/ClashX/General/ApiRequest.swift), [`ClashX/Models/ClashConnection.swift`](/Users/yyy/Documents/protein_design/ClashX/ClashX/Models/ClashConnection.swift), [`ClashX/ViewControllers/Connections/`](/Users/yyy/Documents/protein_design/ClashX/ClashX/ViewControllers/Connections), [`ClashX/Basic/Logger.swift`](/Users/yyy/Documents/protein_design/ClashX/ClashX/Basic/Logger.swift), and [`ClashX/AppDelegate.swift`](/Users/yyy/Documents/protein_design/ClashX/ClashX/AppDelegate.swift). Update this memory document when SmartX diagnostics or mihomo observability integration changes.
