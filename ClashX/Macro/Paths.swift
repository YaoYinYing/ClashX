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

    static func localConfigPath(for name: String) -> String {
        guard let safeName = try? SafeConfigName(name),
              let safeURL = try? localConfigURL(for: safeName) else {
            return defaultConfigURL.path
        }
        return safeURL.path
    }

    static func configFileName(for name: String) -> String {
        if let safeName = try? SafeConfigName(name) {
            return configFileName(for: safeName)
        }
        return "config.yaml"
    }
}
