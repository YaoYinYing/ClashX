<h1 align="center">
  <img src="https://github.com/Dreamacro/clash/raw/master/docs/logo.png" alt="Clash" width="200">
  <br>
  ClashX
  <br>
</h1>


A rule based proxy client for macOS based on ClashX, with the SmartX `smartx` branch embedding the Vernesong Smart fork of mihomo through the Go c-archive bridge.

ClashX 旨在提供一个简单轻量化的代理客户端，如果需要更多的定制化，可以考虑使用 [CFW Mac 版](https://github.com/Fndroid/clash_for_windows_pkg/releases) 


## SmartX branch status
- This is an **experimental SmartX branch** for preview testing, not a production release.
- It embeds the **Vernesong Smart fork of mihomo**.
- It is only a local proxy client, and **does not provide proxy servers or subscriptions**.
- Legacy ClashX Pro branding/wording is obsolete in this branch.
- The app keeps the legacy local config directory at `~/.config/clash/`, with additional safe-path validation for config names and writes.
- Before any public distribution, replace signing identities, helper trust requirements, bundle metadata, and complete notarization/release hardening.

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


Checkout [Clash](https://github.com/Dreamacro/clash) or [SS-Rule-Snippet for Clash](https://github.com/Hackl0us/SS-Rule-Snippet/blob/master/LAZY_RULES/clash.yaml) or [lancellc's gitbook](https://lancellc.gitbook.io/clash/) for more detail.

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
