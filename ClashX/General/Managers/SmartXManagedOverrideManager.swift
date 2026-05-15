//
//  SmartXManagedOverrideManager.swift
//  ClashX
//
//  Created by Codex on 2026/5/4.
//
//  This file persists SmartX-owned JSON overrides at Paths.smartXManagedOverrideURL.
//  It does not mutate remote subscription YAML, and it is not yet merged into a
//  generated effective config pipeline. The current override file exists to keep
//  SmartX-managed LightGBM settings durable and to sync those runtime settings
//  into the active core path.

import Foundation

enum SmartXManagedOverrideDiskState {
    case missing
    case currentOrCompatible(SmartXManagedOverride)
    case futureSchema(version: Int, rawData: Data)
    case unreadableOrIncompatible(String)
}

enum SmartXManagedOverridePersistenceResult {
    case saved
    case skippedFutureSchema(version: Int)
    case skippedUnreadableExistingFile(String)
    case failed(String)

    var statusText: String {
        switch self {
        case .saved:
            return NSLocalizedString("Saved to the SmartX managed override file.", comment: "")
        case let .skippedFutureSchema(version):
            return String(format: NSLocalizedString("Applied runtime settings, but preserved a newer SmartX override schema (v%d) instead of overwriting it.", comment: ""), version)
        case .skippedUnreadableExistingFile:
            return NSLocalizedString("Applied runtime settings, but did not overwrite the existing SmartX managed override file because it could not be decoded safely.", comment: "")
        case let .failed(message):
            return String(format: NSLocalizedString("Applied runtime settings, but failed to persist the SmartX managed override file: %@", comment: ""), message)
        }
    }

    var warningText: String? {
        switch self {
        case .saved:
            return nil
        case .skippedFutureSchema, .skippedUnreadableExistingFile, .failed:
            return statusText
        }
    }
}

enum SmartXManagedOverrideManager {
    static let currentSchemaVersion = 1

    private static var hasBootstrapped = false
    private static var loadedFutureSchemaVersion: Int?
    private static let legacyKeys = [
        "smartLightGBMOverrideConfig",
        "smartLightGBMModelUrl",
        "smartLightGBMAutoUpdate",
        "smartLightGBMUpdateIntervalHours"
    ]

    static func bootstrapIfNeeded() {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true

        switch diskState(logFailures: true) {
        case let .currentOrCompatible(overrideModel):
            applyToSettings(overrideModel)
            return
        case let .futureSchema(version, rawData):
            loadedFutureSchemaVersion = max(loadedFutureSchemaVersion ?? 0, version)
            Logger.log("Loaded future SmartX managed override schema version \(version). SmartX will preserve that file version until settings are saved again.", level: .warning)
            if let overrideModel = decodedOverride(from: rawData, logFailures: false) {
                applyToSettings(overrideModel)
            } else {
                Logger.log("Existing SmartX managed override file uses future schema version \(version) and could not be decoded safely. SmartX will preserve the file and leave compatibility-cache settings unchanged.", level: .warning)
            }
            return
        case let .unreadableOrIncompatible(message):
            Logger.log(message, level: .warning)
            return
        case .missing:
            break
        }

        guard legacySettingsExist else { return }
        let overrideModel = captureFromSettings()
        do {
            try save(overrideModel)
        } catch {
            Logger.log("Failed to migrate legacy SmartX managed overrides: \(error.localizedDescription)", level: .warning)
        }
        applyToSettings(overrideModel)
    }

    static func load() -> SmartXManagedOverride? {
        switch diskState(logFailures: true) {
        case let .currentOrCompatible(overrideModel):
            return overrideModel
        case let .futureSchema(version, rawData):
            loadedFutureSchemaVersion = max(loadedFutureSchemaVersion ?? 0, version)
            Logger.log("Loaded future SmartX managed override schema version \(version). SmartX will preserve that file version until settings are saved again.", level: .warning)
            if let overrideModel = decodedOverride(from: rawData, logFailures: false) {
                return normalized(overrideModel)
            }
            Logger.log("Existing SmartX managed override file uses future schema version \(version) and could not be decoded safely. SmartX will preserve the file and leave compatibility-cache settings unchanged.", level: .warning)
            return nil
        case let .unreadableOrIncompatible(message):
            Logger.log(message, level: .warning)
            return nil
        case .missing:
            return nil
        }
    }

    static func save(_ overrideModel: SmartXManagedOverride) throws {
        let normalizedOverride = normalized(overrideModel)
        try ensureOverrideDirectory()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(normalizedOverride)
        try data.write(to: Paths.smartXManagedOverrideURL, options: .atomic)
    }

    static func applyToSettings(_ overrideModel: SmartXManagedOverride? = nil) {
        let resolvedOverride = overrideModel ?? load()
        guard let lightGBM = resolvedOverride?.lightGBM else { return }
        Settings.smartLightGBMOverrideConfig = lightGBM.enabled
        Settings.smartLightGBMModelUrl = lightGBM.modelURL
        Settings.smartLightGBMAutoUpdate = lightGBM.autoUpdate
        Settings.smartLightGBMUpdateIntervalHours = max(1, lightGBM.updateIntervalHours)
    }

    static func captureFromSettings() -> SmartXManagedOverride {
        // Read raw compatibility-cache values only. This capture path must not depend
        // on effective getters that could later grow hidden migration side effects.
        SmartXManagedOverride(schemaVersion: currentSchemaVersion,
                              lightGBM: normalizedLightGBMOverride(enabled: Settings.smartLightGBMOverrideConfig,
                                                                   modelURL: Settings.smartLightGBMModelUrl,
                                                                   autoUpdate: Settings.smartLightGBMAutoUpdate,
                                                                   updateIntervalHours: Settings.smartLightGBMUpdateIntervalHours))
    }

    static func persistCurrentSettings() -> SmartXManagedOverridePersistenceResult {
        switch diskState(logFailures: false) {
        case let .futureSchema(version, _):
            Logger.log("Skipping SmartX managed override write because schema version \(version) is newer than SmartX schema version \(currentSchemaVersion). The current app may use known fields at runtime, but it will not overwrite the future-schema file during a normal UI save.", level: .warning)
            return .skippedFutureSchema(version: version)
        case let .unreadableOrIncompatible(message):
            Logger.log(message, level: .warning)
            return .skippedUnreadableExistingFile(message)
        case .missing, .currentOrCompatible:
            break
        }

        if let futureSchemaVersion = unsafeFutureSchemaVersionOnDisk() {
            Logger.log("Skipping SmartX managed override write because schema version \(futureSchemaVersion) is newer than SmartX schema version \(currentSchemaVersion). The current app may use known fields at runtime, but it will not overwrite the future-schema file during a normal UI save.", level: .warning)
            return .skippedFutureSchema(version: futureSchemaVersion)
        }

        let overrideModel = captureFromSettings()
        do {
            try save(overrideModel)
            applyToSettings(overrideModel)
            return .saved
        } catch {
            Logger.log("Failed to persist SmartX managed overrides: \(error.localizedDescription)", level: .warning)
            return .failed(error.localizedDescription)
        }
    }

    static func canSafelyWriteCurrentSchema() -> Bool {
        switch diskState(logFailures: false) {
        case .missing, .currentOrCompatible:
            return true
        case .futureSchema, .unreadableOrIncompatible:
            return false
        }
    }

    static func resetBootstrapStateForTesting() {
        hasBootstrapped = false
        loadedFutureSchemaVersion = nil
    }

    private static func ensureOverrideDirectory() throws {
        try FileManager.default.createDirectory(at: Paths.smartXOverridesDirectoryURL,
                                                withIntermediateDirectories: true,
                                                attributes: nil)
    }

    private static var legacySettingsExist: Bool {
        legacyKeys.contains { UserDefaults.standard.object(forKey: $0) != nil }
    }

    private static func decodedOverride(logFailures: Bool) -> SmartXManagedOverride? {
        guard let data = try? Data(contentsOf: Paths.smartXManagedOverrideURL) else {
            return nil
        }
        return decodedOverride(from: data, logFailures: logFailures)
    }

    private static func decodedOverride(from data: Data, logFailures: Bool) -> SmartXManagedOverride? {
        do {
            return try JSONDecoder().decode(SmartXManagedOverride.self, from: data)
        } catch {
            if logFailures {
                Logger.log("Failed to decode SmartX managed overrides: \(error.localizedDescription)", level: .warning)
            }
            return nil
        }
    }

    @discardableResult
    private static func recordFutureSchemaIfNeeded(_ overrideModel: SmartXManagedOverride) -> Int? {
        guard overrideModel.schemaVersion > currentSchemaVersion else { return nil }
        loadedFutureSchemaVersion = max(loadedFutureSchemaVersion ?? 0, overrideModel.schemaVersion)
        Logger.log("Loaded future SmartX managed override schema version \(overrideModel.schemaVersion). SmartX will preserve that file version until settings are saved again.", level: .warning)
        return overrideModel.schemaVersion
    }

    private static func diskState(logFailures: Bool) -> SmartXManagedOverrideDiskState {
        guard let data = try? Data(contentsOf: Paths.smartXManagedOverrideURL) else {
            return .missing
        }

        switch schemaProbe(from: data) {
        case let .futureSchema(version):
            return .futureSchema(version: version, rawData: data)
        case .currentOrMissingSchema:
            if let overrideModel = decodedOverride(from: data, logFailures: logFailures) {
                return .currentOrCompatible(normalized(overrideModel))
            }
            return .unreadableOrIncompatible(NSLocalizedString("Existing SmartX managed override file could not be decoded safely. SmartX will preserve the file and leave compatibility-cache settings unchanged.", comment: ""))
        case let .invalid(message):
            return .unreadableOrIncompatible(message)
        }
    }

    private enum SchemaProbeResult {
        case currentOrMissingSchema
        case futureSchema(Int)
        case invalid(String)
    }

    private static func schemaProbe(from data: Data) -> SchemaProbeResult {
        let unreadableMessage = NSLocalizedString("Existing SmartX managed override file could not be decoded safely. SmartX will preserve the file and leave compatibility-cache settings unchanged.", comment: "")
        guard let object = try? JSONSerialization.jsonObject(with: data, options: []),
              let dictionary = object as? [String: Any]
        else {
            return .invalid(unreadableMessage)
        }

        guard let rawSchemaVersion = dictionary["schemaVersion"] else {
            return .currentOrMissingSchema
        }

        if let number = rawSchemaVersion as? NSNumber {
            let doubleValue = number.doubleValue
            guard doubleValue.rounded(.towardZero) == doubleValue else {
                return .invalid(unreadableMessage)
            }
            let version = number.intValue
            if version > currentSchemaVersion {
                return .futureSchema(version)
            }
            return .currentOrMissingSchema
        }

        if let stringValue = rawSchemaVersion as? String, let version = Int(stringValue) {
            if version > currentSchemaVersion {
                return .futureSchema(version)
            }
            return .currentOrMissingSchema
        }

        return .invalid(unreadableMessage)
    }

    private static func unsafeFutureSchemaVersionOnDisk() -> Int? {
        if let loadedFutureSchemaVersion {
            return loadedFutureSchemaVersion
        }
        guard case let .futureSchema(version, _) = diskState(logFailures: false) else {
            return nil
        }
        loadedFutureSchemaVersion = max(loadedFutureSchemaVersion ?? 0, version)
        return version
    }

    private static func normalized(_ overrideModel: SmartXManagedOverride) -> SmartXManagedOverride {
        return SmartXManagedOverride(schemaVersion: max(currentSchemaVersion, overrideModel.schemaVersion),
                                     lightGBM: overrideModel.lightGBM.map(normalized))
    }

    private static func normalized(_ overrideValue: LightGBMOverride) -> LightGBMOverride {
        normalizedLightGBMOverride(enabled: overrideValue.enabled,
                                   modelURL: overrideValue.modelURL,
                                   autoUpdate: overrideValue.autoUpdate,
                                   updateIntervalHours: overrideValue.updateIntervalHours)
    }

    private static func normalizedLightGBMOverride(enabled: Bool,
                                                   modelURL: String,
                                                   autoUpdate: Bool,
                                                   updateIntervalHours: Int) -> LightGBMOverride {
        LightGBMOverride(enabled: enabled,
                         modelURL: validatedModelURL(modelURL),
                         autoUpdate: autoUpdate,
                         updateIntervalHours: max(1, updateIntervalHours))
    }

    private static func validatedModelURL(_ rawURL: String) -> String {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        // Invalid or unsupported URLs fall back to the SmartX default model URL, but
        // the other override fields remain intact so enablement, auto-update, and the
        // persisted interval survive normalization.
        guard !trimmed.isEmpty,
              let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host?.isEmpty == false
        else {
            return Settings.defaultSmartLightGBMModelUrl
        }
        return trimmed
    }
}
