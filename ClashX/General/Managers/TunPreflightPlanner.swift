//
//  TunPreflightPlanner.swift
//  ClashX
//
//  Created by Codex on 2026/5/16.
//

import Foundation

enum TunPreflightPlanner {
    static func buildReport(config: ClashConfig?,
                            isControllerRunning: Bool,
                            isUsingEmbeddedCore: Bool,
                            configPatchAvailability: CoreEndpointAvailability,
                            helperStatus: HelperStatus,
                            helperTunDescriptors: [HelperCommandDescriptor]) -> TunPreflightReport {
        var blockers = [TunPreflightBlocker]()
        var warnings = [String]()

        let runtimeMode: TunRuntimeMode = isUsingEmbeddedCore ? .embeddedCoreUnsupported : .externalController
        if !isControllerRunning {
            blockers.append(.controllerNotRunning)
        }
        if isUsingEmbeddedCore {
            blockers.append(.embeddedCoreUnsupported)
        }
        guard isControllerRunning, !isUsingEmbeddedCore else {
            let warningLines = boundaryWarnings(config: config,
                                                helperStatus: helperStatus,
                                                helperTunDescriptors: helperTunDescriptors)
            warnings.append(contentsOf: warningLines)
            return TunPreflightReport(runtimeMode: runtimeMode,
                                      canAttemptControllerPatch: false,
                                      blockers: ordered(blockers),
                                      warnings: deduplicated(warnings),
                                      helperTrustState: helperStatus.trustState,
                                      helperTunCommandsReserved: true,
                                      verificationScope: .systemTunNotImplemented,
                                      userMessage: userMessage(for: ordered(blockers), runtimeMode: runtimeMode),
                                      recoverySuggestion: recoverySuggestion(for: ordered(blockers)))
        }

        guard let config else {
            blockers.append(.controllerConfigUnavailable)
            warnings.append(contentsOf: boundaryWarnings(config: nil,
                                                         helperStatus: helperStatus,
                                                         helperTunDescriptors: helperTunDescriptors))
            return TunPreflightReport(runtimeMode: runtimeMode,
                                      canAttemptControllerPatch: false,
                                      blockers: ordered(blockers),
                                      warnings: deduplicated(warnings),
                                      helperTrustState: helperStatus.trustState,
                                      helperTunCommandsReserved: true,
                                      verificationScope: .systemTunNotImplemented,
                                      userMessage: userMessage(for: ordered(blockers), runtimeMode: runtimeMode),
                                      recoverySuggestion: recoverySuggestion(for: ordered(blockers)))
        }

        if config.tun == nil {
            blockers.append(.tunSectionMissing)
        }

        let tunValidation = TunConfigValidator.validate(config.tun)
        let dnsValidation = DNSConfigValidator.validate(config.dns)
        let tunBlocking = !tunValidation.blockingErrors.isEmpty
        let dnsBlocking = dnsValidation.issues.contains { $0.severity == .blocking }
        if tunBlocking {
            blockers.append(.tunValidationFailed)
        }
        if dnsBlocking {
            blockers.append(.dnsValidationFailed)
        }

        switch configPatchAvailability {
        case .unsupported:
            blockers.append(.configPatchUnsupported)
        case .unauthorized:
            blockers.append(.controllerUnauthorized)
        case .unknown, .available, .degraded, .unavailable:
            break
        }

        warnings.append(contentsOf: tunValidation.warnings.map(\.message))
        warnings.append(contentsOf: tunValidation.informational.map(\.message))
        warnings.append(contentsOf: dnsValidation.issues.map(\.message))
        warnings.append(contentsOf: boundaryWarnings(config: config,
                                                     helperStatus: helperStatus,
                                                     helperTunDescriptors: helperTunDescriptors))

        let finalBlockers = ordered(blockers)
        let canAttemptControllerPatch = finalBlockers.isEmpty
        let verificationScope: TunVerificationScope = canAttemptControllerPatch ? .controllerConfigOnly : .systemTunNotImplemented

        return TunPreflightReport(runtimeMode: runtimeMode,
                                  canAttemptControllerPatch: canAttemptControllerPatch,
                                  blockers: finalBlockers,
                                  warnings: deduplicated(warnings),
                                  helperTrustState: helperStatus.trustState,
                                  helperTunCommandsReserved: true,
                                  verificationScope: verificationScope,
                                  userMessage: userMessage(for: finalBlockers, runtimeMode: runtimeMode),
                                  recoverySuggestion: recoverySuggestion(for: finalBlockers))
    }

    static func verificationReport(expectedEnabled: Bool,
                                   controllerReportedEnabled: Bool?,
                                   didFailToReload: Bool,
                                   preflightReport: TunPreflightReport,
                                   interfaceEvidence: TunRuntimeInterfaceEvidence = TunRuntimeInterfaceEvidence(interfaceNames: [],
                                                                                                                tunLikeInterfaceNames: [],
                                                                                                                evidenceState: .notChecked,
                                                                                                                message: "Runtime interface evidence was not checked.")) -> TunLifecycleVerificationReport {
        let runtimeReport = runtimeVerificationReport(expectedEnabled: expectedEnabled,
                                                      controllerReportedEnabled: controllerReportedEnabled,
                                                      didFailToReload: didFailToReload,
                                                      preflightReport: preflightReport,
                                                      interfaceEvidence: interfaceEvidence)

        if didFailToReload {
            return TunLifecycleVerificationReport(expectedEnabled: expectedEnabled,
                                                  outcome: .requestedButUnverified,
                                                  verificationScope: .controllerConfigOnly,
                                                  controllerReportedEnabled: nil,
                                                  runtimeVerification: runtimeReport,
                                                  message: runtimeReport.message,
                                                  recoverySuggestion: runtimeReport.recoverySuggestion)
        }

        guard let controllerReportedEnabled else {
            return TunLifecycleVerificationReport(expectedEnabled: expectedEnabled,
                                                  outcome: .failed,
                                                  verificationScope: preflightReport.verificationScope,
                                                  controllerReportedEnabled: nil,
                                                  runtimeVerification: runtimeReport,
                                                  message: runtimeReport.message,
                                                  recoverySuggestion: runtimeReport.recoverySuggestion)
        }

        if controllerReportedEnabled == expectedEnabled {
            return TunLifecycleVerificationReport(expectedEnabled: expectedEnabled,
                                                  outcome: .controllerStateMatches,
                                                  verificationScope: .controllerConfigOnly,
                                                  controllerReportedEnabled: controllerReportedEnabled,
                                                  runtimeVerification: runtimeReport,
                                                  message: runtimeReport.message,
                                                  recoverySuggestion: runtimeReport.recoverySuggestion)
        }

        return TunLifecycleVerificationReport(expectedEnabled: expectedEnabled,
                                              outcome: .controllerStateMismatch,
                                              verificationScope: .controllerConfigOnly,
                                              controllerReportedEnabled: controllerReportedEnabled,
                                              runtimeVerification: runtimeReport,
                                              message: runtimeReport.message,
                                              recoverySuggestion: runtimeReport.recoverySuggestion)
    }

    static func runtimeVerificationReport(expectedEnabled: Bool,
                                          controllerReportedEnabled: Bool?,
                                          didFailToReload: Bool,
                                          preflightReport: TunPreflightReport,
                                          interfaceEvidence: TunRuntimeInterfaceEvidence) -> TunRuntimeVerificationReport {
        let verificationLevels = runtimeVerificationLevels(interfaceEvidence: interfaceEvidence)
        let consistency = runtimeConsistency(controllerReportedEnabled: controllerReportedEnabled,
                                             interfaceEvidence: interfaceEvidence)
        let message = runtimeVerificationMessage(expectedEnabled: expectedEnabled,
                                                 controllerReportedEnabled: controllerReportedEnabled,
                                                 didFailToReload: didFailToReload,
                                                 preflightReport: preflightReport,
                                                 interfaceEvidence: interfaceEvidence,
                                                 consistency: consistency)
        let recoverySuggestion = runtimeRecoverySuggestion(expectedEnabled: expectedEnabled,
                                                           controllerReportedEnabled: controllerReportedEnabled,
                                                           didFailToReload: didFailToReload,
                                                           interfaceEvidence: interfaceEvidence)
        return TunRuntimeVerificationReport(expectedEnabled: expectedEnabled,
                                            controllerReportedEnabled: controllerReportedEnabled,
                                            interfaceEvidence: interfaceEvidence,
                                            verificationLevels: verificationLevels,
                                            isRuntimeConsistentWithController: consistency,
                                            message: message,
                                            recoverySuggestion: recoverySuggestion)
    }

    private static func userMessage(for blockers: [TunPreflightBlocker],
                                    runtimeMode: TunRuntimeMode) -> String {
        guard let first = blockers.first else {
            return "External-controller TUN can be attempted only through the controller API, helper-backed TUN remains reserved only, and any verification is limited to controller config state."
        }

        switch first {
        case .controllerNotRunning:
            return "The active controller is not running, so SmartX cannot attempt a guarded TUN patch."
        case .embeddedCoreUnsupported:
            return "Embedded-core TUN is unsupported in this build, and helper-backed TUN remains reserved only."
        case .controllerConfigUnavailable:
            return "SmartX could not load controller config state, so it cannot safely attempt a guarded TUN patch."
        case .tunSectionMissing:
            return "The current controller config does not expose a tun section, so SmartX keeps TUN disabled."
        case .tunValidationFailed:
            return "SmartX blocked the guarded TUN patch because the current tun config has blocking validation issues."
        case .dnsValidationFailed:
            return "SmartX blocked the guarded TUN patch because the current DNS config has blocking validation issues."
        case .configPatchUnsupported:
            return "The active controller does not support guarded TUN updates through the controller API, and helper-backed TUN remains reserved only."
        case .controllerUnauthorized:
            return "The active controller rejected config patch access, so SmartX cannot attempt a guarded TUN update."
        case .helperTunReservedOnly:
            return runtimeMode == .embeddedCoreUnsupported
                ? "Helper-backed TUN commands remain reserved only, and embedded-core TUN is unsupported in this build."
                : "Helper-backed TUN commands remain reserved only. SmartX can only attempt an external-controller config patch path."
        }
    }

    private static func recoverySuggestion(for blockers: [TunPreflightBlocker]) -> String {
        if blockers.isEmpty {
            return "A successful request can only prove controller-config state. SmartX does not implement utun, route, interface, or DNS runtime verification yet."
        }

        if blockers.contains(.embeddedCoreUnsupported) {
            return "Keep using the external-controller config patch path only. Embedded-core TUN and helper-backed TUN remain future work."
        }
        if blockers.contains(.controllerNotRunning) || blockers.contains(.controllerConfigUnavailable) {
            return "Reconnect the external controller, reload config state, and retry only after SmartX can read /configs reliably."
        }
        if blockers.contains(.tunSectionMissing) {
            return "Add or expose a tun section in controller config before attempting a guarded TUN update."
        }
        if blockers.contains(.tunValidationFailed) || blockers.contains(.dnsValidationFailed) {
            return "Fix the blocking validation issues first. SmartX will not fall back to helper-backed TUN or system-level commands."
        }
        if blockers.contains(.configPatchUnsupported) || blockers.contains(.controllerUnauthorized) {
            return "Use a controller/runtime that exposes authorized /configs patching. SmartX does not allow helper takeover for TUN here."
        }
        return "Helper-backed TUN remains reserved only. SmartX does not provide a shell-based or privileged fallback for TUN."
    }

    private static func boundaryWarnings(config: ClashConfig?,
                                         helperStatus: HelperStatus,
                                         helperTunDescriptors: [HelperCommandDescriptor]) -> [String] {
        var warnings = [String]()
        warnings.append("Helper status is \(helperStatus.trustState.rawValue). Helper status does not imply TUN support.")
        if helperTunDescriptors.allSatisfy({ $0.availability == .reserved }) {
            warnings.append("Helper-backed TUN commands are reserved only. SmartX does not execute helper-backed TUN in this build.")
        }
        warnings.append("System-level TUN verification is not implemented. SmartX only verifies controller config state when available.")
        if let config, config.tun != nil {
            warnings.append("External-controller TUN remains a guarded controller API patch path.")
        }
        return warnings
    }

    private static func runtimeVerificationLevels(interfaceEvidence: TunRuntimeInterfaceEvidence) -> [TunRuntimeVerificationLevel] {
        var levels = [TunRuntimeVerificationLevel.controllerConfigOnly]
        if interfaceEvidence.evidenceState != .notChecked {
            levels.append(.interfacePresenceOnly)
        }
        levels.append(.routeVerificationNotImplemented)
        levels.append(.dnsRuntimeVerificationNotImplemented)
        levels.append(.packetFlowVerificationNotImplemented)
        return levels
    }

    private static func runtimeConsistency(controllerReportedEnabled: Bool?,
                                           interfaceEvidence: TunRuntimeInterfaceEvidence) -> Bool? {
        guard let controllerReportedEnabled else { return nil }

        switch (controllerReportedEnabled, interfaceEvidence.evidenceState) {
        case (true, .tunLikeInterfacePresent), (false, .noTunLikeInterface):
            return true
        case (true, .noTunLikeInterface), (false, .tunLikeInterfacePresent):
            return false
        case (_, .notChecked), (_, .unavailable), (_, .inconclusive):
            return nil
        }
    }

    private static func runtimeVerificationMessage(expectedEnabled: Bool,
                                                   controllerReportedEnabled: Bool?,
                                                   didFailToReload: Bool,
                                                   preflightReport: TunPreflightReport,
                                                   interfaceEvidence: TunRuntimeInterfaceEvidence,
                                                   consistency: Bool?) -> String {
        let base: String
        if didFailToReload {
            base = "SmartX sent the controller TUN update request, but could not confirm controller-config state after reload."
        } else if let controllerReportedEnabled {
            if controllerReportedEnabled == expectedEnabled {
                base = "Controller config matches tun.enable=\(expectedEnabled ? "true" : "false")."
            } else {
                base = "SmartX requested tun.enable=\(expectedEnabled ? "true" : "false"), but the controller reported tun.enable=\(controllerReportedEnabled ? "true" : "false")."
            }
        } else {
            base = "SmartX could not read controller-config TUN state after the request."
        }

        let evidenceLine = runtimeEvidenceSummary(expectedEnabled: expectedEnabled,
                                                  controllerReportedEnabled: controllerReportedEnabled,
                                                  interfaceEvidence: interfaceEvidence,
                                                  consistency: consistency)

        let verificationLine = "Route verification is not implemented. DNS runtime verification is not implemented. Packet-flow verification is not implemented."
        let helperLine = preflightReport.helperTunCommandsReserved
            ? "Helper-backed TUN remains reserved only."
            : nil
        return [base, evidenceLine, helperLine, verificationLine]
            .compactMap { $0 }
            .joined(separator: " ")
    }

    private static func runtimeRecoverySuggestion(expectedEnabled: Bool,
                                                  controllerReportedEnabled: Bool?,
                                                  didFailToReload: Bool,
                                                  interfaceEvidence: TunRuntimeInterfaceEvidence) -> String {
        if didFailToReload {
            return "Refresh controller config, inspect the current core log, and compare the latest tun.enable state with the read-only interface evidence. SmartX does not implement route, DNS runtime, or packet-flow verification."
        }

        guard let controllerReportedEnabled else {
            return "Re-read /configs when available and compare it with the read-only interface evidence. SmartX does not implement route, DNS runtime, or packet-flow verification."
        }

        if controllerReportedEnabled != expectedEnabled {
            return "Inspect controller config first, then compare it with the read-only interface evidence. SmartX will not mutate routes, DNS, or helper state to force runtime alignment."
        }

        if expectedEnabled {
            switch interfaceEvidence.evidenceState {
            case .tunLikeInterfacePresent:
                return "Treat the tun-like interface as supporting evidence only. Route, DNS runtime, and packet-flow verification remain future work."
            case .noTunLikeInterface:
                return "No tun-like interface evidence was observed. This does not prove failure; inspect the core log and current controller state before assuming TUN is broken."
            case .unavailable, .inconclusive, .notChecked:
                return "Runtime interface evidence is unavailable or inconclusive. Inspect controller state and the core log; SmartX does not implement route, DNS runtime, or packet-flow verification."
            }
        }

        switch interfaceEvidence.evidenceState {
        case .tunLikeInterfacePresent:
            return "Tun-like interface evidence remains even though controller config now says tun.enable=false. The interface may belong to another app or may require manual inspection."
        case .noTunLikeInterface:
            return "Controller config now says tun.enable=false and no tun-like interface evidence was observed. Route, DNS runtime, and packet-flow verification still remain unimplemented."
        case .unavailable, .inconclusive, .notChecked:
            return "Runtime interface evidence is unavailable or inconclusive, so only controller config state is confirmed."
        }
    }

    private static func runtimeEvidenceSummary(expectedEnabled: Bool,
                                               controllerReportedEnabled: Bool?,
                                               interfaceEvidence: TunRuntimeInterfaceEvidence,
                                               consistency: Bool?) -> String {
        switch interfaceEvidence.evidenceState {
        case .notChecked:
            return "Runtime interface evidence was not checked."
        case .unavailable, .inconclusive:
            return interfaceEvidence.message
        case .tunLikeInterfacePresent:
            let names = interfaceEvidence.tunLikeInterfaceNames.joined(separator: ", ")
            if controllerReportedEnabled == false {
                return "Tun-like interface evidence remains: \(names). This does not prove route ownership and may belong to another app or require manual inspection."
            }
            return "A tun-like interface was observed: \(names). This is evidence only and does not prove packet forwarding, route ownership, or DNS hijack behavior."
        case .noTunLikeInterface:
            if controllerReportedEnabled == true || expectedEnabled {
                return "No tun-like interface was observed. This does not prove failure; inspect the core log and current controller state."
            }
            if consistency == true {
                return "No tun-like interface was observed."
            }
            return "No tun-like interface was observed. Absence of utun-style or tun-style names does not prove TUN failed."
        }
    }

    private static func ordered(_ blockers: [TunPreflightBlocker]) -> [TunPreflightBlocker] {
        TunPreflightBlocker.allCases.filter { blockers.contains($0) }
    }

    private static func deduplicated(_ warnings: [String]) -> [String] {
        var seen = Set<String>()
        return warnings.filter { seen.insert($0).inserted }
    }
}
