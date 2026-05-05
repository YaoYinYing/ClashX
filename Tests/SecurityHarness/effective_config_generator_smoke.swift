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

        let request = EffectiveConfigGenerationRequest(baseConfigURL: baseURL,
                                                       managedOverride: override)
        let result = EffectiveConfigGenerator.generate(request)
        expect(!result.isGenerated, "generator should stay explicit about unsupported generation")
        expect(result.provenance.baseConfigPath == baseURL.path, "provenance should record the base config path")
        expect(result.provenance.hasManagedOverride, "provenance should record managed override presence")
        expect(result.provenance.includesSmartXOverrides, "provenance should record SmartX override inclusion")

        switch result {
        case let .unsupported(reason, provenance):
            expect(reason.localizedCaseInsensitiveContains("yaml emitter"), "unsupported reason should explain the safe YAML emitter requirement")
            expect(reason.localizedCaseInsensitiveContains("lightgbm"), "unsupported reason should mention the managed LightGBM override scope")
            expect(provenance.reason == reason, "provenance should preserve the unsupported reason")
        case .generated:
            expect(false, "generator must not claim generated output without a safe YAML emitter")
        case let .failed(reason, provenance):
            expect(false, "generator should not fail here; got \(reason) with provenance \(provenance.baseConfigPath)")
        }

        print("effective_config_generator_smoke passed")
    }
}
