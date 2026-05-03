<h1 align="center">
  <img src="https://github.com/Dreamacro/clash/raw/master/docs/logo.png" alt="Clash" width="200">
  <br>
  ClashX
  <br>
</h1>


A rule-based proxy client for macOS on the SmartX `smartx` branch, embedding the Vernesong Smart fork of mihomo through the existing Go c-archive bridge.

This branch is for preview hardening and is not an official upstream ClashX/ClashX Pro release.


## SmartX branch status
- This is an **experimental SmartX branch** for preview testing, not a production release.
- It embeds the **Vernesong Smart fork of mihomo**.
- It is only a local proxy client, and **does not provide proxy servers or subscriptions**.
- Legacy ClashX Pro branding/wording is obsolete in this branch.
- The app keeps the legacy local config directory at `~/.config/clash/`, with additional safe-path validation for config names and writes.
- Before any public distribution, replace signing identities, helper trust requirements, bundle metadata, and complete notarization/release hardening.

## Security model
- Config names are validated by a strict allowlist before building local file paths.
- Suggested remote filenames must be plain basenames. If a suggested filename includes any path component, separator, traversal-like structure, hidden basename, or other invalid form, SmartX falls back to a deterministic SHA256-based `remote-config-<hash>` name instead of salvaging the basename.
- Remote configs are verified before replacement; failed updates must preserve the previous valid file.
- The privileged helper is limited to system proxy management and must not launch binaries/download resources/write arbitrary files.
- Public distribution requires replacing legacy signing identifiers and completing notarization.

## Features

- HTTP/HTTPS and SOCKS protocol
- Surge like configuration
- GeoIP rule support
- Support Vmess/Shadowsocks/Socks5/Trojan
- Support for Netfilter TCP redirect

## Install

Build from source on this branch for preview validation. Legacy public AppCenter links and ClashX Pro release wording are intentionally not used for SmartX preview builds.

## Build
- Make sure have python3 and golang installed in your computer.
- Use the project Ruby in [`.ruby-version`](./.ruby-version). macOS system Ruby 2.6 is not supported for this repository's Bundler dependencies.
- Recommended Ruby setup:
  ```
  brew install rbenv ruby-build
  rbenv install 3.2.4
  rbenv local 3.2.4
  gem install bundler
  bundle install
  ```

- Install Golang
  ```
  brew install golang

  or download from https://golang.org
  ```

- Download deps
  ```
  bash install_dependency.sh
  ```

- Build and run.

## CI for pull requests
- PR CI runs on macOS GitHub Actions and performs unsigned Debug builds (`CODE_SIGNING_ALLOWED=NO`).
- PR CI now uses the same `bash install_dependency.sh` path as local setup, so dashboard resources, `Country.mmdb.gz`, Pods, and the Go c-archive are installed the same way in CI and local environments.
- CI compile-checks the app, embedded go c-archive build, and helper source path, verifies that the Release helper client requirement stays fail-closed, and runs a lightweight security harness.
- CI does not prove notarization or privileged helper installation behavior; local signed validation is still required.

## Config


The default configuration directory is `$HOME/.config/clash`

The default name of the configuration file is `config.yaml`. You can use your custom config name and switch config in menu `Config` section.


For mihomo-compatible config details, refer to mihomo documentation and rule resources compatible with your deployment.

## Advance Config

### 修改代理端口号
1. 在菜单栏->配置->更多设置中修改对应端口号



### Change your status menu icon

  Place your icon file in the `~/.config/clash/menuImage.png`  then restart ClashX

### Change default system ignore list.

- Change by menu -> Config -> Setting -> Bypass proxy settings for these Hosts & Domains

### URL Schemes.

- Using url scheme to import remote config.

  ```
  clash://install-config?url=http%3A%2F%2Fexample.com&name=example
  ```
- Using url scheme to reload current config.

  ```
  clash://update-config
  ```

## Pre-distribution checklist (must be replaced for SmartX release)
- Main bundle identifier.
- Helper bundle identifier and Mach service name.
- `SMAuthorizedClients` and `SMPrivilegedExecutables` requirements.
- Team ID / Developer ID code-signing requirements used by helper trust validation.
- Sparkle appcast URL and signing key material.
- iCloud container identifiers (if iCloud is retained).

Developer note:
- `AllowedClientCodeSigningRequirement` in helper metadata is now driven by `SMARTX_ALLOWED_CLIENT_REQUIREMENT`.
- Debug helper builds intentionally set `SMARTX_ALLOWED_CLIENT_REQUIREMENT` to an empty string. The helper accepts that only in `#if DEBUG`, and logs when the Debug-only bypass is used.
- That Debug override only affects helper XPC trust after the helper is already installed.
- It does **not** make `SMJobBless` succeed for unsigned or ad-hoc local Debug builds.
- Because `SMAuthorizedClients` and `SMPrivilegedExecutables` still contain legacy signing requirements, local Debug builds may still need the legacy install path until identity migration is done.
- Full `SMJobBless` support for SmartX requires a separate identity/signing migration PR.
- Release helper builds must keep `SMARTX_ALLOWED_CLIENT_REQUIREMENT` non-empty. An empty or unresolved Release value is rejected fail-closed by the helper, and CI now checks this build setting explicitly.
- `AllowedClientCodeSigningRequirement` and helper `SMAuthorizedClients` must track the app target bundle identifier (currently `com.doodlenet.ClashX`) or helper IPC/auth can fail for default builds.
- This PR does **not** complete signing identity migration.

### SmartX local helper development

- Xcode Debug builds may use an empty helper client requirement for local development only.
- That empty Debug requirement only allows the installed helper to accept the app over XPC; it does not satisfy the reciprocal `SMJobBless` signing checks.
- Release builds reject an empty helper client requirement and still run `SecCodeCheckValidity`.
- Unsigned or ad-hoc CI artifacts are not suitable for privileged helper testing.
- Copying the app to `/Applications` does not install the helper by itself.
- Helper installation still requires `SMJobBless` or the legacy root install path, and unsigned/ad-hoc Debug builds may still need the legacy path until helper/app signing metadata is migrated.
- Public distribution still requires final Developer ID signing, notarization, final bundle identifiers, final helper identifiers, and final `SMAuthorizedClients` / `SMPrivilegedExecutables`.

Current helper metadata still under later migration review:
- App bundle identifier: `com.doodlenet.ClashX`
- Helper bundle identifier: `com.west2online.ClashX.ProxyConfigHelper`
- Mach service name: `com.west2online.ClashX.ProxyConfigHelper`
- Helper `SMAuthorizedClients`: legacy West2Online requirement
- App `SMPrivilegedExecutables`: helper requirement still points at West2Online helper identity
- Team ID / signing requirement placeholder in Release: `MEWHFZ92DY`

Manual test expectations for this PR:
- Debug: build from Xcode, copy to `/Applications` if needed, launch, trigger helper install, confirm helper installs through `SMJobBless` or the legacy install path, confirm system proxy enable/disable works, and confirm logs show the Debug bypass only when `SMARTX_ALLOWED_CLIENT_REQUIREMENT` is empty.
- Release: build Release with an empty or invalid `SMARTX_ALLOWED_CLIENT_REQUIREMENT`, confirm helper install/connect is rejected, and confirm Release does not accept arbitrary unsigned clients.

Minimal verification for the helper requirement expansion:
- After building, inspect the processed helper plist or embedded `__TEXT,__info_plist` section.
- Example processed plist check:
  `plutil -p ~/Library/Developer/Xcode/DerivedData/<DerivedData>/Build/Intermediates.noindex/ClashX.build/Debug/com.west2online.ClashX.ProxyConfigHelper.build/Objects-normal/arm64/Processed-Info.plist | rg AllowedClientCodeSigningRequirement`
- Example embedded binary check:
  `strings ~/Library/Developer/Xcode/DerivedData/<DerivedData>/Build/Products/Debug/com.west2online.ClashX.ProxyConfigHelper | rg 'AllowedClientCodeSigningRequirement|com.doodlenet.ClashX|MEWHFZ92DY'`
- Expected result: Debug expands to an empty `AllowedClientCodeSigningRequirement`; Release expands to a non-empty placeholder requirement.

### SmartX Core Settings page

- Settings -> Core is currently a status and control surface. It should remain informative even when the core is stopped, `/configs` is unavailable, the helper is missing, or Smart / LightGBM endpoints are unsupported.
- TUN status in this page reflects the current mihomo config only. It does **not** mean full macOS TUN routing support is finished in this branch.
- `SMJobBless` failure in unsigned or ad-hoc local builds is expected, and the legacy helper install path may still succeed, but `ProxyConfigHelper` only manages system proxy operations.
- Helper installation, helper signing migration, and full TUN routing are separate follow-up work. Installing the helper does **not** enable TUN support.
- Full TUN support needs a separate architecture decision, such as a privileged mihomo daemon, a Network Extension, or an external controller/core managed outside SmartX.
- Unsupported mihomo endpoints should degrade gracefully with visible status text instead of leaving the page blank.

Manual test checklist for Settings -> Core:
- Open Settings -> Core before starting the core.
- Open Settings -> Core after starting the embedded core.
- Use a config without `tun`.
- Use a config with `tun.enable: false`.
- Use a config with `tun.enable: true`.
- Stop the core or break `/configs`; the page should still show an error state, not a blank view.
- Delete or rename `Model.bin`; the page should show the model as missing.
- Try manual LightGBM update when the endpoint is unsupported; the button should disable or the status should show unsupported.

### Get process name

You can add the follow config in your config file, and set your proxy mode to rule. Then open the log via help menu in ClashX.
```
script:
  code: |
    def main(ctx, metadata):
      # Log ProcessName
      ctx.log('Process Name: ' + ctx.resolve_process_name(metadata))
      return 'DIRECT'
```

### FAQ

- Q: How to get shell command with external IP?  
  A: Click the clashX menu icon and then press `Option-Command-C`  

### 关闭ClashX的通知

1. 在系统设置中关闭 clashx 的推送权限
2. 在菜单栏->配置->更多设置中选中减少通知

Note：强烈不推荐这么做，这可能导致clashx的很多重要错误提醒无法显示。

### 全局快捷键
- 在菜单栏配置->更多配置中，自定义对应功能的快捷键。（需要1.116.1之后的版本）
- 使用AppleScript设置, 详情点击 [全局快捷键](Shortcuts.md)
