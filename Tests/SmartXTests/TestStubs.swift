//
//  TestStubs.swift
//  SmartXTests
//
//  ponytail: stubs for types defined in CocoaPods-dependent production files.
//  Same pattern as Tests/SecurityHarness smoke harnesses. Each stub provides
//  exactly the fields/methods that pure-logic production sources reference.
//  Ceiling: stubs are NOT the real types. Upgrade path: remove when the
//  project modularizes the API boundary.

import Foundation

// MARK: - ConfigManager stub (real file imports RxSwift)

final class ConfigManager {
    static let shared = ConfigManager()

    var isRunning = true
    var overrideApiURL: URL?
    var apiPort = "9090"
    var apiUrl: String {
        overrideApiURL?.absoluteString ?? "http://127.0.0.1:\(apiPort)"
    }
}

// MARK: - ClashConfig stubs (real file imports SwiftyJSON)

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
