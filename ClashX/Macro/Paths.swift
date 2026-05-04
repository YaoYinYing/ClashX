//
//  Paths.swift
//  ClashX
//
//  Created by CYC on 2018/8/26.
//  Copyright © 2018年 west2online. All rights reserved.
//
import Foundation

let kConfigFolderPath = "\(NSHomeDirectory())/.config/clash/"

let kDefaultConfigFilePath = "\(kConfigFolderPath)config.yaml"

enum SafeConfigNameError: LocalizedError {
    case empty
    case tooLong(max: Int)
    case hidden
    case reserved
    case invalidCharacter(Character)

    var errorDescription: String? {
        switch self {
        case .empty:
            return NSLocalizedString("Config name must not be empty.", comment: "")
        case let .tooLong(max):
            return String(format: NSLocalizedString("Config name must be at most %d characters.", comment: ""), max)
        case .hidden:
            return NSLocalizedString("Config name must not start with '.'.", comment: "")
        case .reserved:
            return NSLocalizedString("Config name must not be '.' or '..'.", comment: "")
        case let .invalidCharacter(ch):
            return String(format: NSLocalizedString("Config name contains unsupported character '%@'.", comment: ""), String(ch))
        }
    }
}

struct SafeConfigName: Equatable {
    static let maxLength = 80
    let value: String

    init(_ rawName: String) throws {
        let candidate = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { throw SafeConfigNameError.empty }
        guard candidate.count <= Self.maxLength else { throw SafeConfigNameError.tooLong(max: Self.maxLength) }
        guard candidate != ".", candidate != ".." else { throw SafeConfigNameError.reserved }
        guard !candidate.hasPrefix(".") else { throw SafeConfigNameError.hidden }

        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " _-."))
        for scalar in candidate.unicodeScalars {
            if scalar.value == 0 || CharacterSet.controlCharacters.contains(scalar) || !allowed.contains(scalar) {
                throw SafeConfigNameError.invalidCharacter(Character(scalar))
            }
        }
        value = candidate
    }
}

enum Paths {
    static var configDirectoryURL: URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("clash", isDirectory: true)
            .standardizedFileURL
    }

    static var defaultConfigURL: URL {
        configDirectoryURL.appendingPathComponent("config.yaml", isDirectory: false).standardizedFileURL
    }

    static var smartLightGBMModelPath: String {
        return configDirectoryURL.appendingPathComponent("Model.bin").path
    }

    static var smartWeightDataPath: String {
        return configDirectoryURL.appendingPathComponent("smart_weight_data.csv").path
    }

    static var smartXArtifactsDirectoryURL: URL {
        configDirectoryURL
            .appendingPathComponent(".smartx", isDirectory: true)
            .appendingPathComponent("profiles", isDirectory: true)
            .standardizedFileURL
    }

    static var smartXDirectoryURL: URL {
        configDirectoryURL
            .appendingPathComponent(".smartx", isDirectory: true)
            .standardizedFileURL
    }

    static var smartXOverridesDirectoryURL: URL {
        smartXDirectoryURL
            .appendingPathComponent("overrides", isDirectory: true)
            .standardizedFileURL
    }

    static var smartXManagedOverrideURL: URL {
        smartXOverridesDirectoryURL
            .appendingPathComponent("smartx-managed.json", isDirectory: false)
            .standardizedFileURL
    }

    static var smartXDiagnosticsDirectoryURL: URL {
        configDirectoryURL
            .appendingPathComponent(".smartx", isDirectory: true)
            .appendingPathComponent("diagnostics", isDirectory: true)
            .standardizedFileURL
    }

    static var successfulReloadArtifactURL: URL {
        smartXArtifactsDirectoryURL.appendingPathComponent("generated-effective.yaml", isDirectory: false)
            .standardizedFileURL
    }

    /// Compatibility alias. This is not a real generated effective config until the profile pipeline lands.
    static var generatedEffectiveConfigURL: URL {
        successfulReloadArtifactURL
    }

    static var lastKnownGoodConfigURL: URL {
        smartXArtifactsDirectoryURL.appendingPathComponent("last-known-good.yaml", isDirectory: false)
            .standardizedFileURL
    }

    static var successfulReloadMetadataURL: URL {
        smartXArtifactsDirectoryURL.appendingPathComponent("generated-effective.json", isDirectory: false)
            .standardizedFileURL
    }

    /// Compatibility alias. This metadata currently describes a loaded source copy, not a generated effective config.
    static var generatedEffectiveMetadataURL: URL {
        successfulReloadMetadataURL
    }

    static var lastKnownGoodMetadataURL: URL {
        smartXArtifactsDirectoryURL.appendingPathComponent("last-known-good.json", isDirectory: false)
            .standardizedFileURL
    }

    static var providerHealthHistoryURL: URL {
        smartXDiagnosticsDirectoryURL.appendingPathComponent("provider-health-history.json", isDirectory: false)
            .standardizedFileURL
    }

    static func configFileName(for name: SafeConfigName) -> String {
        return "\(name.value).yaml"
    }

    static func localConfigURL(for name: SafeConfigName) throws -> URL {
        try configFileURL(for: name, in: configDirectoryURL)
    }

    static func configFileURL(for name: SafeConfigName, in baseDirectoryURL: URL) throws -> URL {
        let base = baseDirectoryURL.standardizedFileURL.resolvingSymlinksInPath()
        let target = base.appendingPathComponent(configFileName(for: name), isDirectory: false)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        guard target.path.hasPrefix(base.path + "/") || target.path == base.path else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        return target
    }

    static func safeLocalConfigURL(for rawName: String) throws -> URL {
        let safeName = try SafeConfigName(rawName)
        return try localConfigURL(for: safeName)
    }

    static func safeConfigFileURL(for rawName: String, in baseDirectoryURL: URL) throws -> URL {
        let safeName = try SafeConfigName(rawName)
        return try configFileURL(for: safeName, in: baseDirectoryURL)
    }

    /// Compatibility wrapper for legacy call sites.
    /// Security-sensitive code should use throwing URL APIs.
    static func localConfigPath(for name: String) -> String {
        do {
            return try safeLocalConfigURL(for: name).path
        } catch {
            assertionFailure("Invalid config name in compatibility API: \(error)")
            return ""
        }
    }

    /// Compatibility wrapper for legacy call sites.
    /// Security-sensitive code should use throwing URL APIs.
    static func configFileName(for name: String) -> String {
        do {
            return try configFileName(for: SafeConfigName(name))
        } catch {
            assertionFailure("Invalid config name in compatibility API: \(error)")
            return ""
        }
    }
}
