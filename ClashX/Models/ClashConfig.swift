//
//  ClashConfig.swift
//  ClashX
//
//  Created by CYC on 2018/7/30.
//  Copyright © 2018年 yichengchen. All rights reserved.
//
import CocoaLumberjack
import Foundation

enum ClashProxyMode: String, Codable {
    case rule
    case global
    case direct
    case script
}

extension ClashProxyMode {
    var name: String {
        switch self {
        case .rule: return NSLocalizedString("Rule", comment: "")
        case .global: return NSLocalizedString("Global", comment: "")
        case .direct: return NSLocalizedString("Direct", comment: "")
        case .script: return NSLocalizedString("Script", comment: "")
        }
    }
}

enum ClashLogLevel: String, Codable {
    case info
    #if PRO_VERSION
        case warning = "warn"
    #else
        case warning
    #endif
    case error
    case debug
    case silent
    case unknow = "unknown"

    func toDDLogLevel() -> DDLogLevel {
        switch self {
        case .info:
            return .info
        case .warning:
            return .warning
        case .error:
            return .error
        case .debug:
            return .debug
        case .silent:
            return .off
        case .unknow:
            return .error
        }
    }
}

class ClashConfig: Codable {
    struct Tun: Codable {
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

        private enum CodingKeys: String, CodingKey {
            case enable, device, stack
            case dnsHijack = "dns-hijack"
            case autoRoute = "auto-route"
            case autoDetectInterface = "auto-detect-interface"
            case strictRoute = "strict-route"
            case mtu
            case udpTimeout = "udp-timeout"
            case routeAddress = "route-address"
            case routeExcludeAddress = "route-exclude-address"
            case includeInterface = "include-interface"
            case excludeInterface = "exclude-interface"
        }
    }

    struct DNS: Codable {
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

        private enum CodingKeys: String, CodingKey {
            case enable
            case enhancedMode = "enhanced-mode"
            case fakeIPRange = "fake-ip-range"
            case fakeIPFilter = "fake-ip-filter"
            case fakeIPFilterMode = "fake-ip-filter-mode"
            case nameserver
            case fallback
            case directNameserver = "direct-nameserver"
            case respectRules = "respect-rules"
            case useHosts = "use-hosts"
            case useSystemHosts = "use-system-hosts"
            case preferH3 = "prefer-h3"
            case listen
        }
    }

    private var port: Int
    private var socksPort: Int
    var allowLan: Bool
    var mixedPort: Int
    var mode: ClashProxyMode
    var logLevel: ClashLogLevel
    var tun: Tun?
    var dns: DNS?

    var usedHttpPort: Int {
        if mixedPort > 0 {
            return mixedPort
        }
        return port
    }

    var usedSocksPort: Int {
        if mixedPort > 0 {
            return mixedPort
        }
        return socksPort
    }

    private enum CodingKeys: String, CodingKey {
        case port, socksPort = "socks-port", mixedPort = "mixed-port", allowLan = "allow-lan", mode, logLevel = "log-level", tun, dns
    }

    static func fromData(_ data: Data) -> ClashConfig? {
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(ClashConfig.self, from: data)
        } catch let err {
            Logger.log((err as NSError).description, level: .error)
            return nil
        }
    }

    func copy() -> ClashConfig? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        let copy = try? JSONDecoder().decode(ClashConfig.self, from: data)
        return copy
    }
}
