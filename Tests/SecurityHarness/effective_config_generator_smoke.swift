import Foundation

struct SmartXManagedOverride {
    var schemaVersion: Int
    var lightGBM: LightGBMOverride?
}

struct LightGBMOverride {
    var enabled: Bool
    var modelURL: String
    var autoUpdate: Bool
    var updateIntervalHours: Int
}

enum Logger {
    enum Level {
        case info
    }

    static func log(_: String, level _: Level = .info) {}
}

@inline(__always)
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("effective_config_generator_smoke failed: \(message)\n", stderr)
        exit(1)
    }
}

@main
enum EffectiveConfigGeneratorSmokeMain {
    static func main() {
        let baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("smartx-effective-config-\(UUID().uuidString).yaml", isDirectory: false)
        let override = SmartXManagedOverride(schemaVersion: 1,
                                             lightGBM: LightGBMOverride(enabled: true,
                                                                        modelURL: "https://example.com/model.bin",
                                                                        autoUpdate: true,
                                                                        updateIntervalHours: 72))

        let result = EffectiveConfigGenerator.generateLightGBMManagedOverrideEffectiveConfig(baseConfigURL: baseURL,
                                                                                             managedOverride: override)
        expect(!result.isGenerated, "generator should stay explicit about unsupported generation")

        switch result {
        case let .unsupported(reason):
            expect(reason.localizedCaseInsensitiveContains("yaml emitter"), "unsupported reason should explain the safe YAML emitter requirement")
            expect(reason.localizedCaseInsensitiveContains("lightgbm"), "unsupported reason should mention the managed LightGBM override scope")
        }

        print("effective_config_generator_smoke passed")
    }
}
