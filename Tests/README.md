# Tests in this repository

This repository currently has no dedicated Xcode unit-test target. The tests in this folder are **pending integration**.

`Tests/Security/PathSafetyTests.swift` contains XCTest cases for safe config-name validation and config-path containment logic. To enable these tests in Xcode:

1. Add a new macOS Unit Testing Bundle target (e.g. `ClashXTests`).
2. Add `Tests/Security/PathSafetyTests.swift` to that target.
3. Set `@testable import ClashX` for the test target.
4. Run the tests with `xcodebuild test`.

Notes:
- A robust symlink-escape integration test should run on macOS with a writable filesystem sandbox representative of app behavior.
- `PathSafetyTests` currently focuses on deterministic name validation/path APIs and config replacement invariants.
- Manual helper validation case to add during macOS test runs: `http://127.evil.com/proxy.pac` must be rejected by helper PAC validation.
- `Tests/SecurityHarness/security_harness.swift` is a temporary CI smoke test. It now mirrors the current production SHA256 fallback naming and suggested-filename validation semantics, but it does not replace a real XCTest target.
- SmartX redaction currently has no dedicated XCTest target either. For the `codex/goal-may26-01` stabilization PR, the production redactor was kept in app code and the gap remains documented here rather than cloning that logic into another standalone harness.

## CI
- PR CI runs on macOS GitHub Actions via `.github/workflows/pr-ci.yml`.
- CI uses the same `bash install_dependency.sh` path as local setup so dashboard resources, `Country.mmdb.gz`, Pods, and the Go archive are installed the same way in both environments.
- CI builds with code signing disabled (`CODE_SIGNING_ALLOWED=NO`) so it can validate compile/build paths without local certificates.
- CI compiles app/helper code paths, verifies that the Release helper client requirement remains fail-closed, and runs `Tests/SecurityHarness/security_harness.swift`.
- CI does **not** validate notarization, privileged helper installation by SMJobBless, or production signing requirements.
- Local release testing still requires real Apple Developer identities and a follow-up helper identity migration.
