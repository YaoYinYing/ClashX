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
- `AllowedClientCodeSigningRequirement` in helper metadata is currently a legacy placeholder.
- For local Debug helper testing, replace it with your own signing requirement (or explicitly clear it only in Debug builds).
- This PR does **not** complete signing identity migration.

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
