//
//  ConfigManager.swift
//  ClashX
//
//  Created by CYC on 2018/6/12.
//  Copyright © 2018年 yichengchen. All rights reserved.
//

import Cocoa
import Foundation
import RxCocoa
import RxSwift

enum ConfigProfileKind: String {
    case local = "Local"
    case remote = "Remote"
}

struct ConfigProfileDescriptor {
    let name: String
    let kind: ConfigProfileKind
    let isActive: Bool
    let localURL: URL?
    let remoteURL: String?
    let lastUpdate: Date?
    let fileExists: Bool
    let validationSummary: String?
    let lastFetchSummary: String?

    var menuTitle: String {
        "\(name) [\(kind.rawValue)]"
    }

    var sourceSummary: String {
        if let remoteURL, kind == .remote {
            return remoteURL
        }
        return localURL?.path ?? NSLocalizedString("Unavailable", comment: "")
    }

    var updateSummary: String {
        guard kind == .remote else {
            return NSLocalizedString("Manual local profile", comment: "")
        }
        guard let lastUpdate else {
            return NSLocalizedString("Never updated", comment: "")
        }
        return DateFormatter.localizedString(from: lastUpdate, dateStyle: .short, timeStyle: .short)
    }

    var statusSummary: String {
        let activity = isActive ? NSLocalizedString("Active", comment: "") : NSLocalizedString("Inactive", comment: "")
        let fileStatus = fileExists ? NSLocalizedString("cache present", comment: "") : NSLocalizedString("cache missing", comment: "")
        if kind == .remote {
            let validation = validationSummary ?? NSLocalizedString("Validation unknown", comment: "")
            return "\(activity), \(fileStatus), \(validation)"
        }
        return "\(activity), \(fileStatus)"
    }

    var toolTip: String {
        var lines = [
            "\(NSLocalizedString("Profile Type", comment: "")): \(kind.rawValue)",
            "\(NSLocalizedString("Profile Name", comment: "")): \(name)",
            "\(NSLocalizedString("Source", comment: "")): \(sourceSummary)",
            "\(NSLocalizedString("Status", comment: "")): \(statusSummary)",
            "\(NSLocalizedString("Last Update", comment: "")): \(updateSummary)"
        ]
        if let lastFetchSummary, kind == .remote {
            lines.append("\(NSLocalizedString("Last Fetch", comment: "")): \(lastFetchSummary)")
        }
        return lines.joined(separator: "\n")
    }
}

class ConfigManager {
    static let shared = ConfigManager()
    private let disposeBag = DisposeBag()
    var apiPort = "8080"
    var allowExternalControl = false
    var apiSecret: String = ""
    var overrideApiURL: URL?
    var overrideSecret: String?

    var currentConfig: ClashConfig? {
        get {
            return currentConfigVariable.value
        }

        set {
            currentConfigVariable.accept(newValue)
        }
    }

    var currentConfigVariable = BehaviorRelay<ClashConfig?>(value: nil)

    var isRunning: Bool {
        get {
            return isRunningVariable.value
        }

        set {
            isRunningVariable.accept(newValue)
        }
    }

    static var selectConfigName: String {
        get {
            if shared.isRunning {
                return UserDefaults.standard.string(forKey: "selectConfigName") ?? "config"
            }
            return "config"
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "selectConfigName")
            watchCurrentConfigFile()
        }
    }

    static func watchCurrentConfigFile() {
        guard let safeName = try? SafeConfigName(selectConfigName) else {
            Logger.log("Skip watching config file due to invalid selected config name", level: .error)
            return
        }
        if ICloudManager.shared.useiCloud.value {
            ICloudManager.shared.getUrl { url in
                guard let url = url else { return }
                guard let configUrl = try? Paths.configFileURL(for: safeName, in: url) else {
                    Logger.log("Skip watching iCloud config due to unsafe config path", level: .error)
                    return
                }
                ConfigFileManager.shared.watchFile(path: configUrl.path)
            }
        } else {
            guard let localPath = try? Paths.localConfigURL(for: safeName).path else {
                Logger.log("Skip watching local config due to unsafe config path", level: .error)
                return
            }
            ConfigFileManager.shared.watchFile(path: localPath)
        }
    }

    let isRunningVariable = BehaviorRelay<Bool>(value: false)

    var proxyPortAutoSet: Bool {
        get {
            return UserDefaults.standard.bool(forKey: "proxyPortAutoSet")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "proxyPortAutoSet")
        }
    }

    let proxyPortAutoSetObservable = UserDefaults.standard.rx.observe(Bool.self, "proxyPortAutoSet").map { $0 ?? false }

    var isProxySetByOtherVariable = BehaviorRelay<Bool>(value: false)
    var proxyShouldPaused = BehaviorRelay<Bool>(value: false)

    var showNetSpeedIndicator: Bool {
        get {
            return UserDefaults.standard.bool(forKey: "showNetSpeedIndicator")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "showNetSpeedIndicator")
        }
    }

    let showNetSpeedIndicatorObservable = UserDefaults.standard.rx.observe(Bool.self, "showNetSpeedIndicator")

    static var apiUrl: String {
        if let override = shared.overrideApiURL {
            return override.absoluteString
        }
        return "http://127.0.0.1:\(shared.apiPort)"
    }

    static var webSocketUrl: String {
        if let override = shared.overrideApiURL, var comp = URLComponents(url: override, resolvingAgainstBaseURL: true) {
            if comp.scheme == "https" {
                comp.scheme = "wss"
            } else {
                comp.scheme = "ws"
            }
            return comp.url?.absoluteString ?? ""
        }
        return "ws://127.0.0.1:\(shared.apiPort)"
    }

    static var selectedProxyRecords = SavedProxyModel.loadsFromUserDefault() {
        didSet {
            SavedProxyModel.save(selectedProxyRecords)
        }
    }

    static var selectOutBoundMode: ClashProxyMode {
        get {
            return ClashProxyMode(rawValue: UserDefaults.standard.string(forKey: "selectOutBoundMode") ?? "") ?? .rule
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "selectOutBoundMode")
        }
    }

    static var allowConnectFromLan: Bool {
        get {
            return UserDefaults.standard.bool(forKey: "allowConnectFromLan")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "allowConnectFromLan")
        }
    }

    static var selectLoggingApiLevel: ClashLogLevel {
        get {
            return ClashLogLevel(rawValue: UserDefaults.standard.string(forKey: "selectLoggingApiLevel") ?? "") ?? .info
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "selectLoggingApiLevel")
        }
    }

    static func getConfigPath(configName: String, complete: ((Result<String, Error>) -> Void)? = nil) {
        let safeName: SafeConfigName
        do {
            safeName = try SafeConfigName(configName)
        } catch {
            complete?(.failure(error))
            return
        }
        if ICloudManager.shared.useiCloud.value {
            ICloudManager.shared.getUrl { url in
                guard let url = url else {
                    complete?(.failure(NSError(domain: "ConfigManager", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("iCloud not available", comment: "")])))
                    return
                }
                do {
                    let configPath = try Paths.configFileURL(for: safeName, in: url).path
                    complete?(.success(configPath))
                } catch {
                    complete?(.failure(error))
                }
            }
        } else {
            do {
                let filePath = try Paths.localConfigURL(for: safeName).path
                complete?(.success(filePath))
            } catch {
                complete?(.failure(error))
            }
        }
    }
}

extension ConfigManager {
    static func getConfigFilesList() -> [String] {
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(atPath: kConfigFolderPath)
            let names = fileURLs
                .filter { $0.lowercased().hasSuffix(".yaml") }
                .compactMap { filename -> String? in
                    let name = (filename as NSString).deletingPathExtension
                    if let safeName = try? SafeConfigName(name) {
                        return safeName.value
                    }
                    Logger.log("Skipped unsafe config filename while listing configs", level: .warning)
                    return nil
                }
            return names.isEmpty ? ["config"] : names
        } catch {
            return ["config"]
        }
    }

    static func getProfileDescriptors(complete: @escaping ([ConfigProfileDescriptor]) -> Void) {
        if ICloudManager.shared.useiCloud.value {
            ICloudManager.shared.getUrl { url in
                guard let url else {
                    complete(buildProfileDescriptors(configNames: [], baseDirectoryURL: nil))
                    return
                }
                ICloudManager.shared.getConfigFilesList { list in
                    complete(buildProfileDescriptors(configNames: list, baseDirectoryURL: url))
                }
            }
            return
        }

        complete(buildProfileDescriptors(configNames: getConfigFilesList(), baseDirectoryURL: Paths.configDirectoryURL))
    }

    static func currentProfileDescriptor() -> ConfigProfileDescriptor {
        let baseDirectoryURL = ICloudManager.shared.useiCloud.value ? nil : Paths.configDirectoryURL
        return buildProfileDescriptor(name: selectConfigName, baseDirectoryURL: baseDirectoryURL)
    }

    static func profileDescriptor(name: String) -> ConfigProfileDescriptor {
        let baseDirectoryURL = ICloudManager.shared.useiCloud.value ? nil : Paths.configDirectoryURL
        return buildProfileDescriptor(name: name, baseDirectoryURL: baseDirectoryURL)
    }

    private static func buildProfileDescriptors(configNames: [String], baseDirectoryURL: URL?) -> [ConfigProfileDescriptor] {
        configNames
            .map { buildProfileDescriptor(name: $0, baseDirectoryURL: baseDirectoryURL) }
            .sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    private static func buildProfileDescriptor(name: String, baseDirectoryURL: URL?) -> ConfigProfileDescriptor {
        let remoteConfig = RemoteConfigManager.shared.configs.first { $0.name == name }
        let localURL = resolvedConfigURL(name: name, baseDirectoryURL: baseDirectoryURL)
        let fileExists = localURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        return ConfigProfileDescriptor(name: name,
                                       kind: remoteConfig == nil ? .local : .remote,
                                       isActive: selectConfigName == name,
                                       localURL: localURL,
                                       remoteURL: remoteConfig?.url,
                                       lastUpdate: remoteConfig?.updateTime,
                                       fileExists: fileExists,
                                       validationSummary: remoteConfig?.validationSummary(),
                                       lastFetchSummary: remoteConfig?.updateResultSummary())
    }

    private static func resolvedConfigURL(name: String, baseDirectoryURL: URL?) -> URL? {
        guard let baseDirectoryURL,
              let safeName = try? SafeConfigName(name) else {
            return nil
        }
        return try? Paths.configFileURL(for: safeName, in: baseDirectoryURL)
    }
}
