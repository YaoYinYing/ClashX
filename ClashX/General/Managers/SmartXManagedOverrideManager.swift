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

struct SmartXManagedOverride: Codable {
    // Keep schema 1 intentionally small for compatibility. Adding metadata such as
    // updatedAt or lastWrittenBy would widen migration surface before the real
    // effective-config pipeline exists, so this groundwork file only stores the
    // override fields SmartX needs today.
    var schemaVersion: Int
    var lightGBM: LightGBMOverride?
}

struct LightGBMOverride: Codable {
    var enabled: Bool
    var modelURL: String
    var autoUpdate: Bool
    var updateIntervalHours: Int
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

        if let overrideModel = load() {
            applyToSettings(overrideModel)
            return
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
        guard let overrideModel = decodedOverride(logFailures: true) else { return nil }
        recordFutureSchemaIfNeeded(overrideModel)
        return normalized(overrideModel)
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
        SmartXManagedOverride(schemaVersion: currentSchemaVersion,
                              lightGBM: normalizedLightGBMOverride(enabled: Settings.smartLightGBMOverrideConfig,
                                                                   modelURL: Settings.smartLightGBMModelUrl,
                                                                   autoUpdate: Settings.smartLightGBMAutoUpdate,
                                                                   updateIntervalHours: Settings.smartLightGBMUpdateIntervalHours))
    }

    static func persistCurrentSettings() {
        if let futureSchemaVersion = unsafeFutureSchemaVersionOnDisk() {
            Logger.log("Skipping SmartX managed override write because schema version \(futureSchemaVersion) is newer than SmartX schema version \(currentSchemaVersion). The current app may use known fields at runtime, but it will not overwrite the future-schema file during a normal UI save.", level: .warning)
            return
        }

        let overrideModel = captureFromSettings()
        do {
            try save(overrideModel)
            applyToSettings(overrideModel)
        } catch {
            Logger.log("Failed to persist SmartX managed overrides: \(error.localizedDescription)", level: .warning)
        }
    }

    static func canSafelyWriteCurrentSchema() -> Bool {
        unsafeFutureSchemaVersionOnDisk() == nil
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

    private static func unsafeFutureSchemaVersionOnDisk() -> Int? {
        if let loadedFutureSchemaVersion {
            return loadedFutureSchemaVersion
        }
        guard let overrideModel = decodedOverride(logFailures: false) else {
            return nil
        }
        return recordFutureSchemaIfNeeded(overrideModel)
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
