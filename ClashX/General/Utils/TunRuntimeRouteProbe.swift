//
//  TunRuntimeRouteProbe.swift
//  ClashX
//
//  Created by Codex on 2026/5/16.
//

import Foundation
import SystemConfiguration

enum TunRuntimeRouteProbe {
    static func currentEvidence(tunLikeInterfaceNames: [String]) -> TunRouteRuntimeEvidence {
        guard let store = SCDynamicStoreCreate(nil, "ClashX.TunRuntimeRouteProbe" as CFString, nil, nil) else {
            return TunRouteRuntimeEvidence(evidenceState: .unavailable,
                                           ipv4PrimaryInterface: nil,
                                           ipv6PrimaryInterface: nil,
                                           tunLikeRouteInterfaces: [],
                                           observedPrimaryRouteInterfaces: [],
                                           message: "Read-only route runtime evidence is unavailable on this host. Route evidence remains read-only and is not packet-flow proof.")
        }

        let ipv4PrimaryInterface = primaryInterface(from: store, entity: kSCEntNetIPv4)
        let ipv6PrimaryInterface = primaryInterface(from: store, entity: kSCEntNetIPv6)
        return classify(ipv4PrimaryInterface: ipv4PrimaryInterface,
                        ipv6PrimaryInterface: ipv6PrimaryInterface,
                        tunLikeInterfaceNames: tunLikeInterfaceNames)
    }

    static func classify(ipv4PrimaryInterface: String?,
                         ipv6PrimaryInterface: String?,
                         tunLikeInterfaceNames: [String]) -> TunRouteRuntimeEvidence {
        let observed = deduplicated([ipv4PrimaryInterface, ipv6PrimaryInterface].compactMap { $0 })
        let tunLikeSet = Set(tunLikeInterfaceNames.map { $0.lowercased() })
        let tunLikeRouteInterfaces = observed.filter { tunLikeSet.contains($0.lowercased()) || TunRuntimeInterfaceProbe.isTunLikeInterfaceNameForTesting($0) }

        if observed.isEmpty {
            return TunRouteRuntimeEvidence(evidenceState: .inconclusive,
                                           ipv4PrimaryInterface: ipv4PrimaryInterface,
                                           ipv6PrimaryInterface: ipv6PrimaryInterface,
                                           tunLikeRouteInterfaces: [],
                                           observedPrimaryRouteInterfaces: [],
                                           message: "No route-visible interfaces were observed, so route evidence is inconclusive. Route evidence is read-only and is not packet-flow proof.")
        }

        if let ipv4PrimaryInterface, TunRuntimeInterfaceProbe.isTunLikeInterfaceNameForTesting(ipv4PrimaryInterface) {
            return TunRouteRuntimeEvidence(evidenceState: .tunLikeRouteEvidencePresent,
                                           ipv4PrimaryInterface: ipv4PrimaryInterface,
                                           ipv6PrimaryInterface: ipv6PrimaryInterface,
                                           tunLikeRouteInterfaces: deduplicated([ipv4PrimaryInterface] + tunLikeRouteInterfaces),
                                           observedPrimaryRouteInterfaces: observed,
                                           message: "The IPv4 primary route interface appears tun-like: \(ipv4PrimaryInterface). This is read-only route evidence only and is not packet-flow proof.")
        }

        if let ipv6PrimaryInterface, TunRuntimeInterfaceProbe.isTunLikeInterfaceNameForTesting(ipv6PrimaryInterface) {
            return TunRouteRuntimeEvidence(evidenceState: .tunLikeRouteEvidencePresent,
                                           ipv4PrimaryInterface: ipv4PrimaryInterface,
                                           ipv6PrimaryInterface: ipv6PrimaryInterface,
                                           tunLikeRouteInterfaces: deduplicated([ipv6PrimaryInterface] + tunLikeRouteInterfaces),
                                           observedPrimaryRouteInterfaces: observed,
                                           message: "The IPv6 primary route interface appears tun-like: \(ipv6PrimaryInterface). This is read-only route evidence only and is not packet-flow proof.")
        }

        if !tunLikeRouteInterfaces.isEmpty {
            return TunRouteRuntimeEvidence(evidenceState: .tunLikeRouteEvidencePresent,
                                           ipv4PrimaryInterface: ipv4PrimaryInterface,
                                           ipv6PrimaryInterface: ipv6PrimaryInterface,
                                           tunLikeRouteInterfaces: tunLikeRouteInterfaces,
                                           observedPrimaryRouteInterfaces: observed,
                                           message: "Observed primary route interfaces include tun-like names: \(tunLikeRouteInterfaces.joined(separator: ", ")). This is read-only route evidence only and is not packet-flow proof.")
        }

        return TunRouteRuntimeEvidence(evidenceState: .noTunLikeRouteEvidence,
                                       ipv4PrimaryInterface: ipv4PrimaryInterface,
                                       ipv6PrimaryInterface: ipv6PrimaryInterface,
                                       tunLikeRouteInterfaces: [],
                                       observedPrimaryRouteInterfaces: observed,
                                       message: "Observed primary route interfaces do not include tun-like names. This does not prove failure, and route evidence is not packet-flow proof.")
    }

    private static func primaryInterface(from store: SCDynamicStore, entity: CFString) -> String? {
        let key = SCDynamicStoreKeyCreateNetworkGlobalEntity(nil, kSCDynamicStoreDomainState, entity)
        let dict = SCDynamicStoreCopyValue(store, key) as? [String: String]
        return dict?[kSCDynamicStorePropNetPrimaryInterface as String]
    }

    private static func deduplicated(_ values: [String]) -> [String] {
        Array(Set(values)).sorted()
    }
}
