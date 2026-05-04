//
//  Settings.swift
//  ClashX
//
//  Created by yicheng on 2020/12/18.
//  Copyright © 2020 west2online. All rights reserved.
//

import Foundation
enum Settings {
    static let defaultMmdbDownloadUrl = "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.metadb"
    @UserDefault("mmdbDownloadUrl", defaultValue: defaultMmdbDownloadUrl)
    static var mmdbDownloadUrl: String

    static let defaultSmartLightGBMModelUrl = "https://github.com/vernesong/mihomo/releases/download/LightGBM-Model/Model.bin"
    @UserDefault("smartLightGBMOverrideConfig", defaultValue: false)
    static var smartLightGBMOverrideConfig: Bool

    @UserDefault("smartLightGBMModelUrl", defaultValue: defaultSmartLightGBMModelUrl)
    static var smartLightGBMModelUrl: String

    @UserDefault("smartLightGBMAutoUpdate", defaultValue: false)
    static var smartLightGBMAutoUpdate: Bool

    @UserDefault("smartLightGBMUpdateIntervalHours", defaultValue: 72)
    static var smartLightGBMUpdateIntervalHours: Int

    static var effectiveSmartLightGBMModelUrl: String {
        bootstrapSmartXManagedOverridesIfNeeded()
        if smartLightGBMModelUrl.isEmpty {
            return defaultSmartLightGBMModelUrl
        }
        return smartLightGBMModelUrl
    }

    static func bootstrapSmartXManagedOverridesIfNeeded() {
        SmartXManagedOverrideManager.bootstrapIfNeeded()
    }

    static func syncSmartLightGBMOptionsToCore() {
        bootstrapSmartXManagedOverridesIfNeeded()
        clash_setLightGBMOptions(smartLightGBMOverrideConfig.goObject(),
                                 effectiveSmartLightGBMModelUrl.goStringBuffer(),
                                 smartLightGBMAutoUpdate.goObject(),
                                 GoInt(smartLightGBMUpdateIntervalHours))
    }

    @UserDefault("filterInterface", defaultValue: true)
    static var filterInterface: Bool

    @UserDefault("disableNoti", defaultValue: false)
    static var disableNoti: Bool

    @UserDefault("configAutoUpdateInterval", defaultValue: 48 * 60 * 60)
    static var configAutoUpdateInterval: TimeInterval

    static let proxyIgnoreListDefaultValue = ["192.168.0.0/16",
                                              "10.0.0.0/8",
                                              "172.16.0.0/12",
                                              "127.0.0.1",
                                              "localhost",
                                              "*.local",
                                              "timestamp.apple.com",
                                              "sequoia.apple.com",
                                              "seed-sequoia.siri.apple.com"]
    @UserDefault("proxyIgnoreList", defaultValue: proxyIgnoreListDefaultValue)
    static var proxyIgnoreList: [String]

    @UserDefault("disableMenubarNotice", defaultValue: false)
    static var disableMenubarNotice: Bool

    @UserDefault("proxyPort", defaultValue: 0)
    static var proxyPort: Int

    @UserDefault("apiPort", defaultValue: 0)
    static var apiPort: Int

    @UserDefault("apiPortAllowLan", defaultValue: false)
    static var apiPortAllowLan: Bool

    @UserDefault("disableSSIDList", defaultValue: [])
    static var disableSSIDList: [String]

    @UserDefault("enableIPV6", defaultValue: false)
    static var enableIPV6: Bool

    static let apiSecretKey = "api-secret"

    static var isApiSecretSet: Bool {
        return UserDefaults.standard.object(forKey: apiSecretKey) != nil
    }

    @UserDefault(apiSecretKey, defaultValue: "")
    static var apiSecret: String

    @UserDefault("overrideConfigSecret", defaultValue: false)
    static var overrideConfigSecret: Bool

    @UserDefault("kBuiltInApiMode", defaultValue: true)
    static var builtInApiMode: Bool

    static let disableShowCurrentProxyInMenu = !AppDelegate.isAboveMacOS14

    static let defaultBenchmarkUrl = "http://cp.cloudflare.com/generate_204"
    @UserDefault("benchMarkUrl", defaultValue: defaultBenchmarkUrl)
    static var benchMarkUrl: String {
        didSet {
            if benchMarkUrl.isEmpty {
                benchMarkUrl = defaultBenchmarkUrl
            }
        }
    }

    @UserDefault("kDisableRestoreProxy", defaultValue: false)
    static var disableRestoreProxy: Bool

    static var embeddedCoreVersion: String {
        Bundle.main.infoDictionary?["coreVersion"] as? String ?? "unknown"
    }

    static var embeddedCoreCommit: String {
        Bundle.main.infoDictionary?["gitCommit"] as? String ?? "unknown"
    }

    static var embeddedCoreBranch: String {
        Bundle.main.infoDictionary?["gitBranch"] as? String ?? "unknown"
    }

    static var embeddedCoreBuildTime: String {
        Bundle.main.infoDictionary?["buildTime"] as? String ?? "unknown"
    }

    static var isUsingEmbeddedCore: Bool {
        RemoteControlManager.selectConfig == nil && builtInApiMode
    }

    static var activeControllerURL: String {
        ConfigManager.apiUrl
    }
}
