import Foundation

enum LoggerLevel {
    case warning
}

enum Logger {
    static func log(_ message: String, level: LoggerLevel) {
        _ = (message, level)
    }
}

enum Settings {
    static var isUsingEmbeddedCore = true
}

struct ConfigProfileSmokeDescriptor {
    let name: String
    let kind: ConfigProfileSmokeKind
    let remoteURL: String?
}

enum ConfigProfileSmokeKind: String {
    case local
    case remote
}

enum ConfigManager {
    static func profileDescriptor(name: String) -> ConfigProfileSmokeDescriptor {
        ConfigProfileSmokeDescriptor(name: name, kind: .local, remoteURL: nil)
    }
}

enum Paths {
    static let smartXArtifactsDirectoryURL = FileManager.default.temporaryDirectory
    static let successfulReloadArtifactURL = FileManager.default.temporaryDirectory.appendingPathComponent("artifact.yaml")
    static let lastKnownGoodConfigURL = FileManager.default.temporaryDirectory.appendingPathComponent("last-known-good.yaml")
    static let successfulReloadMetadataURL = FileManager.default.temporaryDirectory.appendingPathComponent("artifact.json")
    static let lastKnownGoodMetadataURL = FileManager.default.temporaryDirectory.appendingPathComponent("last-known-good.json")
}

@inline(__always)
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("profile_artifact_metadata_smoke failed: \(message)\n", stderr)
        exit(1)
    }
}

@main
enum ProfileArtifactMetadataSmokeMain {
    static func main() {
        do {
            let metadata = ProfileArtifactMetadata(selectedProfileName: "Sample",
                                                   selectedProfileKind: "local",
                                                   sourceConfigPath: "/tmp/source.yaml",
                                                   sourceRemoteURL: nil,
                                                   generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
                                                   controllerMode: "embedded",
                                                   generationMode: "source-copy",
                                                   includesSmartXOverrides: false,
                                                   includesProfileMerge: false,
                                                   includesRuntimeOverrides: false)

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(metadata)

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let decoded = try decoder.decode(ProfileArtifactMetadata.self, from: data)

            expect(decoded.selectedProfileName == metadata.selectedProfileName, "profile name should round-trip")
            expect(decoded.generationMode == "source-copy", "generation mode should remain honest for source-copy artifacts")
            expect(decoded.includesSmartXOverrides == false, "override flag should remain false for source-copy artifacts")

            print("profile_artifact_metadata_smoke passed")
        } catch {
            fputs("profile_artifact_metadata_smoke failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
