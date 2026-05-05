# SmartX Profile and Config Enhancement Memory

## Current Config Model

SmartX still uses a largely ClashX-style config model centered on concrete YAML files rather than abstract profiles.

### Default config location

The current config home is still `~/.config/clash/`.

This is enforced in two places:

- [`ClashX/Macro/Paths.swift`](../../ClashX/Macro/Paths.swift), which defines `kConfigFolderPath`, `kDefaultConfigFilePath`, and `Paths.configDirectoryURL`
- [`ClashX/goClash/main.go`](../../ClashX/goClash/main.go), where `initClashCore()` sets the mihomo home directory and config path to `~/.config/clash/config.yaml`

### Default config file

The default active config file is still `config.yaml`.

`ConfigFileManager.copySampleConfigIfNeed()` creates it from the bundled sample config if it is missing, and `ConfigFileManager.backupAndRemoveConfigFile()` still treats `config.yaml` as the primary live config file.

### Config switching

Config switching is filename-based, not profile-based.

[`ClashX/General/Managers/ConfigManager.swift`](../../ClashX/General/Managers/ConfigManager.swift) stores the active selection as `selectConfigName`, and the app treats that value as the selected local config name. The selected config is resolved to:

- `~/.config/clash/<name>.yaml` for local mode
- an iCloud path when iCloud config storage is enabled

The config list is derived by enumerating `.yaml` files under the config directory, not by reading structured profile metadata.

There is now a small metadata bridge in [`ClashX/General/Managers/ConfigManager.swift`](../../ClashX/General/Managers/ConfigManager.swift) that derives `ConfigProfileDescriptor` values for the current selectable configs. That layer can currently label configs as `Local` or `Remote`, surface source URL vs local cache path, and report last-update state for remote-backed configs.

For remote-backed configs, the branch now also persists and surfaces:

- validation status from the last attempted update
- last fetch result summary
- last error message when a fetch or validation step fails

Important limitation: this is only an inventory/provenance layer. The active selection is still `selectConfigName`, and reload still happens by resolving that name back to a concrete YAML file.

### Remote config update

[`ClashX/General/Managers/RemoteConfigManager.swift`](../../ClashX/General/Managers/RemoteConfigManager.swift) implements remote config updates by:

- storing a list of `RemoteConfigModel` entries in user defaults
- downloading remote YAML text
- validating it with `verifyClashConfig`
- atomically writing it to a named local config file

This is still “download subscription and replace local YAML,” not modern profile layering.

Important current behaviors:

- remote configs are identified mainly by `name` plus `url`
- a remote config can rename itself based on the suggested filename
- remote config updates preserve the last valid file on failure
- auto-update is timer-based through `NSBackgroundActivityScheduler`

The current UI now exposes some of that provenance more explicitly:

- the config switch menu shows `Local` vs `Remote` badges derived from the inventory layer
- remote-config table rows expose cache-file, validation, and last-fetch metadata through tooltips
- the diagnostics report includes the active profile type, source, validation, cache/update status, and last-fetch summary

That is useful progress for observability, but it is not yet the profile-window redesign described later in this document.

### Direct config reload

[`ClashX/General/ApiRequest.swift`](../../ClashX/General/ApiRequest.swift) and [`ClashX/AppDelegate.swift`](../../ClashX/AppDelegate.swift) still implement reload as “take a file path and reload it into the active core.”

Current reload paths:

- embedded mode uses exported Go functions such as `clashUpdateConfig`
- external-controller mode uses `PUT /configs` with a file path

That means the application’s config lifecycle is still centered on mutable files and direct reload operations rather than a profile graph or generated effective config.

There is now a limited artifact layer around that reload path:

- after a successful reload, SmartX copies the selected source YAML into `~/.config/clash/.smartx/profiles/generated-effective.yaml`, now surfaced in the UI as the `Successful Reload Artifact`
- the same successful reload also refreshes `~/.config/clash/.smartx/profiles/last-known-good.yaml`
- matching JSON metadata files record profile name, profile kind, source path, remote URL, generation time, and controller mode

This is still not a true merge/script/generated pipeline, because the compatibility `generated-effective.*` files are currently just deterministic copies of the exact file that was successfully loaded. New code should treat them as `Successful Reload Artifact` / `Loaded Source Copy` semantics until the real profile pipeline lands.

### URL scheme import and update

The current README and `AppDelegate.handleURL` support:

- `clash://install-config?url=...&name=...`
- `clash://update-config`

The `install-config` scheme currently opens the remote config UI flow and injects a downloaded remote config definition. This is still conceptually “add another named YAML source,” not “create a managed profile.”

### External controller entries

[`ClashX/General/Managers/RemoteControlManager.swift`](../../ClashX/General/Managers/RemoteControlManager.swift) stores external controller connections separately from local config files. Those entries are runtime controller targets, not local profiles. That distinction matters for the future model.

## Problem Statement

Modern mihomo clients need profile management rather than direct YAML mutation.

The current ClashX-style model has several structural weaknesses:

- the active unit is a file name, not a managed profile object
- remote subscriptions overwrite local YAML targets directly
- local customization and downloaded content are mixed together
- there is no formal notion of overlays, merges, or generated effective configs
- rollback is file-level and ad hoc, not pipeline-level
- there is no first-class place for script-based transformation

This becomes a serious limitation as soon as SmartX wants to support:

- remote subscriptions plus local overrides
- reusable rule/proxy overlays
- Smart-specific tuning layers
- generated effective configs
- deterministic rollback after failed transforms
- profile metadata such as update status, validation state, and source type

In short, direct YAML switching worked for old ClashX, but it is too primitive for a modern mihomo client that may combine embedded, external, Smart, and future sidecar core modes.

## Proposed Profile Types

SmartX should evolve from “selected config filename” to “selected effective profile pipeline.”

### Remote profile

A Remote profile represents a fetched upstream config source.

Expected properties:

- source URL
- display name
- last update time
- update policy
- validation status
- last fetch result
- optional subscription traffic metadata if exposed by headers

The base remote payload should remain read-only after fetch.

### Local profile

A Local profile represents a user-authored or imported local YAML file.

Expected properties:

- file location
- display name
- validation status
- editable flag
- provenance such as imported/manual/generated

This is the natural replacement for the current “named YAML file under `~/.config/clash/`” model.

### Merge profile

A Merge profile is an overlay profile that modifies another base profile without mutating the base source directly.

This is where users should express local rule/proxy additions, local providers, Smart overlays, and small field overrides.

### Script profile

A Script profile is a controlled transformation step that consumes config input and produces transformed config output.

This should be treated as a config-processing stage, not as arbitrary app extension logic.

### Generated effective profile

A Generated effective profile is the concrete config that SmartX actually hands to mihomo after all enabled profile layers are applied.

This should be:

- reproducible
- inspectable
- disposable
- safe to overwrite on regeneration

### Last-known-good profile snapshot

A Last-known-good profile snapshot is the most recent successfully loaded source-copy artifact that SmartX kept as a rollback anchor.

This is the rollback anchor when:

- a merge layer becomes invalid
- a script transform fails
- the generated config parses but core reload fails

The branch now has a first-pass version of this idea for the legacy filename-based flow. On successful reload, the loaded config file is copied to a last-known-good artifact path with metadata. The Diagnostics dashboard can now explicitly restore that artifact into the running core. This is still not automatic rollback, and it is still not driven by a layered effective-profile pipeline, but it does provide a concrete rollback anchor plus a manual restore path.

The current branch also has a tiny `EffectiveConfigGenerator` boundary, but it still returns an explicit unsupported result because SmartX does not yet have a safe YAML parse-emit path for generating base config plus managed LightGBM override. Source-copy artifact semantics therefore remain the honest current behavior.

## Merge Profile Design

Merge profiles should support constrained, explicit operations rather than raw arbitrary patching.

### Intended merge operations

- `prepend-rules`
- `append-rules`
- `prepend-proxies`
- `append-proxies`
- `prepend-proxy-groups`
- `append-proxy-groups`
- `prepend-rule-providers`
- `append-rule-providers`
- direct override of selected mihomo fields

### Why this design

This design lets SmartX preserve the original remote or local base profile while still supporting the common real-world tasks users need:

- adding extra routing rules
- appending private proxies
- injecting local proxy groups
- overriding DNS or TUN defaults
- layering Smart-specific options without editing the base subscription

### Direct field override scope

Direct override should be limited to explicit, high-value mihomo fields rather than unrestricted YAML replacement. Candidate override areas include:

- ports and external controller settings
- logging level
- DNS block
- TUN block
- rule behavior toggles
- provider-related settings
- profile persistence flags

The branch should avoid a merge system that quietly turns into arbitrary textual YAML surgery.

## Script Profile Design

Script profiles should be treated as a controlled config transformation layer, not as arbitrary application logic.

### Input

The script step should receive:

- the already-merged config document
- optional profile metadata
- controlled execution context such as current platform, profile type, or build mode

It should not receive unrestricted access to unrelated app internals.

### Output

The expected output should be a transformed config document, not side effects.

That means script profiles should not directly:

- manipulate UI state
- install helpers
- spawn privileged processes
- write arbitrary files outside the profile pipeline

### Validation

Script output should be validated exactly like merge output:

- YAML parse check
- schema/model check where available
- mihomo dry-run parse

### Error reporting

Script failures should report:

- which script profile failed
- whether the failure was parse, transform, or validation
- a concise actionable message

Error reporting should not dump secrets or full subscription content into logs.

### Rollback behavior

If a script profile fails, SmartX should:

- keep the previous last-known-good effective config
- keep the base and merge profiles unchanged
- mark the script profile as failed
- avoid partially updating the active core

## Effective Config Pipeline

SmartX should eventually move to a generated effective config pipeline like this:

1. Load base profile.
2. Apply enabled merge profiles in order.
3. Apply enabled script profiles in order.
4. Validate YAML/schema.
5. Dry-run parse with mihomo.
6. Write generated effective config.
7. Reload core.
8. Roll back on failure.

### Why ordered layering matters

This pipeline gives SmartX deterministic behavior:

- base profile is the source of truth
- merges are explicit overlays
- scripts are explicit transforms
- generated output is reproducible
- rollback is tied to the last-known-good effective snapshot

That is much stronger than today’s model, where the app mostly replaces a file and immediately reloads it.

## Safety and Reproducibility

The profile system should preserve user intent and make failure recovery obvious.

### Base subscriptions should remain read-only

Downloaded remote profiles should not be directly edited in place. Their local cache can be replaced on update, but user customizations should live elsewhere.

### Local modifications should live in overlay files

Merge profiles and script profiles should be stored as overlay data, separate from the base remote config.

That keeps:

- upstream subscription updates clean
- user intent reviewable
- generated output reproducible

### Generated config should be reproducible

At any point, SmartX should be able to answer:

- which base profile produced the current config
- which merge profiles were enabled
- which script profiles were enabled
- what generated file was handed to the core

That is the minimum needed for reliable debugging and rollback.

## UI Plan

A future SmartX Profile window should replace the old flat remote-config and local-file mindset with profile cards or rows that expose state clearly.

Recommended UI elements:

- profile type badge: Remote, Local, Merge, Script, Generated
- display name
- source location or upstream URL
- enable/disable state
- update status
- last update time
- validation status
- last error summary
- base/overlay relationship
- manual refresh action for remote profiles
- reorder controls for merge and script profiles

If subscription traffic headers are available, SmartX should also show:

- remaining traffic
- used traffic
- expiry date

The key UI goal is to make it obvious what is:

- downloaded source
- local override
- generated output
- active profile pipeline

The branch now partially satisfies the first part of that goal for existing UI surfaces by surfacing `Local` vs `Remote` provenance in menu items, diagnostics output, and remote-config table tooltips. It still does not provide:

- first-class Merge or Script profile rows
- active pipeline visualization
- reorder or enable/disable controls for layered profiles
- generated effective config editing or a true pipeline graph

The branch now does provide a first-pass generated artifact inspection surface in the Diagnostics dashboard:

- preview of the current generated-effective YAML
- preview of the current last-known-good YAML
- artifact metadata such as selected profile, source path, generated time, and controller mode
- open-folder access to the SmartX profile artifacts directory

That is still not a full profile window or pipeline visualizer, but it is materially better than path-only diagnostics.

That is a better fit for modern mihomo clients than the current mix of menu-based file switching and a separate remote-config editor.

## Acceptance Criteria

Profile management can be called mature only when all of the following are true:

- SmartX no longer relies primarily on selected YAML file names as the user-facing config model.
- Remote, Local, Merge, and Script profiles are represented explicitly.
- Base remote subscriptions remain read-only, and local changes are stored as overlays.
- The app can generate a deterministic effective config from base plus overlays.
- Validation occurs before the active core is reloaded.
- Failed profile updates or transformations roll back cleanly to the last-known-good effective config.
- The UI clearly shows profile type, update state, validation state, and active/inactive status.
- URL scheme imports create managed profiles rather than ad hoc mutable files.
- External controller connections remain distinct from local profile definitions.
- The system can explain which exact profile pipeline produced the current running config.

## Source of Truth

This document is descriptive, not normative. The current implementation is defined by the source files in this repository, especially [`ClashX/General/Managers/ConfigManager.swift`](../../ClashX/General/Managers/ConfigManager.swift), [`ClashX/General/Managers/RemoteConfigManager.swift`](../../ClashX/General/Managers/RemoteConfigManager.swift), [`ClashX/General/ApiRequest.swift`](../../ClashX/General/ApiRequest.swift), [`ClashX/Macro/Paths.swift`](../../ClashX/Macro/Paths.swift), [`ClashX/goClash/main.go`](../../ClashX/goClash/main.go), and [`ClashX/AppDelegate.swift`](../../ClashX/AppDelegate.swift). Update this memory document when profile management evolves.
