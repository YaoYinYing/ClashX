//
//  TunLifecycleDiagnostics.swift
//  ClashX
//
//  Created by Codex on 2026/5/16.
//

import Foundation

enum TunRuntimeMode: String, Codable {
    case externalController
    case embeddedCoreUnsupported
}

enum TunPreflightBlocker: String, Codable, CaseIterable {
    case controllerNotRunning
    case embeddedCoreUnsupported
    case controllerConfigUnavailable
    case tunSectionMissing
    case tunValidationFailed
    case dnsValidationFailed
    case configPatchUnsupported
    case controllerUnauthorized
    case helperTunReservedOnly
}

enum TunVerificationScope: String, Codable {
    case controllerConfigOnly
    case systemTunNotImplemented
}

enum TunVerificationOutcome: String, Codable {
    case notAttempted
    case requestedButUnverified
    case controllerStateMatches
    case controllerStateMismatch
    case failed
}

struct TunPreflightReport: Codable {
    var runtimeMode: TunRuntimeMode
    var canAttemptControllerPatch: Bool
    var blockers: [TunPreflightBlocker]
    var warnings: [String]
    var helperTrustState: HelperTrustState
    var helperTunCommandsReserved: Bool
    var verificationScope: TunVerificationScope
    var userMessage: String
    var recoverySuggestion: String
}

struct TunLifecycleVerificationReport: Codable {
    var expectedEnabled: Bool
    var outcome: TunVerificationOutcome
    var verificationScope: TunVerificationScope
    var controllerReportedEnabled: Bool?
    var message: String
    var recoverySuggestion: String
}
