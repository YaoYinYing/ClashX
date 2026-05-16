//
//  HelperCommandContract.swift
//  ClashX
//
//  Created by Codex on 2026/5/16.
//

import Foundation

enum HelperCommandCategory: String, Codable, CaseIterable {
    case systemProxy
    case helperDiagnostics
    case tunReserved
}

enum HelperCommandName: String, Codable, CaseIterable {
    case getVersion
    case enableSystemProxy
    case disableSystemProxy
    case restoreSystemProxy
    case readSystemProxy
    case helperStatus
    case tunPreflight
    case tunEnable
    case tunDisable
    case tunStatus
    case tunVerifyRoute
    case tunVerifyDNS
    case tunRollback
}

enum HelperCommandAvailability: String, Codable {
    case implemented
    case reserved
    case forbidden
}

struct HelperCommandDescriptor: Codable {
    var name: HelperCommandName
    var category: HelperCommandCategory
    var availability: HelperCommandAvailability
    var requiresPrivilege: Bool
    var mutatesSystemState: Bool
    var diagnosticDescription: String
    var safetyNotes: String
}

enum HelperCommandErrorCode: String, Codable, CaseIterable {
    case unavailable
    case unsupported
    case unauthorized
    case requirementMismatch
    case notInstalled
    case timeout
    case helperRejected
    case invalidInput
    case forbidden
    case unknown
}

struct HelperCommandResult: Codable {
    var command: HelperCommandName
    var success: Bool
    var errorCode: HelperCommandErrorCode?
    var message: String
    var recoverySuggestion: String?
}

enum HelperCommandContract {
    static let knownCommands = HelperCommandName.allCases

    static let forbiddenCommandCategories = [
        "arbitrary shell execution",
        "arbitrary file writes",
        "arbitrary launchctl calls",
        "arbitrary route commands",
        "arbitrary process spawning",
        "arbitrary command strings from the app",
        "generic root proxy for app-side logic"
    ]

    static let knownDescriptors: [HelperCommandDescriptor] = [
        HelperCommandDescriptor(name: .getVersion,
                                category: .systemProxy,
                                availability: .implemented,
                                requiresPrivilege: false,
                                mutatesSystemState: false,
                                diagnosticDescription: "Reads the bundled helper version for install and update checks.",
                                safetyNotes: "Read-only helper metadata call. It must not be treated as proof of privileged TUN support."),
        HelperCommandDescriptor(name: .enableSystemProxy,
                                category: .systemProxy,
                                availability: .implemented,
                                requiresPrivilege: true,
                                mutatesSystemState: true,
                                diagnosticDescription: "Enables system proxy settings through the bounded helper XPC surface.",
                                safetyNotes: "Input must stay typed and validated. This helper method must not become a generic privileged command runner."),
        HelperCommandDescriptor(name: .disableSystemProxy,
                                category: .systemProxy,
                                availability: .implemented,
                                requiresPrivilege: true,
                                mutatesSystemState: true,
                                diagnosticDescription: "Disables the system proxy settings managed by SmartX.",
                                safetyNotes: "This remains scoped to proxy state only and does not imply route or TUN control."),
        HelperCommandDescriptor(name: .restoreSystemProxy,
                                category: .systemProxy,
                                availability: .implemented,
                                requiresPrivilege: true,
                                mutatesSystemState: true,
                                diagnosticDescription: "Restores system proxy settings from the app's typed proxy snapshot.",
                                safetyNotes: "Restore remains proxy-specific. Future TUN recovery must use a separate typed contract."),
        HelperCommandDescriptor(name: .readSystemProxy,
                                category: .systemProxy,
                                availability: .implemented,
                                requiresPrivilege: false,
                                mutatesSystemState: false,
                                diagnosticDescription: "Reads current system proxy settings for diagnostics and restore preparation.",
                                safetyNotes: "Read-only system-proxy inspection. It must not prompt for helper install or authorization."),
        HelperCommandDescriptor(name: .helperStatus,
                                category: .helperDiagnostics,
                                availability: .implemented,
                                requiresPrivilege: false,
                                mutatesSystemState: false,
                                diagnosticDescription: "Builds a diagnostic-only helper trust summary from bundled metadata and safe local file checks.",
                                safetyNotes: "Helper status is descriptive only. It does not perform XPC trust verification and does not imply TUN support."),
        HelperCommandDescriptor(name: .tunPreflight,
                                category: .tunReserved,
                                availability: .reserved,
                                requiresPrivilege: true,
                                mutatesSystemState: false,
                                diagnosticDescription: "Reserved typed helper preflight for a future helper-backed TUN boundary.",
                                safetyNotes: "Reserved only in this PR. No executable helper-backed TUN behavior exists."),
        HelperCommandDescriptor(name: .tunEnable,
                                category: .tunReserved,
                                availability: .reserved,
                                requiresPrivilege: true,
                                mutatesSystemState: false,
                                diagnosticDescription: "Reserved typed helper command for a future helper-backed TUN enable flow.",
                                safetyNotes: "Reserved only in this PR. SmartX does not enable helper-backed TUN here."),
        HelperCommandDescriptor(name: .tunDisable,
                                category: .tunReserved,
                                availability: .reserved,
                                requiresPrivilege: true,
                                mutatesSystemState: false,
                                diagnosticDescription: "Reserved typed helper command for a future helper-backed TUN disable flow.",
                                safetyNotes: "Reserved only in this PR. SmartX does not disable helper-backed TUN here."),
        HelperCommandDescriptor(name: .tunStatus,
                                category: .tunReserved,
                                availability: .reserved,
                                requiresPrivilege: true,
                                mutatesSystemState: false,
                                diagnosticDescription: "Reserved typed helper command for future helper-owned TUN status reporting.",
                                safetyNotes: "Reserved only in this PR. Helper status remains separate from any future TUN status."),
        HelperCommandDescriptor(name: .tunVerifyRoute,
                                category: .tunReserved,
                                availability: .reserved,
                                requiresPrivilege: true,
                                mutatesSystemState: false,
                                diagnosticDescription: "Reserved typed helper command for future route verification after a helper-backed TUN action.",
                                safetyNotes: "Reserved only in this PR. No route ownership or route mutation is implemented."),
        HelperCommandDescriptor(name: .tunVerifyDNS,
                                category: .tunReserved,
                                availability: .reserved,
                                requiresPrivilege: true,
                                mutatesSystemState: false,
                                diagnosticDescription: "Reserved typed helper command for future DNS verification after a helper-backed TUN action.",
                                safetyNotes: "Reserved only in this PR. No helper-backed DNS mutation or verification runs here."),
        HelperCommandDescriptor(name: .tunRollback,
                                category: .tunReserved,
                                availability: .reserved,
                                requiresPrivilege: true,
                                mutatesSystemState: false,
                                diagnosticDescription: "Reserved typed helper command for a future rollback or recovery flow after helper-backed TUN work.",
                                safetyNotes: "Reserved only in this PR. SmartX does not perform helper-backed TUN rollback here.")
    ]

    static func descriptor(for command: HelperCommandName) -> HelperCommandDescriptor {
        if let descriptor = knownDescriptors.first(where: { $0.name == command }) {
            return descriptor
        }
        preconditionFailure("Missing descriptor for helper command \(command.rawValue)")
    }

    static func isTunCommandReserved(_ command: HelperCommandName) -> Bool {
        descriptor(for: command).category == .tunReserved &&
            descriptor(for: command).availability == .reserved
    }
}
