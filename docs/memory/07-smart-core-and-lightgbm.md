# SmartX Smart Core and LightGBM Memory

## Current Smart Core Integration

The `smartx` branch integrates the Vernesong mihomo Smart fork through the existing Go c-archive bridge.

The key wiring is in [`ClashX/goClash/go.mod`](../../ClashX/goClash/go.mod):

- the required module path remains `github.com/metacubex/mihomo`
- the source is replaced with `github.com/vernesong/mihomo`

That works because the Vernesong fork still declares the `github.com/metacubex/mihomo` module path, so existing imports in [`ClashX/goClash/main.go`](../../ClashX/goClash/main.go) continue to compile unchanged.

In practice, SmartX therefore behaves like:

- Swift/AppKit shell
- Go c-archive bridge
- mihomo import path compatibility
- Vernesong Smart fork as the real core implementation

This is important memory for future work because the branch is not using a separate Smart-only Go package name. It is depending on replace-based module substitution.

## Current LightGBM Integration

The current user-facing LightGBM settings still bridge through [`ClashX/General/Managers/Settings.swift`](../../ClashX/General/Managers/Settings.swift), but they now persist through a SmartX-owned managed-override file handled by [`ClashX/General/Managers/SmartXManagedOverrideManager.swift`](../../ClashX/General/Managers/SmartXManagedOverrideManager.swift).

Current settings are:

- `smartLightGBMOverrideConfig`
- `smartLightGBMModelUrl`
- `smartLightGBMAutoUpdate`
- `smartLightGBMUpdateIntervalHours`
- `effectiveSmartLightGBMModelUrl`

The current intent is:

- by default, SmartX follows the core config unless override is enabled
- when override is enabled, SmartX supplies its own model URL and update policy
- if the stored model URL is empty, `effectiveSmartLightGBMModelUrl` falls back to the default Vernesong release URL
- SmartX persists the override under `~/.config/clash/.smartx/overrides/smartx-managed.json` instead of mutating remote subscription YAML
- `Paths.smartXManagedOverrideURL` is the concrete JSON path for that SmartX-owned override file
- the UserDefaults keys remain a compatibility cache, while the managed override file is the first durable SmartX-owned override source
- bootstrap into that file is now an explicit migration/setup step rather than a hidden Settings getter side effect
- SmartX preserves newer future-schema override files instead of overwriting them during normal UI saves

These values are passed from Swift to Go through the exported bridge function `clash_setLightGBMOptions`, which is defined in [`ClashX/goClash/main.go`](../../ClashX/goClash/main.go) and called by `Settings.syncSmartLightGBMOptionsToCore()`.

On the Go side, the current state is stored in:

- `smartLightGBMOverride`
- `smartLightGBMURL`
- `smartLightGBMAutoUpdate`
- `smartLightGBMUpdateInterval`

Those values are applied to `config.RawConfig` inside `applySmartLightGBMOverrides(rawCfg *config.RawConfig)`, which currently sets:

- `rawCfg.LgbmUrl`
- `rawCfg.LgbmAutoUpdate`
- `rawCfg.LgbmUpdateInterval`

The override is applied in both major core paths:

- initial startup via `parseDefaultConfigThenStart`
- config reload via `clashUpdateConfig`

That means SmartX’s LightGBM override is part of the embedded-core runtime path, but the current branch still does **not** implement a full generated effective config pipeline. The persisted override file is groundwork for later provenance-aware config generation, not proof that the profile pipeline already exists.

## File Paths

Current Smart-related file paths are defined in [`ClashX/Macro/Paths.swift`](../../ClashX/Macro/Paths.swift).

They are:

- `Model.bin` at `~/.config/clash/Model.bin`
- `smart_weight_data.csv` at `~/.config/clash/smart_weight_data.csv`

In code, these are exposed as:

- `Paths.smartLightGBMModelPath`
- `Paths.smartWeightDataPath`

This matches the branch’s continued use of `~/.config/clash/` as the core home directory, but it is probably not the final abstraction.

Future work will likely need a `CoreHome` or equivalent abstraction because:

- embedded and external/sidecar cores may not share one fixed home layout
- SmartX may eventually want Smart assets, generated configs, and profile overlays to live in more structured directories
- `Model.bin` and `smart_weight_data.csv` are logically core-runtime assets, not generic app preferences

## Smart API Endpoints

The current app uses or assumes the following Smart-related controller endpoints in [`ClashX/General/ApiRequest.swift`](../../ClashX/General/ApiRequest.swift):

- `/group/weights`
- `/group/:group/weights`
- `/cache/smart/flush`
- `/cache/smart/flush/:configName`
- `/connections/smart/:id`
- `/upgrade/lgbm`

### Current usage

Current call sites include:

- `requestSmartWeights()` for all groups
- `requestSmartWeights(group:)` for a specific group
- `flushSmartCache()` and `flushSmartCache(configName:)`
- `blockSmartConnection(_:)`
- `updateSmartLightGBMModel()`

### Capability probing needs

These endpoints should not be assumed to exist on every controller. The current branch already treats some of them as optional in practice, but the capability model is still incomplete.

The endpoints that most clearly need explicit capability probing are:

- `/group/weights`
- `/group/:group/weights`
- `/cache/smart/flush`
- `/cache/smart/flush/:configName`
- `/connections/smart/:id`
- `/upgrade/lgbm`

Current status by behavior:

- `SmartDashboardViewController` disables Smart dashboard actions when Smart weights fail and Smart groups exist
- `CoreSettingViewController` tracks whether `/upgrade/lgbm` appears supported or unsupported
- `updateSmartLightGBMModel()` currently maps `200` to success and `400` or `404` to unsupported

That is a reasonable first pass, but it is still endpoint-specific rather than a general capability framework.

## Smart Proxy Group Model

Smart is already represented in the proxy model as a first-class proxy-group type.

[`ClashX/Models/ClashProxy.swift`](../../ClashX/Models/ClashProxy.swift) defines:

- `ClashProxyType.smart = "Smart"`

It is also treated as:

- part of `proxyGroups`
- an automatic group in `isAutoGroup`
- a proxy-group type in `isProxyGroup(_:)`

That means the app already understands Smart groups as policy groups rather than ordinary leaf proxies.

UI implications:

- Smart groups should be displayed alongside other strategy groups
- they should keep their group identity in menus and dashboards
- the UI should distinguish the group itself from node weights and current node choice
- Smart-only controls should not appear for non-Smart groups

The current `SmartDashboardViewController` follows this model by filtering merged proxy data for groups where `type == .smart`.

## Smart Diagnostics

The current branch already exposes some Smart-related diagnostics, but only partially.

### Already present

- node weights from `/group/weights`
- Smart group membership and current node
- model file presence and modification time
- model path
- limited endpoint-supported vs unsupported status for LightGBM update
- connection metadata fields `smartTarget` and `smartBlock`
- structured connection-detail text that surfaces Smart target in the route summary and Smart block in the diagnostics summary
- a first-pass `Smart Explanation` block in connection detail that derives likely Smart group, current selected node, target rank/weight when available, top candidates, and local model-file status

### Future diagnostics to add

SmartX should eventually expose:

- show Smart target
- show Smart block reason
- show node weights
- show last model update
- show model file status
- show weight history if available
- explain decision path in connection detail

Recommended direction:

- `SmartDashboardViewController` remains the top-level Smart group view
- connection detail should surface `smartTarget` and `smartBlock` when present
- Core settings should summarize model health and endpoint availability
- future diagnostics can include “why this node was preferred” if the core exposes a usable decision trace

The key point is that Smart routing should eventually be observable, not just enabled.

The current branch now partially addresses the last point for individual connections, but only by inference. The connection detail panel can combine:

- `smartTarget`
- `smartBlock`
- current Smart groups from merged proxy data
- `/group/weights`
- local `Model.bin` file status

to produce a compact explanation block. This is still not a true decision trace from the core, because it cannot prove which internal scorer or fallback path produced the target.

## Failure Modes

The current Smart integration has several predictable failure modes.

### missing `Model.bin`

Both `SmartDashboardViewController` and `CoreSettingViewController` already check for the model file and can show it as missing. This is the simplest failure mode and should remain explicit in UI.

### failed LightGBM download

`/upgrade/lgbm` can fail even when the endpoint exists. In the current branch this is reported as `.failed`, but the exact reason is not deeply surfaced yet.

### unsupported endpoint

Some controllers will not support Smart-specific endpoints. The current branch already recognizes this for LightGBM update and partially for Smart weights, but broader probing is still needed.

### incompatible smart fork API

Because SmartX depends on Smart behavior through replace-based module wiring rather than a separate API version contract, future fork/API changes can break assumptions in:

- endpoint names
- response shapes
- config field names
- metadata fields such as connection Smart annotations

### stale model

A present `Model.bin` is not proof that the model is current or useful. SmartX currently shows modification time, but not staleness policy beyond auto-update interval settings.

### corrupted model

The file can exist while still being unusable or semantically invalid. The current UI only knows file existence and file metadata, not model integrity.

### smart group exists in config but core lacks smart capability

This is a real compatibility risk for future mixed-core operation:

- the config may contain Smart group definitions
- the controller may still reject Smart endpoints
- the UI may detect the group type from `/proxies` but fail to retrieve Smart weights or Smart cache behavior

That is why Smart group presence and Smart endpoint capability should be tracked separately.

## Acceptance Criteria

Smart support can be considered product-ready only when all of the following are true:

- Smart core identity is explicit and verifiable in build metadata.
- LightGBM override settings are persisted, applied deterministically, and reflected accurately in UI.
- Smart-related file paths are abstracted clearly enough to support future core-home changes.
- Smart endpoint availability is probed rather than assumed.
- The UI degrades gracefully when Smart endpoints are unsupported.
- Smart groups are shown as first-class policy groups with Smart-specific diagnostics.
- Connection details can surface Smart target and block metadata when present.
- Model file existence, freshness, and update status are visible to the user.
- Failed LightGBM downloads, unsupported endpoints, and missing model files produce actionable diagnostics.
- SmartX can distinguish “Smart config exists” from “Smart runtime capability is actually available.”

## Source of Truth

This document is descriptive, not normative. The current implementation is defined by the source files in this repository, especially [`ClashX/goClash/go.mod`](../../ClashX/goClash/go.mod), [`ClashX/goClash/main.go`](../../ClashX/goClash/main.go), [`ClashX/General/Managers/Settings.swift`](../../ClashX/General/Managers/Settings.swift), [`ClashX/Macro/Paths.swift`](../../ClashX/Macro/Paths.swift), [`ClashX/General/ApiRequest.swift`](../../ClashX/General/ApiRequest.swift), [`ClashX/Models/ClashProxy.swift`](../../ClashX/Models/ClashProxy.swift), [`ClashX/Models/ClashConnection.swift`](../../ClashX/Models/ClashConnection.swift), [`ClashX/ViewControllers/Settings/CoreSettingViewController.swift`](../../ClashX/ViewControllers/Settings/CoreSettingViewController.swift), and [`ClashX/ViewControllers/Connections/SmartDashboardViewController.swift`](../../ClashX/ViewControllers/Connections/SmartDashboardViewController.swift). Update this memory document when Smart endpoint coverage or LightGBM integration changes.
