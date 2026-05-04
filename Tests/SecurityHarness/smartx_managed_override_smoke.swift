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

            let keys = [
                "smartLightGBMOverrideConfig",
                "smartLightGBMModelUrl",
                "smartLightGBMAutoUpdate",
                "smartLightGBMUpdateIntervalHours"
            ]
            for key in keys {
                UserDefaults.standard.removeObject(forKey: key)
            }

            UserDefaults.standard.set(true, forKey: "smartLightGBMOverrideConfig")
            UserDefaults.standard.set("not-a-url", forKey: "smartLightGBMModelUrl")
            UserDefaults.standard.set(true, forKey: "smartLightGBMAutoUpdate")
            UserDefaults.standard.set(0, forKey: "smartLightGBMUpdateIntervalHours")

            Settings.smartLightGBMOverrideConfig = true
            Settings.smartLightGBMModelUrl = "not-a-url"
            Settings.smartLightGBMAutoUpdate = true
            Settings.smartLightGBMUpdateIntervalHours = 0

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
            SmartXManagedOverrideManager.persistCurrentSettings()

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
            SmartXManagedOverrideManager.persistCurrentSettings()

            let persistedFutureJSON = try String(contentsOf: Paths.smartXManagedOverrideURL, encoding: .utf8)
            expect(persistedFutureJSON.contains("\"futureOnly\""), "persist should not overwrite a future-schema file")
            expect(persistedFutureJSON.contains("future-model.bin"), "persist should leave future-schema contents untouched")
            expect(Logger.loggedWarnings.contains { $0.contains("Skipping SmartX managed override write because schema version") }, "persist should warn when it skips overwriting a future schema file")

            print("smartx_managed_override_smoke passed")
        } catch {
            fputs("smartx_managed_override_smoke failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
