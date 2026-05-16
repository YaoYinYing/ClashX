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

enum TunRuntimeEvidenceState: String, Codable {
    case notChecked
    case unavailable
    case noTunLikeInterface
    case tunLikeInterfacePresent
    case inconclusive
}

enum TunRuntimeVerificationLevel: String, Codable {
    case controllerConfigOnly
    case interfacePresenceOnly
    case routeVerificationNotImplemented
    case dnsRuntimeVerificationNotImplemented
    case packetFlowVerificationNotImplemented
}

struct TunRuntimeInterfaceEvidence: Codable {
    var interfaceNames: [String]
    var tunLikeInterfaceNames: [String]
    var evidenceState: TunRuntimeEvidenceState
    var message: String
}

struct TunRuntimeVerificationReport: Codable {
    var expectedEnabled: Bool
    var controllerReportedEnabled: Bool?
    var interfaceEvidence: TunRuntimeInterfaceEvidence
    var verificationLevels: [TunRuntimeVerificationLevel]
    var isRuntimeConsistentWithController: Bool?
    var message: String
    var recoverySuggestion: String
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
    var runtimeVerification: TunRuntimeVerificationReport?
    var message: String
    var recoverySuggestion: String
}
