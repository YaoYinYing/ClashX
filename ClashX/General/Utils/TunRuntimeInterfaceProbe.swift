//
//  TunRuntimeInterfaceProbe.swift
//  ClashX
//
//  Created by Codex on 2026/5/16.
//

import Darwin
import Foundation

enum TunRuntimeInterfaceProbe {
    static func currentEvidence() -> TunRuntimeInterfaceEvidence {
        var cursor: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&cursor) == 0, let first = cursor else {
            return TunRuntimeInterfaceEvidence(interfaceNames: [],
                                               tunLikeInterfaceNames: [],
                                               evidenceState: .unavailable,
                                               message: "Read-only runtime interface enumeration is unavailable on this host. Route, DNS runtime, and packet-flow verification remain unimplemented.")
        }

        defer {
            freeifaddrs(first)
        }

        var names = Set<String>()
        var current: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = current?.pointee {
            if let rawName = entry.ifa_name {
                names.insert(String(cString: rawName))
            }
            current = entry.ifa_next
        }

        return classify(interfaceNames: names.sorted())
    }

    static func classify(interfaceNames: [String]) -> TunRuntimeInterfaceEvidence {
        let normalizedNames = Array(Set(interfaceNames)).sorted()
        let tunLikeInterfaceNames = normalizedNames.filter { isTunLikeInterfaceNameForTesting($0) }

        if normalizedNames.isEmpty {
            return TunRuntimeInterfaceEvidence(interfaceNames: [],
                                               tunLikeInterfaceNames: [],
                                               evidenceState: .inconclusive,
                                               message: "No interface names were enumerated, so runtime interface evidence is inconclusive. Route, DNS runtime, and packet-flow verification remain unimplemented.")
        }

        if tunLikeInterfaceNames.isEmpty {
            return TunRuntimeInterfaceEvidence(interfaceNames: normalizedNames,
                                               tunLikeInterfaceNames: [],
                                               evidenceState: .noTunLikeInterface,
                                               message: "No tun-like interfaces were observed. Absence of utun-style or tun-style names does not prove TUN failed. Route, DNS runtime, and packet-flow verification remain unimplemented.")
        }

        return TunRuntimeInterfaceEvidence(interfaceNames: normalizedNames,
                                           tunLikeInterfaceNames: tunLikeInterfaceNames,
                                           evidenceState: .tunLikeInterfacePresent,
                                           message: "Observed tun-like interfaces: \(tunLikeInterfaceNames.joined(separator: ", ")). This is evidence only, not proof of route, DNS, or packet-flow behavior.")
    }

    static func isTunLikeInterfaceNameForTesting(_ name: String) -> Bool {
        let normalized = name.lowercased()
        return normalized.hasPrefix("utun") || normalized.hasPrefix("tun")
    }
}
