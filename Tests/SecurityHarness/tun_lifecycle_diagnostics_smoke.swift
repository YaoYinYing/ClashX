import Foundation

enum CoreEndpointAvailability {
    case available
    case unavailable
    case unauthorized
    case unsupported
    case unknown
    case degraded
}

final class ClashConfig {
    struct Tun {
        var enable: Bool
        var device: String?
        var stack: String?
        var dnsHijack: [String]?
        var autoRoute: Bool?
        var autoDetectInterface: Bool?
        var strictRoute: Bool?
        var mtu: Int?
        var udpTimeout: Int?
        var routeAddress: [String]?
        var routeExcludeAddress: [String]?
        var includeInterface: [String]?
        var excludeInterface: [String]?
    }

    struct DNS {
        var enable: Bool?
        var enhancedMode: String?
        var fakeIPRange: String?
        var fakeIPFilter: [String]?
        var fakeIPFilterMode: String?
        var nameserver: [String]?
        var fallback: [String]?
        var directNameserver: [String]?
        var respectRules: Bool?
        var useHosts: Bool?
        var useSystemHosts: Bool?
        var preferH3: Bool?
        var listen: String?
    }

    var tun: Tun?
    var dns: DNS?

    init(tun: Tun?, dns: DNS?) {
        self.tun = tun
        self.dns = dns
    }
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("tun_lifecycle_diagnostics_smoke failed: \(message)\n", stderr)
        exit(1)
    }
}

@main
enum TunLifecycleDiagnosticsSmokeMain {
    static func main() {
        let helperStatus = HelperStatus(trustState: .installedButUnverified,
                                        isPrivilegedHelperAvailable: true,
                                        diagnosticMessage: nil,
                                        recoverySuggestion: nil)
        let helperTunDescriptors = HelperCommandRegistry.reservedTunDescriptors()

        let embedded = TunPreflightPlanner.buildReport(config: nil,
                                                       isControllerRunning: true,
                                                       isUsingEmbeddedCore: true,
                                                       configPatchAvailability: .unknown,
                                                       helperStatus: helperStatus,
                                                       helperTunDescriptors: helperTunDescriptors)
        require(embedded.blockers.contains(.embeddedCoreUnsupported), "embedded core should block TUN")
        require(!embedded.canAttemptControllerPatch, "embedded core should not allow controller patch")
        require(embedded.verificationScope == .systemTunNotImplemented, "embedded core should not imply controller-only verification")

        let stopped = TunPreflightPlanner.buildReport(config: nil,
                                                      isControllerRunning: false,
                                                      isUsingEmbeddedCore: false,
                                                      configPatchAvailability: .unknown,
                                                      helperStatus: helperStatus,
                                                      helperTunDescriptors: helperTunDescriptors)
        require(stopped.blockers.contains(.controllerNotRunning), "stopped controller should block patch attempts")

        let missingTun = TunPreflightPlanner.buildReport(config: ClashConfig(tun: nil, dns: nil),
                                                         isControllerRunning: true,
                                                         isUsingEmbeddedCore: false,
                                                         configPatchAvailability: .available,
                                                         helperStatus: helperStatus,
                                                         helperTunDescriptors: helperTunDescriptors)
        require(missingTun.blockers.contains(.tunSectionMissing), "missing tun section should block")
        require(missingTun.helperTunCommandsReserved, "helper TUN contract should remain reserved only")
        require(missingTun.userMessage.contains("keeps TUN disabled"), "missing tun message drifted")

        let validConfig = ClashConfig(tun: ClashConfig.Tun(enable: false,
                                                           device: "utun9",
                                                           stack: nil,
                                                           dnsHijack: nil,
                                                           autoRoute: nil,
                                                           autoDetectInterface: nil,
                                                           strictRoute: false,
                                                           mtu: nil,
                                                           udpTimeout: 30,
                                                           routeAddress: ["10.0.0.0/8"],
                                                           routeExcludeAddress: nil,
                                                           includeInterface: nil,
                                                           excludeInterface: nil),
                                      dns: ClashConfig.DNS(enable: true,
                                                           enhancedMode: nil,
                                                           fakeIPRange: nil,
                                                           fakeIPFilter: nil,
                                                           fakeIPFilterMode: nil,
                                                           nameserver: ["1.1.1.1"],
                                                           fallback: nil,
                                                           directNameserver: nil,
                                                           respectRules: nil,
                                                           useHosts: nil,
                                                           useSystemHosts: nil,
                                                           preferH3: nil,
                                                           listen: nil))
        let ready = TunPreflightPlanner.buildReport(config: validConfig,
                                                    isControllerRunning: true,
                                                    isUsingEmbeddedCore: false,
                                                    configPatchAvailability: .available,
                                                    helperStatus: helperStatus,
                                                    helperTunDescriptors: helperTunDescriptors)
        require(ready.blockers == [], "valid external controller config should not block")
        require(ready.canAttemptControllerPatch, "valid external controller config should allow patch attempt")
        require(ready.verificationScope == .controllerConfigOnly, "successful preflight should only allow controller-config verification")
        require(ready.warnings.contains { $0.contains("System-level TUN verification is not implemented") }, "warnings should keep system verification boundary explicit")
        require(!ready.userMessage.contains("implemented"), "preflight text must not claim helper-backed TUN is implemented")

        let encodedPreflight = try! JSONEncoder().encode(ready)
        let decodedPreflight = try! JSONDecoder().decode(TunPreflightReport.self, from: encodedPreflight)
        require(decodedPreflight.verificationScope == .controllerConfigOnly, "preflight codable round trip changed verification scope")

        let verification = TunPreflightPlanner.verificationReport(expectedEnabled: true,
                                                                  controllerReportedEnabled: true,
                                                                  didFailToReload: false,
                                                                  preflightReport: ready)
        require(verification.outcome == .controllerStateMatches, "matching controller state should verify")
        require(verification.verificationScope == .controllerConfigOnly, "verification scope should stay controller-config only")
        require(verification.message.contains("System-level TUN verification is not implemented"), "verification message should keep runtime boundary explicit")

        let encodedVerification = try! JSONEncoder().encode(verification)
        let decodedVerification = try! JSONDecoder().decode(TunLifecycleVerificationReport.self, from: encodedVerification)
        require(decodedVerification.outcome == .controllerStateMatches, "verification codable round trip changed outcome")

        print("tun_lifecycle_diagnostics_smoke passed")
    }
}
