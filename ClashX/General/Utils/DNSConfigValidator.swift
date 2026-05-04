//
//  DNSConfigValidator.swift
//  ClashX
//
//  Created by Codex on 2026/5/4.
//

import Foundation

struct DNSConfigValidationInput {
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

struct DNSValidationResult {
    let issues: [ConfigValidationIssue]
}

enum DNSConfigValidator {
    static func validate(_ dns: ClashConfig.DNS?) -> DNSValidationResult {
        let input = dns.map {
            DNSConfigValidationInput(enable: $0.enable,
                                     enhancedMode: $0.enhancedMode,
                                     fakeIPRange: $0.fakeIPRange,
                                     fakeIPFilter: $0.fakeIPFilter,
                                     fakeIPFilterMode: $0.fakeIPFilterMode,
                                     nameserver: $0.nameserver,
                                     fallback: $0.fallback,
                                     directNameserver: $0.directNameserver,
                                     respectRules: $0.respectRules,
                                     useHosts: $0.useHosts,
                                     useSystemHosts: $0.useSystemHosts,
                                     preferH3: $0.preferH3,
                                     listen: $0.listen)
        }
        return validate(input)
    }

    static func validate(_ dns: DNSConfigValidationInput?) -> DNSValidationResult {
        guard let dns else { return DNSValidationResult(issues: []) }

        var issues = [ConfigValidationIssue]()
        if dns.respectRules == true, (dns.directNameserver ?? []).isEmpty, (dns.nameserver ?? []).isEmpty, (dns.fallback ?? []).isEmpty {
            issues.append(ConfigValidationIssue(severity: .warning,
                                                message: NSLocalizedString("Warning: respect-rules is enabled without an obvious configured resolver path.", comment: "")))
        }
        // fake-ip mode is a compatibility risk, but it should remain non-blocking here.
        if dns.enhancedMode?.caseInsensitiveCompare("fake-ip") == .orderedSame {
            issues.append(ConfigValidationIssue(severity: .warning,
                                                message: NSLocalizedString("Warning: fake-ip mode can break software that expects direct real-IP DNS answers.", comment: "")))
        }
        if dns.preferH3 == true, dns.respectRules == true {
            issues.append(ConfigValidationIssue(severity: .warning,
                                                message: NSLocalizedString("Warning: prefer-h3 with respect-rules may need extra resolver testing.", comment: "")))
        }
        return DNSValidationResult(issues: issues)
    }
}
