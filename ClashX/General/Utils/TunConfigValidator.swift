//
//  TunConfigValidator.swift
//  ClashX
//
//  Created by Codex on 2026/5/4.
//

import Darwin
import Foundation

struct TunConfigValidationInput {
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

struct TunValidationResult {
    let issues: [ConfigValidationIssue]

    var blockingErrors: [ConfigValidationIssue] {
        issues.filter { $0.severity == .blocking }
    }

    var warnings: [ConfigValidationIssue] {
        issues.filter { $0.severity == .warning }
    }

    var informational: [ConfigValidationIssue] {
        issues.filter { $0.severity == .info }
    }
}

enum TunConfigValidator {
    static func validate(_ tun: ClashConfig.Tun?) -> TunValidationResult {
        let input = tun.map {
            TunConfigValidationInput(enable: $0.enable,
                                     device: $0.device,
                                     stack: $0.stack,
                                     dnsHijack: $0.dnsHijack,
                                     autoRoute: $0.autoRoute,
                                     autoDetectInterface: $0.autoDetectInterface,
                                     strictRoute: $0.strictRoute,
                                     mtu: $0.mtu,
                                     udpTimeout: $0.udpTimeout,
                                     routeAddress: $0.routeAddress,
                                     routeExcludeAddress: $0.routeExcludeAddress,
                                     includeInterface: $0.includeInterface,
                                     excludeInterface: $0.excludeInterface)
        }
        return validate(input)
    }

    static func validate(_ tun: TunConfigValidationInput?) -> TunValidationResult {
        guard let tun else { return TunValidationResult(issues: []) }

        var issues = [ConfigValidationIssue]()

        if let include = tun.includeInterface, !include.isEmpty,
           let exclude = tun.excludeInterface, !exclude.isEmpty {
            issues.append(ConfigValidationIssue(severity: .warning,
                                                message: NSLocalizedString("Warning: include-interface and exclude-interface are both set. SmartX should treat that as expert-only until a structured editor exists.", comment: "")))
        }

        if tun.strictRoute == true {
            issues.append(ConfigValidationIssue(severity: .warning,
                                                message: NSLocalizedString("Warning: strict-route can break local macOS workflows and needs careful testing.", comment: "")))
        }

        if let mtu = tun.mtu, !(576 ... 9000).contains(mtu) {
            issues.append(ConfigValidationIssue(severity: .warning,
                                                message: String(format: NSLocalizedString("Warning: mtu=%d is outside the usual safe range SmartX expects.", comment: ""), mtu)))
        }

        if let udpTimeout = tun.udpTimeout, udpTimeout <= 0 {
            issues.append(ConfigValidationIssue(severity: .blocking,
                                                message: NSLocalizedString("Blocking: udp-timeout should be a positive integer before SmartX attempts a TUN update.", comment: "")))
        }

        let invalidCIDRs = invalidCIDRs(in: tun.routeAddress) + invalidCIDRs(in: tun.routeExcludeAddress)
        if !invalidCIDRs.isEmpty {
            issues.append(ConfigValidationIssue(severity: .blocking,
                                                message: NSLocalizedString("Blocking: one or more route-address or route-exclude-address entries do not parse as valid CIDR values.", comment: "")))
        }

        if let device = tun.device,
           !device.isEmpty,
           !device.lowercased().hasPrefix("utun") {
            issues.append(ConfigValidationIssue(severity: .info,
                                                message: NSLocalizedString("Heuristic note: macOS usually exposes utun-style TUN device names. Verify the configured device on the target host.", comment: "")))
        }

        return TunValidationResult(issues: issues)
    }

    private static func invalidCIDRs(in values: [String]?) -> [String] {
        (values ?? []).filter { !isValidCIDR($0) }
    }

    private static func isValidCIDR(_ rawValue: String) -> Bool {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "/")
        guard parts.count == 2, let prefix = Int(parts[1]) else { return false }

        let address = String(parts[0])
        if isValidIPv4(address) {
            return (0 ... 32).contains(prefix)
        }
        if isValidIPv6(address) {
            return (0 ... 128).contains(prefix)
        }
        return false
    }

    private static func isValidIPv4(_ rawValue: String) -> Bool {
        var storage = in_addr()
        return rawValue.withCString { inet_pton(AF_INET, $0, &storage) } == 1
    }

    private static func isValidIPv6(_ rawValue: String) -> Bool {
        var storage = in6_addr()
        return rawValue.withCString { inet_pton(AF_INET6, $0, &storage) } == 1
    }
}
