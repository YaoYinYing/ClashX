# SmartX Build and Release Memory

## Build Identity

The `smartx` branch should be treated as an experimental SmartX build of ClashX, not as a verified reproduction of historical ClashX Pro releases.

That distinction matters because the branch already mixes:

- a new embedded Vernesong mihomo Smart core path
- updated API and UI work
- partially modernized helper/signing settings
- older product identity, updater, and release assumptions

Build success alone does not mean release readiness, notarization readiness, or compatibility with old ClashX Pro distribution behavior.

The current branch is also modern-only by project decision. Active macOS `10.14` support was dropped after the legacy CI lane failed on `CryptoKit.SHA256`, and CI success in this branch does not imply a signed or notarized release is ready.

## Local Build Flow

The current repository implies the following local build flow.

1. Clone repository.
2. Checkout `smartx`.
3. Install Go, Ruby/Bundler, and CocoaPods tooling.
4. Run `install_dependency.sh`.
5. Open `ClashX.xcworkspace`, not `ClashX.xcodeproj`.
6. Build the `ClashX` scheme.

### 1. Clone repository

Cloning should produce the app source, the Go c-archive source under [`ClashX/goClash/`](../../ClashX/goClash), the Xcode project/workspace, CocoaPods manifests, and the current GitHub workflow definitions.

### 2. Checkout `smartx`

The branch selection matters because the Smart core integration, Core settings UI, Smart dashboard work, helper-policy changes, and unsigned SmartX CI all live on `smartx`, not on `main`.

### 3. Install Go, Ruby/Bundler, CocoaPods

The inspected files imply these toolchains are expected:

- Go `1.21` family from [`ClashX/goClash/go.mod`](../../ClashX/goClash/go.mod)
- Ruby `3.2.4` from [`.ruby-version`](../../.ruby-version), matching the current GitHub Actions Ruby `3.2` family
- Bundler for the [`Gemfile`](../../Gemfile)
- CocoaPods for the [`Podfile`](../../Podfile)
- Xcode with SwiftPM support and macOS SDK compatible with the project

The `Gemfile` currently pins:

- `fastlane`
- `cocoapods`
- `activesupport = 7.0.8`

The repository should be installed with a project Ruby, not macOS system Ruby 2.6. `activesupport = 7.0.8` requires Ruby `>= 2.7`, and the documented local recommendation is Ruby `3.2.4`. Run `bundle install` using that project Ruby before invoking the rest of the dependency flow.

### 4. Run `install_dependency.sh`

[`install_dependency.sh`](../../install_dependency.sh) currently performs four main jobs:

- builds the Go core by running `python3 build_clash_universal.py` inside `ClashX/goClash`
- checks that the active Ruby is at least `2.7.0` and recommends Ruby `3.2.4`
- runs `bundle install`
- runs `bundle exec pod install`
- deletes and redownloads runtime resources

The resource step currently:

- downloads `Country.mmdb` from Dreamacro’s latest release URL
- clones the `gh-pages` branch of `MetaCubeX/Yacd-meta` into `ClashX/Resources/dashboard`
- strips `.git`, `CNAME`, and some built assets

What this is expected to produce:

- `ClashX/goClash/goClash.a`
- `ClashX/goClash/goClash.h`
- a generated `ClashX.xcworkspace`
- populated `Pods/`
- dashboard assets in `ClashX/Resources/dashboard`
- `ClashX/Resources/Country.mmdb.gz`

### 5. Open `ClashX.xcworkspace`

The repository uses both CocoaPods and SwiftPM. Opening only `ClashX.xcodeproj` would skip the Pods integration and typically leads to missing module or linker failures.

The workspace is the correct entry point because:

- Pods are integrated through CocoaPods
- `KeyboardShortcuts` is integrated through SwiftPM

Important workspace-format note:

- `ClashX.xcworkspace/contents.xcworkspacedata` is XML, not a plist.
- `plutil` can reject a valid workspace file because the root element is `Workspace`.
- A valid readiness check is:
  - XML parses
  - root tag is `Workspace`
  - `FileRef` entries exist
  - `group:ClashX.xcodeproj` resolves
  - `group:Pods/Pods.xcodeproj` resolves when referenced
  - `xcodebuild -list -workspace "$PWD/ClashX.xcworkspace"` succeeds

SmartX now carries a dedicated readiness helper:

- `bash scripts/ensure-xcworkspace.sh`

That helper validates the workspace XML structure directly instead of treating it like a plist. If the workspace XML is valid but CocoaPods products are missing, the normal local repair path is:

- `bundle install`
- `bundle exec pod install`
- `xcodebuild -list -workspace "$PWD/ClashX.xcworkspace"`

If the global CocoaPods install differs from the Bundler-managed one, prefer `bundle exec pod install` for this repository. Project fallback is diagnostic only and should not replace the normal workspace-based path.

### 6. Build the `ClashX` scheme

The current project expects the `ClashX` target to link:

- `goClash.a`
- Pods-managed frameworks and libraries
- SwiftPM package `KeyboardShortcuts`

In unsigned local or CI builds, `xcodebuild` is typically invoked with signing disabled. That is sufficient for app compilation and UI testing, but not for privileged-helper release validation.

## Go Core Build Flow

The embedded core build is defined by [`ClashX/goClash/build_clash_universal.py`](../../ClashX/goClash/build_clash_universal.py).

### Current module wiring

[`ClashX/goClash/go.mod`](../../ClashX/goClash/go.mod) declares:

- module: `github.com/yichengchen/clashX/ClashX`
- required mihomo module: `github.com/metacubex/mihomo`
- `replace github.com/metacubex/mihomo => github.com/vernesong/mihomo`

This works because the Vernesong fork still declares the `github.com/metacubex/mihomo` module path. The build script resolves the reported version using `go list -m` against the metacubex module identity, not the fork name.

### Per-architecture c-archive build

The script builds twice:

- `GOOS=darwin GOARCH=arm64`
- `GOOS=darwin GOARCH=amd64`

It also sets:

- `CGO_ENABLED=1`

Historical note:

- the older build script snapshot documented here still showed `CGO_CFLAGS=-mmacosx-version-min=10.14`
- the older build script snapshot documented here still showed `CGO_LDFLAGS=-mmacosx-version-min=10.14`
- those historical flags should not be read as an active SmartX support promise for macOS `10.14`

The build command uses:

- `go build`
- `-trimpath`
- `-buildmode=c-archive`
- output `goClash_arm64.a` or `goClash_amd64.a`

`-buildmode=c-archive` is what produces a C-callable static archive plus a generated header, which is how the Swift/Objective-C app links against the embedded Go core.

### Metadata injection

The script sets Go linker flags for:

- `github.com/metacubex/mihomo/constant.Version`
- `github.com/metacubex/mihomo/constant.BuildTime`

If `MIHOMO_CORE_VERSION` is not set, it derives the version from `go list -m` or falls back to parsing `go.mod`.

### Header consistency and lipo merge

After both builds, the script:

- compares `goClash_amd64.h` and `goClash_arm64.h`
- exits if they differ
- renames the shared header to `goClash.h`
- runs `lipo *.a -create -output goClash.a`

That means successful universal output requires:

- both architecture builds to succeed
- both generated headers to match exactly
- `lipo` to succeed on the two archives

### Info.plist metadata update

In CI contexts, the script writes `coreVersion` into [`ClashX/Info.plist`](../../ClashX/Info.plist). The branch also reads `gitCommit`, `gitBranch`, and `buildTime` from the app bundle at runtime, so release-quality metadata generation still depends on additional steps outside the Go build script.

## Dependency Management

### CocoaPods

The current [`Podfile`](../../Podfile) pulls in:

- `LetsMove`
- `Alamofire`
- `SwiftyJSON`
- `RxSwift`
- `RxCocoa`
- `CocoaLumberjack/Swift`
- `Starscream`
- `AppCenter/Analytics`
- `AppCenter/Crashes`
- `Sparkle`
- `FlexibleDiff`
- `GzipSwift`
- `SwiftLint`
- `SwiftFormat/CLI`

[`Podfile.lock`](../../Podfile.lock) currently pins concrete versions and checksums, so CocoaPods resolution is reasonably reproducible as long as the podspec sources remain available.

The repository now treats Bundler as the preferred CocoaPods entry point whenever [`Gemfile`](../../Gemfile) exists:

- run `bundle install`
- run `bundle exec pod install`

This matters because the observed `xcodebuild: error: 'ClashX.xcworkspace' is not a workspace file` failure was traced to incomplete workspace/dependency preparation, not to `contents.xcworkspacedata` being malformed.

### SwiftPM

The project also uses SwiftPM for `KeyboardShortcuts`. [`ClashX.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`](../../ClashX.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved) pins:

- package: `KeyboardShortcuts`
- version: `1.17.0`
- revision: `ac12762853126cf2e7ad63a6a58e1c9f58c6a0ee`

### Resource downloads

Resource reproducibility is weaker than code dependency reproducibility.

Current weak points:

- `install_dependency.sh` downloads `Country.mmdb` from a `latest` URL
- `install_dependency.sh` clones the dashboard from a moving `gh-pages` branch

That means two builds from the same Git commit can still end up with different runtime resources.

### Project integration

[`ClashX.xcodeproj/project.pbxproj`](../../ClashX.xcodeproj/project.pbxproj) shows that the app target links:

- `goClash.a`
- `KeyboardShortcuts`
- the Pods-generated dependencies

This is why the Go archive build, `pod install`, and SwiftPM resolution all need to succeed for a healthy local build.

## CI Plan

The repository already contains GitHub Actions workflows:

- [`.github/workflows/main.yml`](../../.github/workflows/main.yml)
- [`.github/workflows/pr-ci.yml`](../../.github/workflows/pr-ci.yml)

They already perform unsigned SmartX builds, including Go archive creation and `xcodebuild` Debug builds. A future stable SmartX CI plan should keep that direction and standardize on the following pipeline:

Current CI scope note:

- PR CI now has one unsigned Debug artifact lane:
  - Modern: `macos-26` + Xcode `26.3`
- Every PR uploads an unsigned SmartX app artifact and build logs for the modern lane.
- PR CI also runs the helper fail-closed validation, the security harness, the endpoint-builder smoke harness, and the capability-identity smoke harness.
- Artifact upload does **not** imply Developer ID signing, notarization, helper installation success, or runtime compatibility on the target OS.

### Post-merge DMG artifacts

The branch now also has a dedicated post-merge artifact workflow for manual testing after code lands on `smartx`.

- It runs on `push` to `smartx` and `workflow_dispatch`.
- It uses the same modern-only baseline as PR artifacts:
  - `macos-26`
  - Xcode `26.3`
  - deployment target `11.0`
  - Go `1.21.x`
  - Ruby `3.2`
- It discovers the built app bundle from `xcodebuild -showBuildSettings` instead of hardcoding `SmartX.app`.
- It derives the user-facing DMG version tag as `v<SmartX-version>+<git-hash[:8]>`.
- It creates an unsigned DMG that contains:
  - the built app bundle
  - an `Applications` symlink
  - a drag-to-Applications background image
  - a README explaining that the artifact is unsigned and not notarized
- It uploads the DMG and the workflow logs as separate GitHub Actions artifacts.

Important artifact semantics:

- The DMG is unsigned.
- The DMG is not notarized.
- The DMG is not a release build.
- It is meant for manual testing after merge.
- Privileged helper behavior may not work correctly in unsigned builds.
- Signed/notarized DMG packaging remains future release work.
- macOS `10.14` is not supported.

1. checkout
2. setup Xcode version
3. setup Go version
4. setup Ruby and Bundler
5. cache Go modules
6. cache Pods
7. build Go archive
8. `pod install`
9. `xcodebuild` Debug
10. upload unsigned debug artifacts for the current modern lane

Recommended details:

- pin the Xcode runner and version explicitly
- use Go module cache keyed by `go.sum`
- use Bundler cache keyed by `Gemfile.lock` if introduced
- cache Pods keyed by `Podfile.lock`
- resolve Swift packages explicitly
- archive `.ci-logs` and the unsigned `.app` or zipped `.app`

Important boundary:

CI success only proves that SmartX can be built as an unsigned app artifact. It does not imply:

- Developer ID signing works
- helper installation works for release
- notarization works
- Sparkle update signing works
- the app is ready for public distribution

## Release Requirements

The current repository still has multiple release blockers.

### Developer ID signing

The current project has placeholders and historical identities mixed together. A real SmartX release needs its own Developer ID Application and, if required, Developer ID Installer identities.

### bundle identifier migration

The main app target in `project.pbxproj` now uses `com.doodlenet.ClashX`, but [`ClashX/Info.plist`](../../ClashX/Info.plist) still contains legacy URL names, iCloud container IDs, and helper authorization strings tied to older identities. These need a coherent final SmartX release identity.

### privileged helper signing

The helper target still carries legacy helper identifiers and signing assumptions. The branch already improved Debug-vs-Release helper trust behavior, but public release still requires final helper signing and identity migration.

### SMJobBless authorization strings

`SMAuthorizedClients` and `SMPrivilegedExecutables` in `ClashX/Info.plist` are still legacy-bound. Release-quality helper installation requires final reciprocal signing requirements, not placeholders.

### Sparkle feed and signing keys

`SUFeedURL` is currently `https://invalid.local/smartx/appcast.xml`, which is intentionally not a real release feed. A public release needs:

- a real appcast feed
- Sparkle signing keys
- release-channel policy

### notarization

Unsigned CI artifacts are not notarized. A real release pipeline needs notarization credentials, notarization submission, stapling, and validation.

### reproducible dashboard and resource downloads

Dashboard and MMDB downloads should move from floating URLs/branches to pinned revisions or vendored release assets.

### version metadata generation

The bundle reads `coreVersion`, `gitCommit`, `gitBranch`, and `buildTime`. Release builds need a clear, reproducible metadata generation step so users and future developers can identify exactly what was built.

### privacy cleanup for analytics/crash reporters

The Podfile still includes `AppCenter/Analytics` and `AppCenter/Crashes`. A release decision is needed on whether SmartX keeps, replaces, or removes those services before public distribution.

## Risks

The current build and release flow has several predictable failure modes.

### Go module replace mismatch

If the Vernesong fork stops declaring the same module path as `github.com/metacubex/mihomo`, or if replace-based expectations drift, the Go build can break even though `go.mod` still parses.

### CGO header mismatch between arm64 and amd64

The build script explicitly fails if `goClash_amd64.h` and `goClash_arm64.h` differ. Any architecture-specific exported symbol drift or cgo generation mismatch will block universal archive creation.

### lipo merge failure

Even if both per-arch archives build, `lipo` can still fail if one archive is missing, corrupt, or incompatible.

### CocoaPods resolution failure

`bundle exec pod install` can fail because of:

- missing Ruby/Bundler environment
- CocoaPods repo/index issues
- upstream podspec changes
- local architecture or Xcode compatibility changes

### SwiftPM package resolution failure

Even with `Package.resolved`, SwiftPM can fail if:

- GitHub is unavailable
- the pinned revision is unreachable
- the selected Xcode version has a package-resolution regression

### code signing failure

Signed builds will fail until the app, helper, and release identities are aligned. Unsigned local builds avoid that only by turning signing off.

### privileged helper install failure

A compiled app does not imply working helper installation. Local unsigned builds can still hit `SMJobBless` authorization failure, and release builds still require final helper signing metadata.

## Acceptance Criteria

The SmartX build system can be called stable only when all of the following are true:

- A documented local build from a clean checkout succeeds using pinned toolchain versions.
- `install_dependency.sh` or its replacement produces deterministic dashboard and MMDB inputs.
- The Go c-archive build succeeds for both `arm64` and `amd64`, and header parity is verified.
- `ClashX.xcworkspace` resolves both CocoaPods and SwiftPM dependencies without manual repair.
- CI reliably builds unsigned Debug artifacts from pull requests.
- CI artifacts can be launched locally for basic UI verification.
- Version metadata in the app bundle matches the actual source revision and embedded core revision.
- Release identities for the app and privileged helper are finalized and coherent.
- `SMJobBless` metadata is aligned with final bundle IDs and signing identities.
- Sparkle feed configuration and signing keys are finalized or explicitly removed from release scope.
- Notarization is automated and verified.
- The release process no longer depends on floating dashboard or resource downloads.

This document does not claim those criteria are satisfied today. It records the current state and the conditions that must be met before SmartX can be treated as a stable build and release system.
