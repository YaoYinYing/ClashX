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
        fputs("tun_route_dns_runtime_smoke failed: \(message)\n", stderr)
        exit(1)
    }
}

@main
enum TunRouteDNSRuntimeSmokeMain {
    static func main() {
        let routeInconclusive = TunRuntimeRouteProbe.classify(defaultRouteInterface: nil,
                                                              observedRouteInterfaces: [],
                                                              tunLikeInterfaceNames: [])
        require(routeInconclusive.evidenceState == .inconclusive, "empty route data should be inconclusive")

        let routeNoTun = TunRuntimeRouteProbe.classify(defaultRouteInterface: nil,
                                                       observedRouteInterfaces: ["en0"],
                                                       tunLikeInterfaceNames: ["utun4"])
        require(routeNoTun.evidenceState == .noTunLikeRouteEvidence, "non-tun route interfaces should stay negative evidence")

        let routeObservedTun = TunRuntimeRouteProbe.classify(defaultRouteInterface: nil,
                                                             observedRouteInterfaces: ["en0", "utun4"],
                                                             tunLikeInterfaceNames: ["utun4"])
        require(routeObservedTun.evidenceState == .tunLikeRouteEvidencePresent, "observed tun route should count as route evidence")

        let routeDefaultTun = TunRuntimeRouteProbe.classify(defaultRouteInterface: "utun4",
                                                            observedRouteInterfaces: ["en0"],
                                                            tunLikeInterfaceNames: [])
        require(routeDefaultTun.evidenceState == .tunLikeRouteEvidencePresent, "tun default route should count as route evidence")
        require(!routeDefaultTun.message.contains("packet-flow verification succeeded"), "route evidence must not claim packet-flow verification")

        let dnsInconclusive = TunRuntimeDNSProbe.classify(resolverInterfaceNames: [],
                                                          resolverServerCount: nil,
                                                          hasScopedResolvers: nil)
        require(dnsInconclusive.evidenceState == .inconclusive, "empty DNS data should be inconclusive")

        let dnsScoped = TunRuntimeDNSProbe.classify(resolverInterfaceNames: ["utun4"],
                                                    resolverServerCount: nil,
                                                    hasScopedResolvers: true)
        require(dnsScoped.evidenceState == .dnsRuntimeEvidencePresent, "scoped resolver interface should count as DNS runtime evidence")

        let dnsGeneric = TunRuntimeDNSProbe.classify(resolverInterfaceNames: [],
                                                     resolverServerCount: 2,
                                                     hasScopedResolvers: false)
        require(dnsGeneric.evidenceState == .dnsRuntimeEvidencePresent, "generic DNS server count should count as DNS evidence")
        require(dnsGeneric.message.contains("not TUN DNS proof"), "generic DNS evidence must stay conservative")

        let dnsNone = TunRuntimeDNSProbe.classify(resolverInterfaceNames: [],
                                                  resolverServerCount: 0,
                                                  hasScopedResolvers: false)
        require(dnsNone.evidenceState == .noDNSRuntimeEvidence, "zero DNS server count should be negative evidence")
        require(!dnsNone.message.contains("DNS hijack verified"), "DNS evidence must not claim DNS hijack verification")

        let preflight = TunPreflightReport(runtimeMode: .externalController,
                                           canAttemptControllerPatch: true,
                                           blockers: [],
                                           warnings: [],
                                           helperTrustState: .installedButUnverified,
                                           helperTunCommandsReserved: true,
                                           verificationScope: .controllerConfigOnly,
                                           userMessage: "guarded external-controller path",
                                           recoverySuggestion: "controller path only")

        let interfacePresent = TunRuntimeInterfaceProbe.classify(interfaceNames: ["lo0", "utun4"])
        let runtimePositive = TunPreflightPlanner.runtimeVerificationReport(expectedEnabled: true,
                                                                            controllerReportedEnabled: true,
                                                                            didFailToReload: false,
                                                                            preflightReport: preflight,
                                                                            interfaceEvidence: interfacePresent,
                                                                            routeEvidence: routeObservedTun,
                                                                            dnsEvidence: dnsScoped)
        require(runtimePositive.message.contains("Tun-like interface evidence is present"), "runtime report should mention interface evidence")
        require(runtimePositive.message.contains("route"), "runtime report should mention route evidence")
        require(runtimePositive.message.contains("DNS"), "runtime report should mention DNS evidence")
        require(!runtimePositive.message.contains("full runtime verification"), "runtime report must not claim full runtime verification")

        let interfaceAbsent = TunRuntimeInterfaceProbe.classify(interfaceNames: ["lo0", "en0"])
        let runtimeNegative = TunPreflightPlanner.runtimeVerificationReport(expectedEnabled: true,
                                                                            controllerReportedEnabled: true,
                                                                            didFailToReload: false,
                                                                            preflightReport: preflight,
                                                                            interfaceEvidence: interfaceAbsent,
                                                                            routeEvidence: routeNoTun,
                                                                            dnsEvidence: dnsInconclusive)
        require(runtimeNegative.message.contains("does not prove failure"), "no interface and route evidence should stay conservative")
        require(runtimeNegative.verificationLevels.contains(.controllerConfigOnly), "runtime levels should keep controller config verification")
        require(runtimeNegative.verificationLevels.contains(.interfacePresenceOnly), "runtime levels should keep interface evidence level")
        require(runtimeNegative.verificationLevels.contains(.routeVerificationNotImplemented), "runtime levels should keep route boundary")
        require(runtimeNegative.verificationLevels.contains(.dnsRuntimeVerificationNotImplemented), "runtime levels should keep DNS boundary")
        require(runtimeNegative.verificationLevels.contains(.packetFlowVerificationNotImplemented), "runtime levels should keep packet-flow boundary")
        require(!runtimeNegative.message.contains("helper-backed TUN is implemented"), "runtime report must not claim helper-backed TUN support")

        let encodedRoute = try! JSONEncoder().encode(routeObservedTun)
        let decodedRoute = try! JSONDecoder().decode(TunRouteRuntimeEvidence.self, from: encodedRoute)
        require(decodedRoute.evidenceState == .tunLikeRouteEvidencePresent, "route evidence codable round trip changed state")

        let encodedDNS = try! JSONEncoder().encode(dnsScoped)
        let decodedDNS = try! JSONDecoder().decode(TunDNSRuntimeEvidence.self, from: encodedDNS)
        require(decodedDNS.evidenceState == .dnsRuntimeEvidencePresent, "DNS evidence codable round trip changed state")

        print("tun_route_dns_runtime_smoke passed")
    }
}
