# SmartX Helper Command Contract

## Scope

This document defines the intended typed helper command boundary for SmartX after the helper-boundary audit work.

This PR does not implement helper-backed TUN.
This PR defines the contract boundary only.

## Current legacy helper XPC methods

The live privileged helper XPC surface is still bounded to these methods:

- `getVersion`
- `enableProxyWithPort`
- `disableProxyWithFilterInterface`
- `restoreProxyWithCurrentPort`
- `getCurrentProxySetting`

These remain system-proxy helper methods. They are not a general privileged command runner.

## Command classification

### Current supported system-proxy commands

- `getVersion`
- `enableSystemProxy`
- `disableSystemProxy`
- `restoreSystemProxy`
- `readSystemProxy`
- `helperStatus`

`helperStatus` is diagnostic-only app-side contract metadata, not a new privileged helper XPC method.

### Future reserved TUN commands

- `tunPreflight`
- `tunEnable`
- `tunDisable`
- `tunStatus`
- `tunVerifyRoute`
- `tunVerifyDNS`
- `tunRollback`

These names are reserved so future helper-backed TUN work stays typed and auditable instead of extending shell-based or ad hoc privileged behavior.

### Explicitly forbidden commands

- arbitrary shell execution
- arbitrary file writes
- arbitrary launchctl calls
- arbitrary route commands
- arbitrary process spawning
- arbitrary command strings from the app
- generic root proxy for app-side logic

## Future reserved TUN command categories

Future helper-backed TUN work must stay within explicit typed categories:

- preflight
- install or validate helper-owned TUN prerequisites
- enable
- disable
- status
- verify route
- verify DNS
- rollback / recovery

## Required properties for future TUN commands

Any future helper-backed TUN command must provide all of the following:

- typed input
- typed output
- no raw shell command
- no user-provided executable path
- allowlisted operations only
- structured error code
- audit log message
- safe timeout semantics
- no silent fallback to legacy shell install path

## Current implementation boundary

The typed command contract introduced in this PR is a pure Swift model and diagnostics boundary only:

- it does not call XPC
- it does not call `SMJobBless`
- it does not call `Authorization`
- it does not run shell commands
- it does not create `utun` devices
- it does not modify routes
- it does not start mihomo through the helper

The legacy AppleScript shell install fallback remains legacy risk and must not grow into the future helper-backed TUN design.

Future helper-backed TUN work should compose with the typed TUN lifecycle diagnostics boundary and its read-only interface, route, and DNS evidence layers rather than bypassing them with shell commands, route helpers, or generic root execution.
