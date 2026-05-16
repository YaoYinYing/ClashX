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
        fputs("tun_runtime_diagnostics_smoke failed: \(message)\n", stderr)
        exit(1)
    }
}

@main
enum TunRuntimeDiagnosticsSmokeMain {
    static func main() {
        let noTunEvidence = TunRuntimeInterfaceProbe.classify(interfaceNames: ["lo0", "en0"])
        require(noTunEvidence.evidenceState == .noTunLikeInterface, "plain interfaces should not look TUN-like")

        let utunEvidence = TunRuntimeInterfaceProbe.classify(interfaceNames: ["lo0", "en0", "utun4"])
        require(utunEvidence.evidenceState == .tunLikeInterfacePresent, "utun interface should count as tun-like evidence")
        require(utunEvidence.tunLikeInterfaceNames == ["utun4"], "utun evidence should keep only tun-like names")

        let tunEvidence = TunRuntimeInterfaceProbe.classify(interfaceNames: ["tun0"])
        require(tunEvidence.evidenceState == .tunLikeInterfacePresent, "tun prefix should count as tun-like evidence")

        let encodedEvidence = try! JSONEncoder().encode(utunEvidence)
        let decodedEvidence = try! JSONDecoder().decode(TunRuntimeInterfaceEvidence.self, from: encodedEvidence)
        require(decodedEvidence.evidenceState == .tunLikeInterfacePresent, "interface evidence codable round trip changed state")

        let preflight = TunPreflightReport(runtimeMode: .externalController,
                                           canAttemptControllerPatch: true,
                                           blockers: [],
                                           warnings: [],
                                           helperTrustState: .installedButUnverified,
                                           helperTunCommandsReserved: true,
                                           verificationScope: .controllerConfigOnly,
                                           userMessage: "guarded external-controller path",
                                           recoverySuggestion: "controller path only")
        let routeEvidence = TunRuntimeRouteProbe.classify(defaultRouteInterface: "utun4",
                                                          observedRouteInterfaces: ["utun4"],
                                                          tunLikeInterfaceNames: ["utun4"])
        let dnsEvidence = TunRuntimeDNSProbe.classify(resolverInterfaceNames: ["utun4"],
                                                      resolverServerCount: 1,
                                                      hasScopedResolvers: true)

        let runtimeEnabled = TunPreflightPlanner.runtimeVerificationReport(expectedEnabled: true,
                                                                           controllerReportedEnabled: true,
                                                                           didFailToReload: false,
                                                                           preflightReport: preflight,
                                                                           interfaceEvidence: utunEvidence,
                                                                           routeEvidence: routeEvidence,
                                                                           dnsEvidence: dnsEvidence)
        require(runtimeEnabled.interfaceEvidence.evidenceState == .tunLikeInterfacePresent, "runtime report should keep tun-like evidence")
        require(runtimeEnabled.message.contains("Controller config matches tun.enable=true"), "enabled runtime report should mention config match")
        require(runtimeEnabled.message.contains("utun4"), "enabled runtime report should mention tun-like interface name")
        require(!runtimeEnabled.message.contains("full runtime verification"), "runtime report must not claim full verification")

        let passiveEnabled = TunPreflightPlanner.passiveRuntimeSnapshotReport(controllerReportedEnabled: true,
                                                                              preflightReport: preflight,
                                                                              interfaceEvidence: utunEvidence,
                                                                              routeEvidence: routeEvidence,
                                                                              dnsEvidence: dnsEvidence)
        require(passiveEnabled.message.contains("passive diagnostics snapshot"), "passive report should declare passive snapshot scope")
        require(passiveEnabled.message.contains("not a post-toggle verification"), "passive report should reject post-toggle verification wording")
        require(passiveEnabled.message.contains("may be stale"), "passive report should warn that cached/current state may be stale")
        require(!passiveEnabled.message.contains("Controller config matches"), "passive report must not synthesize controller match wording")
        require(!passiveEnabled.message.localizedCaseInsensitiveContains("verified"), "passive report must not claim verified state")
        require(!passiveEnabled.message.localizedCaseInsensitiveContains("succeeded"), "passive report must not claim success")
        require(passiveEnabled.message.contains("read-only evidence only"), "passive report should describe read-only evidence")
        require(passiveEnabled.isRuntimeConsistentWithController == nil, "passive report must not compute runtime consistency")
        require(passiveEnabled.interfaceEvidence.evidenceState == utunEvidence.evidenceState, "passive report should preserve interface evidence")
        require(passiveEnabled.routeEvidence.evidenceState == routeEvidence.evidenceState, "passive report should preserve route evidence")
        require(passiveEnabled.dnsEvidence.evidenceState == dnsEvidence.evidenceState, "passive report should preserve DNS evidence")
        require(passiveEnabled.verificationLevels.contains(.packetFlowVerificationNotImplemented), "passive report should keep packet-flow boundary explicit")
        require(!passiveEnabled.message.contains("helper-backed TUN is implemented"), "passive report must not claim helper-backed TUN support")
        require(!passiveEnabled.message.contains("embedded-core TUN is supported"), "passive report must not claim embedded-core TUN support")
        require(passiveEnabled.recoverySuggestion.contains("does not verify a toggle request"), "passive report should reject post-toggle semantics")

        let runtimeNoEvidence = TunPreflightPlanner.runtimeVerificationReport(expectedEnabled: true,
                                                                              controllerReportedEnabled: true,
                                                                              didFailToReload: false,
                                                                              preflightReport: preflight,
                                                                              interfaceEvidence: noTunEvidence,
                                                                              routeEvidence: TunRuntimeRouteProbe.classify(defaultRouteInterface: nil,
                                                                                                                           observedRouteInterfaces: ["en0"],
                                                                                                                           tunLikeInterfaceNames: ["utun4"]),
                                                                              dnsEvidence: TunRuntimeDNSProbe.classify(resolverInterfaceNames: [],
                                                                                                                       resolverServerCount: nil,
                                                                                                                       hasScopedResolvers: nil))
        require(runtimeNoEvidence.interfaceEvidence.evidenceState == .noTunLikeInterface, "runtime report should keep no-interface evidence")
        require(runtimeNoEvidence.message.contains("does not prove failure"), "no-interface runtime report should stay conservative")
        require(runtimeNoEvidence.verificationLevels.contains(.routeVerificationNotImplemented), "runtime report should keep route verification boundary explicit")
        require(runtimeNoEvidence.verificationLevels.contains(.dnsRuntimeVerificationNotImplemented), "runtime report should keep DNS verification boundary explicit")
        require(runtimeNoEvidence.verificationLevels.contains(.packetFlowVerificationNotImplemented), "runtime report should keep packet-flow boundary explicit")
        require(!runtimeNoEvidence.message.contains("helper-backed TUN is implemented"), "runtime report must not claim helper-backed TUN support")

        let encodedRuntime = try! JSONEncoder().encode(runtimeNoEvidence)
        let decodedRuntime = try! JSONDecoder().decode(TunRuntimeVerificationReport.self, from: encodedRuntime)
        require(decodedRuntime.interfaceEvidence.evidenceState == .noTunLikeInterface, "runtime report codable round trip changed evidence state")

        print("tun_runtime_diagnostics_smoke passed")
    }
}
