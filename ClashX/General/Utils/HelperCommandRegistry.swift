//
//  HelperCommandRegistry.swift
//  ClashX
//
//  Created by Codex on 2026/5/16.
//

import Foundation

enum HelperCommandRegistry {
    static func allDescriptors() -> [HelperCommandDescriptor] {
        HelperCommandContract.knownCommands.map { HelperCommandContract.descriptor(for: $0) }
    }

    static func implementedSystemProxyDescriptors() -> [HelperCommandDescriptor] {
        allDescriptors().filter { $0.category == .systemProxy && $0.availability == .implemented }
    }

    static func reservedTunDescriptors() -> [HelperCommandDescriptor] {
        allDescriptors().filter { $0.category == .tunReserved && $0.availability == .reserved }
    }

    static func helperDiagnosticsDescriptors() -> [HelperCommandDescriptor] {
        allDescriptors().filter { $0.category == .helperDiagnostics && $0.availability == .implemented }
    }

    static func forbiddenCommandNotes() -> [String] {
        HelperCommandContract.forbiddenCommandCategories
    }

    static func renderedDiagnosticsSection() -> String {
        let implemented = implementedSystemProxyDescriptors().map { "- \($0.name.rawValue): \($0.diagnosticDescription)" }
        let helperDiagnostics = helperDiagnosticsDescriptors().map { "- \($0.name.rawValue): \($0.diagnosticDescription)" }
        let reserved = reservedTunDescriptors().map { "- \($0.name.rawValue): reserved only; not executable in this PR" }
        let forbidden = forbiddenCommandNotes().map { "- \($0)" }
        let header = [
            "Helper Command Contract",
            "-----------------------",
            "Implemented system-proxy commands:"
        ]
        let helperHeader = [
            "Implemented helper diagnostics:"
        ]
        let reservedHeader = [
            "Reserved TUN commands:"
        ]
        let forbiddenHeader = [
            "Forbidden command categories:"
        ]
        let footer = [
            "Helper-backed TUN is not implemented.",
            "Helper status does not imply TUN support.",
            "Future TUN work must use typed commands and must not silently fall back to legacy shell install behavior."
        ]

        let lines = header
            + implemented
            + helperHeader
            + helperDiagnostics
            + reservedHeader
            + reserved
            + forbiddenHeader
            + forbidden
            + footer
        return lines.joined(separator: "\n")
    }
}
