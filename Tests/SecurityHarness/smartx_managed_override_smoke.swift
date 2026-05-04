import Foundation

enum LoggerLevel {
    case warning
}

enum Logger {
    static var loggedWarnings = [String]()

    static func log(_ message: String, level: LoggerLevel) {
        if level == .warning {
            loggedWarnings.append(message)
        }
    }
}

enum Settings {
    static let defaultSmartLightGBMModelUrl = "https://example.com/default-model.bin"
    static var smartLightGBMOverrideConfig = false
    static var smartLightGBMModelUrl = defaultSmartLightGBMModelUrl
    static var smartLightGBMAutoUpdate = false
    static var smartLightGBMUpdateIntervalHours = 72

    static var effectiveSmartLightGBMModelUrl: String {
        if smartLightGBMModelUrl.isEmpty {
            return defaultSmartLightGBMModelUrl
        }
        return smartLightGBMModelUrl
    }
}

enum Paths {
    static let baseDirectoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("smartx-managed-override-smoke-\(UUID().uuidString)", isDirectory: true)
    static let smartXOverridesDirectoryURL = baseDirectoryURL
        .appendingPathComponent(".smartx/overrides", isDirectory: true)
    static let smartXManagedOverrideURL = smartXOverridesDirectoryURL
        .appendingPathComponent("smartx-managed.json", isDirectory: false)
}

@inline(__always)
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("smartx_managed_override_smoke failed: \(message)\n", stderr)
        exit(1)
    }
}

@main
enum SmartXManagedOverrideSmokeMain {
    static func main() {
        do {
            try FileManager.default.createDirectory(at: Paths.baseDirectoryURL, withIntermediateDirectories: true)

            resetEnvironment()

            UserDefaults.standard.set(true, forKey: "smartLightGBMOverrideConfig")
            UserDefaults.standard.set("not-a-url", forKey: "smartLightGBMModelUrl")
            UserDefaults.standard.set(true, forKey: "smartLightGBMAutoUpdate")
            UserDefaults.standard.set(0, forKey: "smartLightGBMUpdateIntervalHours")

            Settings.smartLightGBMOverrideConfig = true
            Settings.smartLightGBMModelUrl = "not-a-url"
            Settings.smartLightGBMAutoUpdate = true
            Settings.smartLightGBMUpdateIntervalHours = 0

            expect(!FileManager.default.fileExists(atPath: Paths.smartXManagedOverrideURL.path), "managed override file should not exist before explicit bootstrap")
            _ = Settings.effectiveSmartLightGBMModelUrl
            expect(!FileManager.default.fileExists(atPath: Paths.smartXManagedOverrideURL.path), "reading the effective model URL should not create the managed override file")

            SmartXManagedOverrideManager.bootstrapIfNeeded()

            expect(FileManager.default.fileExists(atPath: Paths.smartXManagedOverrideURL.path), "bootstrap should persist the managed override file")
            expect(Settings.smartLightGBMModelUrl == Settings.defaultSmartLightGBMModelUrl, "bootstrap should normalize invalid model URLs")
            expect(Settings.smartLightGBMUpdateIntervalHours == 1, "bootstrap should clamp invalid update intervals")

            let loaded = SmartXManagedOverrideManager.load()
            expect(loaded?.lightGBM?.enabled == true, "loaded override should preserve enabled state")
            expect(loaded?.lightGBM?.autoUpdate == true, "loaded override should preserve auto-update state")
            expect(loaded?.lightGBM?.modelURL == Settings.defaultSmartLightGBMModelUrl, "loaded override should use normalized model URL")

            Settings.smartLightGBMModelUrl = "https://example.com/custom-model.bin"
            Settings.smartLightGBMUpdateIntervalHours = 12
            let savedResult = SmartXManagedOverrideManager.persistCurrentSettings()
            if case .saved = savedResult {
            } else {
                expect(false, "persist should report a saved result for the current schema")
            }

            let persisted = SmartXManagedOverrideManager.load()
            expect(persisted?.lightGBM?.modelURL == "https://example.com/custom-model.bin", "persist should update the managed override file")
            expect(persisted?.lightGBM?.updateIntervalHours == 12, "persist should keep valid update intervals")

            let futureOverride = SmartXManagedOverride(schemaVersion: SmartXManagedOverrideManager.currentSchemaVersion + 1,
                                                       lightGBM: LightGBMOverride(enabled: true,
                                                                                  modelURL: "https://example.com/future-model.bin",
                                                                                  autoUpdate: false,
                                                                                  updateIntervalHours: 6))
            try SmartXManagedOverrideManager.save(futureOverride)
            Logger.loggedWarnings.removeAll()
            let futureLoaded = SmartXManagedOverrideManager.load()
            expect(futureLoaded?.schemaVersion == SmartXManagedOverrideManager.currentSchemaVersion + 1, "future schema version should be preserved on load")
            expect(Logger.loggedWarnings.contains { $0.contains("future SmartX managed override schema version") }, "future schema load should emit a warning")
            expect(!SmartXManagedOverrideManager.canSafelyWriteCurrentSchema(), "future schema file should disable normal current-schema writes")

            let futureSchemaJSON = """
            {
              "futureOnly": {
                "keep": "me"
              },
              "lightGBM": {
                "autoUpdate": false,
                "enabled": true,
                "modelURL": "https://example.com/future-model.bin",
                "updateIntervalHours": 6
              },
              "schemaVersion": \(SmartXManagedOverrideManager.currentSchemaVersion + 1)
            }
            """
            try futureSchemaJSON.write(to: Paths.smartXManagedOverrideURL, atomically: true, encoding: .utf8)

            Settings.smartLightGBMModelUrl = "https://example.com/should-not-overwrite.bin"
            Settings.smartLightGBMUpdateIntervalHours = 24
            Logger.loggedWarnings.removeAll()
            let skippedResult = SmartXManagedOverrideManager.persistCurrentSettings()
            switch skippedResult {
            case let .skippedFutureSchema(version):
                expect(version == SmartXManagedOverrideManager.currentSchemaVersion + 1, "future schema skip should report the preserved schema version")
            default:
                expect(false, "future schema save should report a skipped result")
            }

            let persistedFutureJSON = try String(contentsOf: Paths.smartXManagedOverrideURL, encoding: .utf8)
            expect(persistedFutureJSON.contains("\"futureOnly\""), "persist should not overwrite a future-schema file")
            expect(persistedFutureJSON.contains("future-model.bin"), "persist should leave future-schema contents untouched")
            expect(Logger.loggedWarnings.contains { $0.contains("Skipping SmartX managed override write because schema version") }, "persist should warn when it skips overwriting a future schema file")
            expect(Settings.smartLightGBMModelUrl == "https://example.com/should-not-overwrite.bin", "runtime settings should still reflect the in-memory save even when persistence is skipped")
            expect(Settings.smartLightGBMUpdateIntervalHours == 24, "runtime interval should still update in memory when persistence is skipped")

            resetEnvironment()
            UserDefaults.standard.set(true, forKey: "smartLightGBMOverrideConfig")
            UserDefaults.standard.set("https://example.com/legacy-bootstrap-should-not-win.bin", forKey: "smartLightGBMModelUrl")
            UserDefaults.standard.set(false, forKey: "smartLightGBMAutoUpdate")
            UserDefaults.standard.set(8, forKey: "smartLightGBMUpdateIntervalHours")
            Settings.smartLightGBMOverrideConfig = false
            Settings.smartLightGBMModelUrl = "https://example.com/runtime-before-bootstrap.bin"
            Settings.smartLightGBMAutoUpdate = false
            Settings.smartLightGBMUpdateIntervalHours = 4
            let preservedFutureSchemaJSON = """
            {
              "futureOnly": {
                "keep": "me"
              },
              "lightGBM": {
                "autoUpdate": false,
                "enabled": true,
                "modelURL": "https://example.com/future-bootstrap.bin",
                "updateIntervalHours": 6
              },
              "schemaVersion": \(SmartXManagedOverrideManager.currentSchemaVersion + 1)
            }
            """
            try writeRawOverrideJSON(preservedFutureSchemaJSON)
            SmartXManagedOverrideManager.bootstrapIfNeeded()
            let bootstrappedFutureJSON = try String(contentsOf: Paths.smartXManagedOverrideURL, encoding: .utf8)
            expect(bootstrappedFutureJSON == preservedFutureSchemaJSON, "bootstrap should not overwrite a decodable future-schema file")
            expect(Settings.smartLightGBMModelUrl == "https://example.com/future-bootstrap.bin", "bootstrap may apply compatible fields from a decodable future-schema file")
            expect(Settings.smartLightGBMOverrideConfig == true, "bootstrap should apply known enabled state from a decodable future-schema file")

            resetEnvironment()
            UserDefaults.standard.set(true, forKey: "smartLightGBMOverrideConfig")
            UserDefaults.standard.set("https://example.com/legacy-should-not-overwrite-future.bin", forKey: "smartLightGBMModelUrl")
            UserDefaults.standard.set(true, forKey: "smartLightGBMAutoUpdate")
            UserDefaults.standard.set(48, forKey: "smartLightGBMUpdateIntervalHours")
            Settings.smartLightGBMOverrideConfig = false
            Settings.smartLightGBMModelUrl = "https://example.com/runtime-before-incompatible-future.bin"
            Settings.smartLightGBMAutoUpdate = false
            Settings.smartLightGBMUpdateIntervalHours = 12
            let incompatibleFutureSchemaJSON = """
            {
              "lightGBM": [
                "not-a-dictionary"
              ],
              "schemaVersion": \(SmartXManagedOverrideManager.currentSchemaVersion + 2)
            }
            """
            try writeRawOverrideJSON(incompatibleFutureSchemaJSON)
            Logger.loggedWarnings.removeAll()
            SmartXManagedOverrideManager.bootstrapIfNeeded()
            let bootstrappedIncompatibleFutureJSON = try String(contentsOf: Paths.smartXManagedOverrideURL, encoding: .utf8)
            expect(bootstrappedIncompatibleFutureJSON == incompatibleFutureSchemaJSON, "bootstrap should not overwrite an incompatible future-schema file")
            expect(Settings.smartLightGBMModelUrl == "https://example.com/runtime-before-incompatible-future.bin", "bootstrap should leave runtime settings unchanged for an incompatible future-schema file")
            expect(Logger.loggedWarnings.contains { $0.contains("could not be decoded safely") }, "bootstrap should warn when a future-schema file is incompatible")
            Settings.smartLightGBMModelUrl = "https://example.com/persist-after-incompatible-future.bin"
            let incompatibleFuturePersistResult = SmartXManagedOverrideManager.persistCurrentSettings()
            switch incompatibleFuturePersistResult {
            case let .skippedFutureSchema(version):
                expect(version == SmartXManagedOverrideManager.currentSchemaVersion + 2, "persist should still treat an incompatible future-schema file as future and preserve it")
            default:
                expect(false, "persist should preserve an incompatible future-schema file")
            }
            let preservedIncompatibleFutureJSON = try String(contentsOf: Paths.smartXManagedOverrideURL, encoding: .utf8)
            expect(preservedIncompatibleFutureJSON == incompatibleFutureSchemaJSON, "persist should not overwrite an incompatible future-schema file")

            resetEnvironment()
            UserDefaults.standard.set(true, forKey: "smartLightGBMOverrideConfig")
            UserDefaults.standard.set("https://example.com/legacy-should-not-overwrite-unreadable.bin", forKey: "smartLightGBMModelUrl")
            UserDefaults.standard.set(true, forKey: "smartLightGBMAutoUpdate")
            UserDefaults.standard.set(36, forKey: "smartLightGBMUpdateIntervalHours")
            Settings.smartLightGBMOverrideConfig = false
            Settings.smartLightGBMModelUrl = "https://example.com/runtime-before-unreadable.bin"
            Settings.smartLightGBMAutoUpdate = false
            Settings.smartLightGBMUpdateIntervalHours = 9
            let unreadableExistingJSON = """
            {
              "schemaVersion": "future-ish",
              "lightGBM": {
                "enabled": true
              }
            }
            """
            try writeRawOverrideJSON(unreadableExistingJSON)
            Logger.loggedWarnings.removeAll()
            SmartXManagedOverrideManager.bootstrapIfNeeded()
            let preservedUnreadableBootstrapJSON = try String(contentsOf: Paths.smartXManagedOverrideURL, encoding: .utf8)
            expect(preservedUnreadableBootstrapJSON == unreadableExistingJSON, "bootstrap should not overwrite an unreadable existing override file")
            expect(Settings.smartLightGBMModelUrl == "https://example.com/runtime-before-unreadable.bin", "bootstrap should leave runtime settings unchanged for an unreadable existing override file")
            expect(Logger.loggedWarnings.contains { $0.contains("could not be decoded safely") }, "bootstrap should warn when an existing override file is unreadable")
            Settings.smartLightGBMModelUrl = "https://example.com/persist-after-unreadable.bin"
            let unreadablePersistResult = SmartXManagedOverrideManager.persistCurrentSettings()
            switch unreadablePersistResult {
            case .skippedUnreadableExistingFile:
                break
            default:
                expect(false, "persist should return a visible unreadable-file result")
            }
            let preservedUnreadablePersistJSON = try String(contentsOf: Paths.smartXManagedOverrideURL, encoding: .utf8)
            expect(preservedUnreadablePersistJSON == unreadableExistingJSON, "persist should not overwrite an unreadable existing override file")

            print("smartx_managed_override_smoke passed")
        } catch {
            fputs("smartx_managed_override_smoke failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func resetEnvironment() {
        let keys = [
            "smartLightGBMOverrideConfig",
            "smartLightGBMModelUrl",
            "smartLightGBMAutoUpdate",
            "smartLightGBMUpdateIntervalHours"
        ]
        for key in keys {
            UserDefaults.standard.removeObject(forKey: key)
        }

        try? FileManager.default.removeItem(at: Paths.smartXManagedOverrideURL)
        Settings.smartLightGBMOverrideConfig = false
        Settings.smartLightGBMModelUrl = Settings.defaultSmartLightGBMModelUrl
        Settings.smartLightGBMAutoUpdate = false
        Settings.smartLightGBMUpdateIntervalHours = 72
        Logger.loggedWarnings.removeAll()
        SmartXManagedOverrideManager.resetBootstrapStateForTesting()
    }

    private static func writeRawOverrideJSON(_ json: String) throws {
        try FileManager.default.createDirectory(at: Paths.smartXOverridesDirectoryURL, withIntermediateDirectories: true)
        try json.write(to: Paths.smartXManagedOverrideURL, atomically: true, encoding: .utf8)
    }
}
