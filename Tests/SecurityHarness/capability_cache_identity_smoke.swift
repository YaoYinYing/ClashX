import Foundation

enum ControllerEndpointResult {
    case success
    case unsupported
    case unauthorized(String)
    case failed(String)
}

enum ControllerJSONResult {
    case success(Any)
    case unsupported
    case unauthorized(String)
    case failed(String)
}

struct CoreCapabilitySnapshot {
    let controllerIdentity: String
    let mode: String
    let running: Bool
    let coreVersion: String?
    let statuses: [CoreCapability: CoreCapabilityStatus]
    let probedAt: Date
}

final class ConfigManager {
    static let shared = ConfigManager()

    var isRunning = true
    var overrideApiURL: URL?
    var apiPort = "9443"
    var overrideSecret: String?
    var apiSecret = ""
}

enum Settings {
    static var isUsingEmbeddedCore = false
}

@inline(__always)
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("capability_cache_identity_smoke failed: \(message)\n", stderr)
        exit(1)
    }
}

func runCapabilityIdentitySmoke() {
    ConfigManager.shared.isRunning = true
    ConfigManager.shared.overrideApiURL = URL(string: "https://user:password@example.com:9443/base?token=secret#frag")
    ConfigManager.shared.overrideSecret = "super-secret"
    ConfigManager.shared.apiSecret = ""
    Settings.isUsingEmbeddedCore = false

    let identity = CapabilityCache.shared.currentControllerIdentityForTesting()
    expect(!identity.contains("super-secret"), "raw controller secret leaked into identity")
    expect(!identity.contains("user:password"), "userinfo leaked into identity")
    expect(!identity.contains("token=secret"), "query leaked into identity")
    expect(identity.contains("https://example.com:9443/base"), "sanitized controller base missing")
    expect(identity.contains("secret-fnv1a64-"), "hashed secret marker missing")

    ConfigManager.shared.overrideSecret = "alpha-secret"
    CapabilityCache.shared.reset()
    let overrideIdentityA = CapabilityCache.shared.currentControllerIdentityForTesting()
    ConfigManager.shared.overrideSecret = "beta-secret"
    CapabilityCache.shared.reset()
    let overrideIdentityB = CapabilityCache.shared.currentControllerIdentityForTesting()
    expect(overrideIdentityA != overrideIdentityB, "different override secrets should change identity")
    expect(!overrideIdentityA.contains("alpha-secret"), "override alpha secret leaked into identity")
    expect(!overrideIdentityB.contains("beta-secret"), "override beta secret leaked into identity")

    ConfigManager.shared.overrideSecret = nil
    ConfigManager.shared.apiSecret = "api-alpha"
    CapabilityCache.shared.reset()
    let apiIdentityA = CapabilityCache.shared.currentControllerIdentityForTesting()
    ConfigManager.shared.apiSecret = "api-beta"
    CapabilityCache.shared.reset()
    let apiIdentityB = CapabilityCache.shared.currentControllerIdentityForTesting()
    expect(apiIdentityA != apiIdentityB, "different api secrets should change identity")
    expect(!apiIdentityA.contains("api-alpha"), "api alpha secret leaked into identity")
    expect(!apiIdentityB.contains("api-beta"), "api beta secret leaked into identity")

    ConfigManager.shared.overrideSecret = nil
    ConfigManager.shared.apiSecret = ""
    CapabilityCache.shared.reset()
    let noSecretIdentity = CapabilityCache.shared.currentControllerIdentityForTesting()
    expect(noSecretIdentity.contains("no-secret"), "empty secret should stay no-secret")
}

@main
enum CapabilityCacheIdentitySmokeMain {
    static func main() {
        runCapabilityIdentitySmoke()
        print("capability_cache_identity_smoke passed")
    }
}
