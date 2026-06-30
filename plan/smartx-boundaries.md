# SmartX Design Boundaries

Answers to the four convergence questions. Once these are fixed in code,
SmartX moves from feature-stack to product-system.

## 1. What config does SmartX manage?

**SmartX owns:**
- `config.yaml` — the active mihomo config file. SmartX reads it, and in
  embedded-core mode writes TUN/DNS sections via ConfigYAMLEditor.
- SmartX managed overrides (`~/.config/clash/.smartx/overrides/`) —
  LightGBM settings persisted as JSON, synced to Go core.
- Profile artifacts (`~/.config/clash/.smartx/profiles/`) — source-copy
  snapshots on successful reload. Named `successful-reload-artifact.yaml`
  and `last-known-good.yaml`. Generation mode explicitly marked
  `source-copy` in metadata.

**SmartX does NOT own:**
- Profile merge/script transforms (Phase 9 pipeline not active)
- Generated effective config generation (ConfigPipeline model exists,
  generateEffectiveConfig implemented but no production caller)
- Remote subscription content (SmartX fetches and validates, but doesn't
  modify downloaded configs)

**Decision:** ConfigWorkspace model (PR #22-23) defines the future state.
Today: config.yaml + SmartX managed overrides. Tomorrow: workspace pipeline.
The `generated-effective.yaml` file naming is misleading — it's a source-copy.
→ **Action:** rename artifact paths to `successful-reload-artifact.yaml` and
`last-known-good.yaml`. Keep backward compat (check both old and new names).

## 2. What operations does embedded core support?

**Embedded core: config-file TUN. External controller: API TUN.**

| Operation | Embedded Core | External Controller |
|-----------|--------------|-------------------|
| TUN enable/disable | ✅ Write tun.enable to config.yaml, reload via Go bridge | ✅ PATCH /configs via HTTP |
| TUN config editing | ✅ TUN editor writes to config.yaml | ✅ TUN editor via PATCH /configs |
| DNS config editing | ✅ DNS editor writes to config.yaml | ✅ DNS editor via PATCH /configs |
| TUN system verification | ❌ No utun/route/DNS hijack verification | ❌ Same — controller-config only |
| TUN rollback on failure | ✅ Restore original file content | ✅ Reverse PATCH |
| Helper-backed TUN | ❌ Helper is system-proxy only | ❌ Same |

**Messaging rules:**
- Never say "embedded-core TUN is unsupported." Say "Embedded-core TUN
  uses config-file update. System-level TUN verification (utun, route,
  DNS hijack) is not available in this mode."
- Preflight planner: remove `embeddedCoreUnsupported` blocker. Change to
  warning about no system-level verification.
- PR #24 already fixed the most visible contradictions. Full cleanup
  should audit all user-facing strings.

**Why no system-level TUN verification?**
Creating utun devices, inserting routes, and hijacking DNS requires
privileged execution. SmartX's helper (ProxyConfigHelper) only manages
system proxy. Two future paths:
- A: Give the embedded mihomo core setuid privilege (Sparkle's pattern:
  chown root:admin, chmod +sx). App launches core as privileged child.
- B: Extend the helper to manage TUN (requires new SMJobBless helper
  with explicit TUN commands — the reserved tunPreflight/tunEnable/etc.
  in HelperCommandContract were designed for this).

**Decision:** Path A (sidecar setuid) is simpler and matches Sparkle's
proven approach. Path B requires identity migration + new helper signing.
→ **Defer the architecture decision. Document as known ceiling.**

## 3. Helper: system proxy only or future TUN?

**Helper is system proxy only. Period.**

Current responsibilities:
- Enable/disable/restore system proxy settings
- Read current proxy settings
- Report helper version

Explicitly NOT:
- TUN device creation
- Route manipulation
- DNS hijack
- Shell execution
- Arbitrary file writes
- Generic privileged command execution

The reserved TUN commands in HelperCommandContract (tunPreflight,
tunEnable, etc.) are a FUTURE design placeholder. They are NOT
implemented and must not be described as available.

**Bundle identity:**
- App: `com.doodlenet.ClashX` (temporary, pending migration)
- Helper: `com.west2online.ClashX.ProxyConfigHelper` (temporary)
- Mach service: `com.west2online.ClashX.ProxyConfigHelper` (temporary)
- Launchd label: `com.west2online.ClashX.ProxyConfigHelper` (temporary)

All identities need migration to SmartX-owned values before any public
distribution. Blocked by Developer ID signing.

**Debug helper guard (PR #24):** Now verifies bundle ID match even when
signing requirement is empty. This prevents arbitrary local processes
from connecting to the privileged helper via the legacy Debug install
path.

## 4. Are diagnostics shareable by default?

**No. But the bundle export IS sanitized. Log export now is too (PR #24).**

| Path | Sanitized? | What's redacted |
|------|-----------|-----------------|
| Diagnostics bundle export | ✅ Yes | URLs, proxy URIs, secrets, paths |
| Log export | ✅ Yes (PR #24) | Same as bundle via sanitizeText |
| In-app log viewer | ❌ No | Shows raw logs (local only) |
| Copied report | ✅ Yes | Via SmartXRedactor |
| Capability status | ✅ Yes | No secrets in capability cache |
| Memory/CPU/GC output | ✅ Yes | No user data in these endpoints |

**Rule:** Any export/save/copy path must run SmartXRedactor.sanitizeText.
In-app display (log viewer, connection details) is exempt — local only.

**Remaining gaps (P2):**
- Log viewer could add a "Redact" toggle (default off)
- Connection detail panel could show redacted proxy info by default
- DNS query results could contain user-chosen hostnames

## Boundary enforcement checklist

Before adding any new feature, verify:

1. Does it work the same in embedded AND external controller modes?
   If not, document the difference explicitly.
2. Does it respect the helper boundary (system proxy only, no TUN)?
3. Does it redact secrets before any export/save/copy?
4. Does it use the ConfigWorkspace model or extend it?
5. Does the user-facing text match actual capability?
