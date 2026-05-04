//
//  DiagnosticsProviderFormatter.swift
//  ClashX
//
//  Created by Codex on 2026/5/4.
//

import Foundation
import SwiftyJSON

enum DiagnosticsProviderFormatter {
    static func format(proxyResult: ControllerJSONResult?,
                       ruleResult: ControllerJSONResult?,
                       existingHTTPProxyProviderNames: [String] = []) -> (text: String, httpProxyProviderNames: [String]) {
        var providerNames = existingHTTPProxyProviderNames
        let proxySection = providerSection(title: "Proxy Providers",
                                           result: proxyResult,
                                           capability: .proxyProviders,
                                           httpProxyProviderNames: &providerNames)
        let ruleSection = providerSection(title: "Rule Providers",
                                          result: ruleResult,
                                          capability: .ruleProviders,
                                          httpProxyProviderNames: &providerNames)
        let historySection = ProviderHealthHistoryManager.summary(limit: 5)
        return ([proxySection, ruleSection, historySection].joined(separator: "\n\n"), providerNames)
    }

    private static func providerSection(title: String,
                                        result: ControllerJSONResult?,
                                        capability: CoreCapability,
                                        httpProxyProviderNames: inout [String]) -> String {
        var lines = [title]
        let resolvedResult = result ?? .failed(NSLocalizedString("No response.", comment: ""))

        switch resolvedResult {
        case let .success(json):
            let providers = json["providers"].dictionaryValue
            let providerNames = providers.keys.sorted()
            if capability == .proxyProviders {
                httpProxyProviderNames = providerNames.filter {
                    providers[$0]?["vehicleType"].stringValue.caseInsensitiveCompare("http") == .orderedSame
                }
            }

            lines.append("Count: \(providerNames.count)")
            if providerNames.isEmpty {
                lines.append("None reported.")
            } else {
                for name in providerNames {
                    let provider = providers[name]
                    let vehicleType = provider?["vehicleType"].stringValue ?? "unknown"
                    let providerType = provider?["type"].stringValue ?? "unknown"
                    let proxyCount = provider?["proxies"].arrayValue.count ?? 0
                    lines.append("- \(name) [\(providerType)/\(vehicleType)] proxies=\(proxyCount)")
                }
            }
        case .unsupported:
            lines.append("Unsupported by the active controller.")
        case let .unauthorized(message):
            lines.append("Unauthorized: \(message)")
        case let .failed(message):
            lines.append("Failed: \(message)")
        }

        if let capabilityMessage = CapabilityCache.shared.message(for: capability),
           !capabilityMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("Capability: \(capabilityMessage)")
        }

        return lines.joined(separator: "\n")
    }
}
