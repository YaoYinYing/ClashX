//
//  SmartXManagedOverrideManager.swift
//  ClashX
//
//  Created by Codex on 2026/5/4.
//

import Foundation

struct SmartXManagedOverride: Codable {
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
        guard let data = try? Data(contentsOf: Paths.smartXManagedOverrideURL) else {
            return nil
        }

        do {
            let overrideModel = try JSONDecoder().decode(SmartXManagedOverride.self, from: data)
            return normalized(overrideModel)
        } catch {
            Logger.log("Failed to decode SmartX managed overrides: \(error.localizedDescription)", level: .warning)
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
        SmartXManagedOverride(schemaVersion: currentSchemaVersion,
                              lightGBM: normalizedLightGBMOverride(enabled: Settings.smartLightGBMOverrideConfig,
                                                                   modelURL: Settings.smartLightGBMModelUrl,
                                                                   autoUpdate: Settings.smartLightGBMAutoUpdate,
                                                                   updateIntervalHours: Settings.smartLightGBMUpdateIntervalHours))
    }

    static func persistCurrentSettings() {
        let overrideModel = captureFromSettings()
        do {
            try save(overrideModel)
            applyToSettings(overrideModel)
        } catch {
            Logger.log("Failed to persist SmartX managed overrides: \(error.localizedDescription)", level: .warning)
        }
    }

    private static func ensureOverrideDirectory() throws {
        try FileManager.default.createDirectory(at: Paths.smartXOverridesDirectoryURL,
                                                withIntermediateDirectories: true,
                                                attributes: nil)
    }

    private static var legacySettingsExist: Bool {
        legacyKeys.contains { UserDefaults.standard.object(forKey: $0) != nil }
    }

    private static func normalized(_ overrideModel: SmartXManagedOverride) -> SmartXManagedOverride {
        SmartXManagedOverride(schemaVersion: max(currentSchemaVersion, overrideModel.schemaVersion),
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
