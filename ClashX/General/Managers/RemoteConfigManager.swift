//
//  RemoteConfigManager.swift
//  ClashX
//
//  Created by yicheng on 2018/11/6.
//  Copyright © 2018 west2online. All rights reserved.
//

import Alamofire
import Cocoa
import CryptoKit

class RemoteConfigManager {
    var configs: [RemoteConfigModel] = []
    var refreshActivity: NSBackgroundActivityScheduler?

    static let shared = RemoteConfigManager()

    private init() {
        if let savedConfigs = UserDefaults.standard.object(forKey: "kRemoteConfigs") as? Data {
            let decoder = JSONDecoder()
            if let loadedConfig = try? decoder.decode([RemoteConfigModel].self, from: savedConfigs) {
                configs = loadedConfig
            } else {
                assertionFailure()
            }
        }
        migrateOldRemoteConfig()
        setupAutoUpdateTimer()
    }

    func saveConfigs() {
        Logger.log("Saving Remote Config Setting")
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(configs) {
            UserDefaults.standard.set(encoded, forKey: "kRemoteConfigs")
        }
    }

    func migrateOldRemoteConfig() {
        if let url = UserDefaults.standard.string(forKey: "kRemoteConfigUrl"),
           let name = URL(string: url)?.host {
            let safeName = (try? SafeConfigName(name).value) ?? RemoteConfigManager.deterministicFallbackName(sourceURL: url)
            if safeName != name {
                Logger.log("Migrated legacy remote config to a safe deterministic name", level: .warning)
            }
            configs.append(RemoteConfigModel(url: url, name: safeName))
            UserDefaults.standard.removeObject(forKey: "kRemoteConfigUrl")
            saveConfigs()
        }
    }

    func setupAutoUpdateTimer() {
        refreshActivity?.invalidate()
        refreshActivity = nil
        guard RemoteConfigManager.autoUpdateEnable else {
            Logger.log("autoUpdateEnable did not enable,autoUpateTimer invalidated.")
            return
        }
        Logger.log("set up autoUpateTimer")

        refreshActivity = NSBackgroundActivityScheduler(identifier: "com.ClashX.configupdate")
        refreshActivity?.repeats = true
        refreshActivity?.interval = 60 * 60 * 2 // Two hour
        refreshActivity?.tolerance = 60 * 60

        refreshActivity?.schedule { [weak self] completionHandler in
            self?.autoUpdateCheck()
            completionHandler(NSBackgroundActivityScheduler.Result.finished)
        }
    }

    static var autoUpdateEnable: Bool {
        get {
            return UserDefaults.standard.object(forKey: "kAutoUpdateEnable") as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "kAutoUpdateEnable")
            RemoteConfigManager.shared.setupAutoUpdateTimer()
        }
    }

    @objc func autoUpdateCheck() {
        guard RemoteConfigManager.autoUpdateEnable else { return }
        Logger.log("Tigger config auto update check")
        updateCheck()
    }

    func updateCheck(ignoreTimeLimit: Bool = false, showNotification: Bool = false) {
        let currentConfigName = ConfigManager.selectConfigName

        let group = DispatchGroup()

        for config in configs {
            if config.updating { continue }
            let timeLimitNoMantians = Date().timeIntervalSince(config.updateTime ?? Date(timeIntervalSince1970: 0)) < Settings.configAutoUpdateInterval

            if timeLimitNoMantians && !ignoreTimeLimit {
                Logger.log("[Auto Upgrade] Bypassing \(config.name) due to time check")
                continue
            }
            Logger.log("[Auto Upgrade] Requesting \(config.name)")
            let isCurrentConfig = config.name == currentConfigName
            config.updating = true
            group.enter()
            RemoteConfigManager.updateConfig(config: config) {
                [weak config] error in
                guard let config = config else { return }

                config.updating = false
                group.leave()
                if error == nil {
                    config.updateTime = Date()
                }

                if isCurrentConfig {
                    if let error = error {
                        // Fail
                        if showNotification {
                            NSUserNotificationCenter.default
                                .post(title: NSLocalizedString("Remote Config Update Fail", comment: ""),
                                      info: "\(config.name): \(error)")
                        }

                    } else {
                        // Success
                        if showNotification {
                            let info = "\(config.name): \(NSLocalizedString("Succeed!", comment: ""))"
                            NSUserNotificationCenter.default
                                .post(title: NSLocalizedString("Remote Config Update", comment: ""), info: info)
                        }
                        AppDelegate.shared.updateConfig(showNotification: false)
                    }
                }
                Logger.log("[Auto Upgrade] Finish \(config.name) result: \(error ?? "succeed")")
            }
        }

        group.notify(queue: .main) {
            [weak self] in
            self?.saveConfigs()
        }
    }

    static func getRemoteConfigData(config: RemoteConfigModel, complete: @escaping ((String?, String?) -> Void)) {
        guard var urlRequest = try? URLRequest(url: config.url, method: .get) else {
            assertionFailure()
            Logger.log("[getRemoteConfigData] url incorrect,\(config.name) \(config.url)")
            complete(nil, nil)
            return
        }
        urlRequest.cachePolicy = .reloadIgnoringCacheData

        AF.request(urlRequest)
            .validate()
            .responseString(encoding: .utf8) { res in
                complete(try? res.result.get(), res.response?.suggestedFilename)
            }
    }

    static func updateConfig(config: RemoteConfigModel, complete: ((String?) -> Void)? = nil) {
        getRemoteConfigData(config: config) { configString, suggestedFilename in
            guard let newConfig = configString else {
                complete?(NSLocalizedString("Download fail", comment: ""))
                return
            }

            let verifyRes = verifyConfig(string: newConfig)
            if let error = verifyRes {
                complete?(NSLocalizedString("Remote Config Format Error", comment: "") + ": " + error)
                return
            }

            if config.isPlaceHolderName {
                let name = safeNameFromSuggestedFilename(suggestedFilename, sourceURL: config.url)
                if !shared.configs.contains(where: { $0.name == name }) {
                    config.name = name
                }
            }
            config.isPlaceHolderName = false

            if ICloudManager.shared.useiCloud.value {
                ConfigFileManager.shared.stopWatchConfigFile()
            }
            if config.name == ConfigManager.selectConfigName {
                ConfigFileManager.shared.pauseForNextChange()
            }

            let saveAction: ((URL) -> Void) = { baseDir in
                do {
                    let saveURL = try Paths.safeConfigFileURL(for: config.name, in: baseDir)
                    try writeConfigAtomically(content: newConfig, targetURL: saveURL)
                    complete?(nil)
                } catch {
                    complete?(error.localizedDescription)
                }
            }

            if ICloudManager.shared.useiCloud.value {
                ICloudManager.shared.getUrl { url in
                    guard let url = url else {
                        complete?(NSLocalizedString("iCloud not available", comment: ""))
                        return
                    }
                    saveAction(url)
                }
            } else {
                saveAction(Paths.configDirectoryURL)
            }
        }
    }

    static func safeNameFromSuggestedFilename(_ suggestedFilename: String?, sourceURL: String) -> String {
        if let suggestedFilename,
           isPlainSuggestedFilename(suggestedFilename) {
            let rawName = (suggestedFilename as NSString).deletingPathExtension
            if let safe = try? SafeConfigName(rawName) {
                return safe.value
            }
        }
        return deterministicFallbackName(sourceURL: sourceURL)
    }

    private static func isPlainSuggestedFilename(_ suggestedFilename: String) -> Bool {
        let trimmed = suggestedFilename.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard !trimmed.contains("/") else { return false }
        guard !trimmed.contains("\\") else { return false }
        guard !trimmed.contains(":") else { return false }

        let components = (trimmed as NSString).pathComponents
        guard components.count == 1 else { return false }
        guard components.first == trimmed else { return false }

        return true
    }

    static func deterministicFallbackName(sourceURL: String) -> String {
        let digest = SHA256.hash(data: Data(sourceURL.utf8))
        let suffix = digest.prefix(4).map { String(format: "%02x", $0) }.joined()
        return "remote-config-\(suffix)"
    }

    static func writeConfigAtomically(content: String, targetURL: URL) throws {
        let fileManager = FileManager.default
        let baseDir = targetURL.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath()
        let safeTarget = targetURL.standardizedFileURL.resolvingSymlinksInPath()
        guard safeTarget.path.hasPrefix(baseDir.path + "/") else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        let tempURL = baseDir.appendingPathComponent(".\(UUID().uuidString).tmp.yaml")
        try content.write(to: tempURL, atomically: true, encoding: .utf8)
        let verifyResult = verifyConfig(string: content)
        guard verifyResult == nil else {
            try? fileManager.removeItem(at: tempURL)
            throw NSError(domain: "RemoteConfigManager", code: 1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("Remote Config Format Error", comment: "") + ": " + (verifyResult ?? "")])
        }
        do {
            if fileManager.fileExists(atPath: safeTarget.path) {
                try fileManager.replaceItemAt(safeTarget, withItemAt: tempURL, backupItemName: nil, options: .usingNewMetadataOnly)
            } else {
                try fileManager.moveItem(at: tempURL, to: safeTarget)
            }
        } catch {
            try? fileManager.removeItem(at: tempURL)
            // A failed update must not destroy the last valid config file.
            throw error
        }
    }

    static func verifyConfig(string: String) -> ErrorString? {
        let res = verifyClashConfig(string.goStringBuffer())?.toString() ?? "unknown error"
        if res == "success" {
            return nil
        } else {
            Logger.log(res, level: .error)
            return res
        }
    }

    static func showAdd() {
        let alertView = NSAlert()
        alertView.addButton(withTitle: NSLocalizedString("OK", comment: ""))
        alertView.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        alertView.messageText = NSLocalizedString("Update remote config update interval", comment: "")
        let setupView = RemoteConfigUpdateIntervalSettingView()
        setupView.frame = NSRect(x: 0, y: 0, width: 100, height: 22)
        alertView.accessoryView = setupView
        let response = alertView.runModal()

        guard response == .alertFirstButtonReturn else { return }
        let stringValue = setupView.textfield.stringValue
        guard let intValue = Int(stringValue), intValue > 0 else {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.informativeText = NSLocalizedString("Should be a least 1 hour", comment: "")
            alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
            alert.runModal()
            return
        }
        Settings.configAutoUpdateInterval = TimeInterval(intValue * 60 * 60)
        RemoteConfigManager.shared.autoUpdateCheck()
    }
}
