//
//  TunRuntimeDNSProbe.swift
//  ClashX
//
//  Created by Codex on 2026/5/16.
//

import Foundation
import SystemConfiguration

enum TunRuntimeDNSProbe {
    static func currentEvidence() -> TunDNSRuntimeEvidence {
        guard let store = SCDynamicStoreCreate(nil, "ClashX.TunRuntimeDNSProbe" as CFString, nil, nil) else {
            return TunDNSRuntimeEvidence(evidenceState: .unavailable,
                                         resolverInterfaceNames: [],
                                         resolverServerCount: nil,
                                         hasScopedResolvers: nil,
                                         message: "Read-only DNS runtime evidence is unavailable on this host. DNS runtime evidence is read-only and is not DNS hijack proof.")
        }

        let globalDNSKey = SCDynamicStoreKeyCreateNetworkGlobalEntity(nil, kSCDynamicStoreDomainState, kSCEntNetDNS)
        let globalDNS = SCDynamicStoreCopyValue(store, globalDNSKey) as? [String: Any]
        let resolverServerCount = (globalDNS?[kSCPropNetDNSServerAddresses as String] as? [String])?.count

        let dnsKeys = (SCDynamicStoreCopyKeyList(store, "State:/Network/Service/.*/DNS" as CFString) as? [String]) ?? []
        let resolverInterfaceNames = dnsKeys.compactMap { interfaceName(forDNSKey: $0, store: store) }
        let hasScopedResolvers = dnsKeys.isEmpty ? nil : !resolverInterfaceNames.isEmpty

        return classify(resolverInterfaceNames: Array(Set(resolverInterfaceNames)).sorted(),
                        resolverServerCount: resolverServerCount,
                        hasScopedResolvers: hasScopedResolvers)
    }

    static func classify(resolverInterfaceNames: [String],
                         resolverServerCount: Int?,
                         hasScopedResolvers: Bool?) -> TunDNSRuntimeEvidence {
        let names = Array(Set(resolverInterfaceNames)).sorted()

        if names.isEmpty, resolverServerCount == nil, hasScopedResolvers == nil {
            return TunDNSRuntimeEvidence(evidenceState: .inconclusive,
                                         resolverInterfaceNames: [],
                                         resolverServerCount: nil,
                                         hasScopedResolvers: nil,
                                         message: "No DNS runtime data was observed, so DNS runtime evidence is inconclusive. DNS runtime evidence is read-only and is not DNS hijack proof.")
        }

        if resolverServerCount == 0 {
            return TunDNSRuntimeEvidence(evidenceState: .noDNSRuntimeEvidence,
                                         resolverInterfaceNames: names,
                                         resolverServerCount: resolverServerCount,
                                         hasScopedResolvers: hasScopedResolvers,
                                         message: "DNS runtime data reported zero resolver servers. This is not DNS hijack proof and may still require manual inspection.")
        }

        if !names.isEmpty || hasScopedResolvers == true {
            let summary = names.isEmpty ? "scoped resolver data is present" : "resolver interfaces: \(names.joined(separator: ", "))"
            return TunDNSRuntimeEvidence(evidenceState: .dnsRuntimeEvidencePresent,
                                         resolverInterfaceNames: names,
                                         resolverServerCount: resolverServerCount,
                                         hasScopedResolvers: hasScopedResolvers,
                                         message: "Read-only DNS runtime evidence is present (\(summary)). This is not DNS hijack proof.")
        }

        if let resolverServerCount, resolverServerCount > 0 {
            return TunDNSRuntimeEvidence(evidenceState: .dnsRuntimeEvidencePresent,
                                         resolverInterfaceNames: names,
                                         resolverServerCount: resolverServerCount,
                                         hasScopedResolvers: hasScopedResolvers,
                                         message: "Generic DNS runtime evidence is present (\(resolverServerCount) resolver servers observed). This is not TUN DNS proof or DNS hijack verification.")
        }

        return TunDNSRuntimeEvidence(evidenceState: .inconclusive,
                                     resolverInterfaceNames: names,
                                     resolverServerCount: resolverServerCount,
                                     hasScopedResolvers: hasScopedResolvers,
                                     message: "DNS runtime evidence is inconclusive. This is read-only evidence and not DNS hijack proof.")
    }

    private static func interfaceName(forDNSKey key: String, store: SCDynamicStore) -> String? {
        let components = key.split(separator: "/")
        guard components.count >= 4 else { return nil }
        let serviceID = String(components[3])
        let interfaceKey = SCDynamicStoreKeyCreateNetworkServiceEntity(nil,
                                                                       kSCDynamicStoreDomainSetup,
                                                                       serviceID as CFString,
                                                                       kSCEntNetInterface)
        let interface = SCDynamicStoreCopyValue(store, interfaceKey) as? [String: Any]
        return interface?[kSCPropNetInterfaceDeviceName as String] as? String
    }
}
