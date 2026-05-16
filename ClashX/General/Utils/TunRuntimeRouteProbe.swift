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
                                           defaultRouteInterface: nil,
                                           tunLikeRouteInterfaces: [],
                                           observedRouteInterfaces: [],
                                           message: "Read-only route runtime evidence is unavailable on this host. Route evidence remains read-only and is not packet-flow proof.")
        }

        let observedRouteInterfaces = Array(Set([primaryInterface(from: store, entity: kSCEntNetIPv4),
                                                 primaryInterface(from: store, entity: kSCEntNetIPv6)]
                .compactMap { $0 }))
            .sorted()

        let defaultRouteInterface = observedRouteInterfaces.first
        return classify(defaultRouteInterface: defaultRouteInterface,
                        observedRouteInterfaces: observedRouteInterfaces,
                        tunLikeInterfaceNames: tunLikeInterfaceNames)
    }

    static func classify(defaultRouteInterface: String?,
                         observedRouteInterfaces: [String],
                         tunLikeInterfaceNames: [String]) -> TunRouteRuntimeEvidence {
        let observed = Array(Set(observedRouteInterfaces)).sorted()
        let tunLikeSet = Set(tunLikeInterfaceNames.map { $0.lowercased() })
        let tunLikeRouteInterfaces = observed.filter { tunLikeSet.contains($0.lowercased()) || TunRuntimeInterfaceProbe.isTunLikeInterfaceNameForTesting($0) }

        if observed.isEmpty {
            return TunRouteRuntimeEvidence(evidenceState: .inconclusive,
                                           defaultRouteInterface: defaultRouteInterface,
                                           tunLikeRouteInterfaces: [],
                                           observedRouteInterfaces: [],
                                           message: "No route-visible interfaces were observed, so route evidence is inconclusive. Route evidence is read-only and is not packet-flow proof.")
        }

        if let defaultRouteInterface, TunRuntimeInterfaceProbe.isTunLikeInterfaceNameForTesting(defaultRouteInterface) {
            return TunRouteRuntimeEvidence(evidenceState: .tunLikeRouteEvidencePresent,
                                           defaultRouteInterface: defaultRouteInterface,
                                           tunLikeRouteInterfaces: deduplicated([defaultRouteInterface] + tunLikeRouteInterfaces),
                                           observedRouteInterfaces: observed,
                                           message: "The default route interface appears tun-like: \(defaultRouteInterface). This is read-only route evidence only and is not packet-flow proof.")
        }

        if !tunLikeRouteInterfaces.isEmpty {
            return TunRouteRuntimeEvidence(evidenceState: .tunLikeRouteEvidencePresent,
                                           defaultRouteInterface: defaultRouteInterface,
                                           tunLikeRouteInterfaces: tunLikeRouteInterfaces,
                                           observedRouteInterfaces: observed,
                                           message: "Observed route-visible interfaces include tun-like names: \(tunLikeRouteInterfaces.joined(separator: ", ")). This is read-only route evidence only and is not packet-flow proof.")
        }

        return TunRouteRuntimeEvidence(evidenceState: .noTunLikeRouteEvidence,
                                       defaultRouteInterface: defaultRouteInterface,
                                       tunLikeRouteInterfaces: [],
                                       observedRouteInterfaces: observed,
                                       message: "Observed route-visible interfaces do not include tun-like names. This does not prove failure, and route evidence is not packet-flow proof.")
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
