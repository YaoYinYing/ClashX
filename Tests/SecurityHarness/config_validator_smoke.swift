import Foundation

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
}

@inline(__always)
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("config_validator_smoke failed: \(message)\n", stderr)
        exit(1)
    }
}

@main
enum ConfigValidatorSmokeMain {
    static func main() {
        let nilDNSResult = DNSConfigValidator.validate(nil as DNSConfigValidationInput?)
        expect(nilDNSResult.issues.isEmpty, "nil DNS input should not produce issues")

        let validIPv4 = TunConfigValidator.validate(TunConfigValidationInput(enable: true,
                                                                             device: "utun7",
                                                                             stack: nil,
                                                                             dnsHijack: nil,
                                                                             autoRoute: nil,
                                                                             autoDetectInterface: nil,
                                                                             strictRoute: false,
                                                                             mtu: nil,
                                                                             udpTimeout: 30,
                                                                             routeAddress: ["10.0.0.0/8"],
                                                                             routeExcludeAddress: ["192.168.0.0/16"],
                                                                             includeInterface: nil,
                                                                             excludeInterface: nil))
        expect(validIPv4.blockingErrors.isEmpty, "valid IPv4 CIDRs should not block")

        let validIPv6 = TunConfigValidator.validate(TunConfigValidationInput(enable: true,
                                                                             device: "utun8",
                                                                             stack: nil,
                                                                             dnsHijack: nil,
                                                                             autoRoute: nil,
                                                                             autoDetectInterface: nil,
                                                                             strictRoute: false,
                                                                             mtu: nil,
                                                                             udpTimeout: 30,
                                                                             routeAddress: ["2001:db8::/64"],
                                                                             routeExcludeAddress: nil,
                                                                             includeInterface: nil,
                                                                             excludeInterface: nil))
        expect(validIPv6.blockingErrors.isEmpty, "valid IPv6 CIDRs should not block")

        let tunResult = TunConfigValidator.validate(TunConfigValidationInput(enable: true,
                                                                             device: "tun0",
                                                                             stack: nil,
                                                                             dnsHijack: nil,
                                                                             autoRoute: true,
                                                                             autoDetectInterface: nil,
                                                                             strictRoute: true,
                                                                             mtu: 128,
                                                                             udpTimeout: 0,
                                                                             routeAddress: ["10.0.0.0/8", "bad-cidr"],
                                                                             routeExcludeAddress: nil,
                                                                             includeInterface: ["en0"],
                                                                             excludeInterface: ["en1"]))
        expect(tunResult.blockingErrors.count == 2, "TUN validation should surface blocking UDP timeout and CIDR issues")
        expect(tunResult.warnings.count >= 2, "TUN validation should surface warning-grade issues")
        expect(tunResult.informational.contains { $0.message.contains("Heuristic note") }, "TUN validation should mark non-utun devices as heuristic info")
        expect(!tunResult.warnings.contains { $0.message.contains("Heuristic note") }, "non-utun device note should stay informational")
        expect(tunResult.warnings.contains { $0.message.contains("strict-route") }, "strict-route should remain warning-grade")

        let invalidPrefixResult = TunConfigValidator.validate(TunConfigValidationInput(enable: true,
                                                                                       device: "utun1",
                                                                                       stack: nil,
                                                                                       dnsHijack: nil,
                                                                                       autoRoute: nil,
                                                                                       autoDetectInterface: nil,
                                                                                       strictRoute: false,
                                                                                       mtu: nil,
                                                                                       udpTimeout: 30,
                                                                                       routeAddress: ["10.0.0.0/99"],
                                                                                       routeExcludeAddress: nil,
                                                                                       includeInterface: nil,
                                                                                       excludeInterface: nil))
        expect(invalidPrefixResult.blockingErrors.count == 1, "invalid CIDR prefix should block")

        let dnsResult = DNSConfigValidator.validate(DNSConfigValidationInput(enable: true,
                                                                             enhancedMode: "fake-ip",
                                                                             fakeIPRange: nil,
                                                                             fakeIPFilter: nil,
                                                                             fakeIPFilterMode: nil,
                                                                             nameserver: [],
                                                                             fallback: [],
                                                                             directNameserver: [],
                                                                             respectRules: true,
                                                                             useHosts: nil,
                                                                             useSystemHosts: nil,
                                                                             preferH3: true,
                                                                             listen: nil))
        expect(dnsResult.issues.count == 3, "DNS validation should surface the expected warning set")
        expect(dnsResult.issues.allSatisfy { $0.severity != .blocking }, "DNS validation issues in this smoke case should remain non-blocking")

        print("config_validator_smoke passed")
    }
}
