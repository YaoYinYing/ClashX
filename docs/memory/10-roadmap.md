# SmartX Roadmap

## Product Thesis

SmartX should become a native macOS mihomo/smart client derived from ClashX. It should preserve ClashX's lightweight menu-bar experience while modernizing core management, profile processing, TUN/DNS configuration, diagnostics, and smart routing visibility.

The branch should keep what ClashX was good at:

- fast native menu-bar interaction
- low-overhead local-client behavior
- AppKit-native configuration and status surfaces

And it should replace what is now too dated for a modern mihomo client:

- implicit feature assumptions
- file-name-based config switching
- incomplete TUN/DNS modeling
- inherited release identity confusion
- weak Smart observability

## Phase 0: Stabilize Current Branch

Scope:

- make current smartx build reproducible
- fix README identity
- document current architecture
- remove inherited release confusion
- verify embedded smart core build
- add CI build checks

This phase is about branch credibility, not new product features. Before SmartX can move forward cleanly, it needs a stable baseline that developers can build, inspect, and explain.

Key outputs:

- current branch behavior is documented
- build flow is explicit
- embedded Smart core wiring is understood
- README stops implying old ClashX/ClashX Pro release identity
- CI proves at least unsigned build health

## Phase 1: Build and Signing Foundation

Scope:

- CI build
- deterministic resources
- version metadata
- signing identity cleanup
- privileged helper migration
- unsigned debug artifact
- signed preview release later

This phase turns SmartX from “branch that can sometimes build” into “branch with a coherent release foundation.”

Priority items:

- pin or vendor dashboard and resource downloads
- make version metadata deterministic
- align app/helper identifiers
- migrate helper signing requirements away from inherited legacy identity
- keep unsigned Debug artifacts for testing
- defer signed public preview until the identity and notarization path is real

## Phase 2: Mihomo API Layer

Scope:

- capability map
- endpoint probing
- remove PRO_VERSION assumptions
- implement missing API wrappers where needed
- normalize error handling

This phase should make SmartX feature detection runtime-driven instead of compile-time-history-driven.

Important outcomes:

- no more treating `PRO_VERSION` as the real capability boundary
- unsupported endpoints disable only the affected UI
- embedded, external stable, external alpha, and Smart cores can coexist under one client model
- errors distinguish unavailable controller, auth failure, unsupported feature, and transient failure

## Phase 3: TUN and DNS

Scope:

- expand TUN model
- add DNS model
- platform-aware UI
- validation
- safe defaults
- rollback on failure

This phase should stop treating TUN and DNS as mostly opaque config text.

Expected direction:

- model the main macOS-relevant TUN fields
- add a structured DNS model
- keep unsupported Linux/Android-specific controls out of normal macOS UI
- validate dangerous combinations before writing config
- preserve previous state and roll back on failed updates

This phase still does not automatically mean “full macOS TUN solved.” If a privileged TUN architecture is still missing, the UI must stay honest.

## Phase 4: Profile Pipeline

Scope:

- remote profiles
- local profiles
- merge overlays
- script overlays
- generated effective config
- dry-run validation
- rollback
- last-known-good snapshot

This phase replaces the old ClashX file-switching model with a modern profile system.

Core principle:

- base profiles stay clean
- overlays carry local modifications
- generated effective config is reproducible
- failed transforms do not destroy the last working state

This is one of the highest-leverage product upgrades because it touches both user experience and operational safety.

## Phase 5: Smart Features

Scope:

- LightGBM model lifecycle
- smart weights UI
- smart cache controls
- smart connection diagnostics
- smart decision explanation

This phase turns current Smart support from “feature hooks exist” into “Smart routing is inspectable and trustworthy.”

Expected direction:

- explicit Smart capability detection
- reliable model status and update workflow
- better Smart dashboard surfaces
- Smart connection detail that explains target, block reason, weights, and decision context

## Phase 6: Diagnostics

Scope:

- memory
- logs
- connections
- DNS query
- pprof helpers
- issue report bundle
- redaction policy

This phase turns SmartX from a menu-bar client with some debug surfaces into an actually supportable product.

Expected outputs:

- memory telemetry
- better log viewer
- richer connection detail
- DNS tools
- safe developer diagnostics for debug endpoints
- sanitized issue-report bundles

## Phase 7: Public Preview

Scope:

- security review
- release notes
- source archive
- known limitations
- update channel decision
- migration guide from ClashX or ClashX Pro

This phase is the first point where SmartX should be treated as something externally consumable beyond source-build testers.

The preview should be explicit about:

- what works
- what is experimental
- what is still missing
- how SmartX differs from older ClashX expectations

## Non-Goals

SmartX should not:

- claim to be official ClashX Pro
- provide proxy services
- silently inherit upstream release/update identities

It also should not confuse:

- helper installation with full TUN support
- unsigned CI artifacts with release readiness
- embedded Smart support with universal capability across all controllers

## Priority Matrix

### Must fix before any release

- signing identity cleanup for app and helper
- notarization path
- helper authorization-string cleanup
- deterministic resource policy
- version metadata generation
- removal or replacement of inherited update feeds
- clear README/release identity

### Should fix before public preview

- capability map and endpoint probing
- better TUN/DNS honesty and validation
- profile pipeline design at least partially implemented or explicitly deferred
- Smart endpoint diagnostics
- sanitized issue-report path
- privacy review for AppCenter/crash reporting and logs

### Can wait for stable release

- full profile overlay system
- full DNS editing model
- complete Smart decision explanation
- mature memory and pprof tooling
- polished migration tooling from older ClashX installs

### Experimental

- optional sidecar/external core mode beyond current controller support
- advanced script profile transformation
- deep Smart explanation UI
- expert-only diagnostics and debug tools

## Definition of Done

### Phase 0 done

Done when:

- the branch builds reproducibly in documented local and CI flows
- the current architecture is documented
- README no longer implies old release identity
- unsigned CI build checks exist and pass consistently

### Phase 1 done

Done when:

- build resources are deterministic
- version metadata is reliable
- app/helper signing identities are coherent
- helper migration no longer depends on legacy release identity
- unsigned Debug artifacts are consistently produced
- signed public preview prerequisites are documented and mostly in place

### Phase 2 done

Done when:

- runtime capability detection exists
- unsupported endpoints no longer break unrelated UI
- `PRO_VERSION` no longer gates normal mihomo features incorrectly
- API-layer error handling is normalized

### Phase 3 done

Done when:

- TUN and DNS have structured models
- platform-aware validation exists
- unsupported settings are hidden or clearly labeled
- failed writes roll back safely

### Phase 4 done

Done when:

- SmartX has explicit profile types
- effective config generation is deterministic
- dry-run validation exists
- rollback to last-known-good effective config works

### Phase 5 done

Done when:

- LightGBM model lifecycle is visible and manageable
- Smart weights and Smart cache tooling are reliable
- Smart connection detail explains decision state enough to debug real traffic

### Phase 6 done

Done when:

- logs, traffic, memory, and connections have coherent diagnostic surfaces
- DNS and provider health tools exist where supported
- issue-report bundles are useful and redacted

### Phase 7 done

Done when:

- SmartX passes a real security/signing/release review
- preview artifacts are signed, notarized, and documented
- update-channel policy is explicit
- source and release materials are aligned with the shipped preview

This roadmap does not claim these phases are already complete unless current code or CI proves it. It is a forward plan derived from the current SmartX branch state and the documented gaps.

## Source of Truth

This document is descriptive, not normative. It is based on the current SmartX memory docs under [`docs/memory/`](../../docs/memory) and the source tree in this repository. Update it when branch priorities or implementation reality changes.
