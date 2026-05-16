import Foundation

struct ProfileArtifactMetadata {
    let selectedProfileName: String
    let selectedProfileKind: String
    let sourceConfigPath: String
    let sourceRemoteURL: String?
    let generatedAt: Date
    let controllerMode: String
    let generationMode: String
    let requestedSmartXOverrides: Bool
    let emittedSmartXOverrides: Bool
    let includesProfileMerge: Bool
    let includesRuntimeOverrides: Bool
}

enum ProfileArtifactManager {
    static func loadMetadata(at _: URL) -> ProfileArtifactMetadata? {
        ProfileArtifactMetadata(selectedProfileName: "Sample",
                                selectedProfileKind: "remote",
                                sourceConfigPath: NSHomeDirectory() + "/configs/source.yaml",
                                sourceRemoteURL: "https://example.com/sub?token=top-secret",
                                generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
                                controllerMode: "external",
                                generationMode: "source-copy",
                                requestedSmartXOverrides: false,
                                emittedSmartXOverrides: false,
                                includesProfileMerge: false,
                                includesRuntimeOverrides: false)
    }
}

enum Paths {
    static let smartXManagedOverrideURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("smartx-managed.json", isDirectory: false)
}

@inline(__always)
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("diagnostics_artifact_formatter_smoke failed: \(message)\n", stderr)
        exit(1)
    }
}

@main
enum DiagnosticsArtifactFormatterSmokeMain {
    static func main() {
        let baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("smartx-diagnostics-artifact-smoke-\(UUID().uuidString)", isDirectory: true)
        let configURL = baseURL.appendingPathComponent("artifact.yaml", isDirectory: false)
        let metadataURL = baseURL.appendingPathComponent("artifact.json", isDirectory: false)

        do {
            try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
            let configText = """
            proxies:
              - { name: leak-ss, type: ss, server: example.com, password: secret-password, uri: ss://YWJjZA==@example.com:443 }
              - { name: leak-vless, type: vless, server: example.com, uri: vless://user@example.com:443?token=secret-value }
            profile:
              url: https://example.com/sub?token=secret-value
            external-controller-secret: abcdef
            Authorization: Bearer secret-token
            path: \(NSHomeDirectory())/Library/Application Support/SmartX/config.yaml
            """
            try configText.write(to: configURL, atomically: true, encoding: .utf8)

            let output = DiagnosticsArtifactFormatter.formatArtifactPreview(title: "Artifact Preview",
                                                                            configURL: configURL,
                                                                            metadataURL: metadataURL)

            expect(output.contains("<redacted-proxy-uri>"), "artifact preview should redact proxy URIs")
            expect(output.contains("https://example.com/sub?token="), "artifact preview should keep a sanitized token-bearing URL shape")
            expect(output.contains("external-controller-secret: <redacted>"), "artifact preview should redact controller secrets")
            expect(output.lowercased().contains("authorization: <redacted>"), "artifact preview should redact authorization values")
            expect(output.contains("~"), "artifact preview should redact home directory paths")
            expect(!output.contains("ss://YWJjZA=="), "artifact preview should not expose raw ss:// URIs")
            expect(!output.contains("trojan://"), "artifact preview should not expose raw trojan:// URIs")
            expect(!output.contains("secret-value"), "artifact preview should not expose raw token values")
            expect(!output.contains("secret-token"), "artifact preview should not expose raw authorization tokens")
            expect(!output.contains(NSHomeDirectory()), "artifact preview should not expose the full home directory")

            print("diagnostics_artifact_formatter_smoke passed")
        } catch {
            fputs("diagnostics_artifact_formatter_smoke failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
