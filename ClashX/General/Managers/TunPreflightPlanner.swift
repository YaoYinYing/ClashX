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
                                                                                                                message: "Runtime interface evidence was not checked."),
                                   routeEvidence: TunRouteRuntimeEvidence = TunRouteRuntimeEvidence(evidenceState: .notChecked,
                                                                                                    defaultRouteInterface: nil,
                                                                                                    tunLikeRouteInterfaces: [],
                                                                                                    observedRouteInterfaces: [],
                                                                                                    message: "Route runtime evidence was not checked."),
                                   dnsEvidence: TunDNSRuntimeEvidence = TunDNSRuntimeEvidence(evidenceState: .notChecked,
                                                                                              resolverInterfaceNames: [],
                                                                                              resolverServerCount: nil,
                                                                                              hasScopedResolvers: nil,
                                                                                              message: "DNS runtime evidence was not checked.")) -> TunLifecycleVerificationReport {
        let runtimeReport = runtimeVerificationReport(expectedEnabled: expectedEnabled,
                                                      controllerReportedEnabled: controllerReportedEnabled,
                                                      didFailToReload: didFailToReload,
                                                      preflightReport: preflightReport,
                                                      interfaceEvidence: interfaceEvidence,
                                                      routeEvidence: routeEvidence,
                                                      dnsEvidence: dnsEvidence)

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
                                          interfaceEvidence: TunRuntimeInterfaceEvidence,
                                          routeEvidence: TunRouteRuntimeEvidence,
                                          dnsEvidence: TunDNSRuntimeEvidence) -> TunRuntimeVerificationReport {
        let verificationLevels = runtimeVerificationLevels(interfaceEvidence: interfaceEvidence,
                                                           routeEvidence: routeEvidence,
                                                           dnsEvidence: dnsEvidence)
        let consistency = runtimeConsistency(controllerReportedEnabled: controllerReportedEnabled,
                                             interfaceEvidence: interfaceEvidence,
                                             routeEvidence: routeEvidence)
        let message = runtimeVerificationMessage(expectedEnabled: expectedEnabled,
                                                 controllerReportedEnabled: controllerReportedEnabled,
                                                 didFailToReload: didFailToReload,
                                                 preflightReport: preflightReport,
                                                 interfaceEvidence: interfaceEvidence,
                                                 routeEvidence: routeEvidence,
                                                 dnsEvidence: dnsEvidence,
                                                 consistency: consistency)
        let recoverySuggestion = runtimeRecoverySuggestion(expectedEnabled: expectedEnabled,
                                                           controllerReportedEnabled: controllerReportedEnabled,
                                                           didFailToReload: didFailToReload,
                                                           interfaceEvidence: interfaceEvidence,
                                                           routeEvidence: routeEvidence,
                                                           dnsEvidence: dnsEvidence)
        return TunRuntimeVerificationReport(expectedEnabled: expectedEnabled,
                                            controllerReportedEnabled: controllerReportedEnabled,
                                            interfaceEvidence: interfaceEvidence,
                                            routeEvidence: routeEvidence,
                                            dnsEvidence: dnsEvidence,
                                            verificationLevels: verificationLevels,
                                            isRuntimeConsistentWithController: consistency,
                                            message: message,
                                            recoverySuggestion: recoverySuggestion)
    }

    static func passiveRuntimeSnapshotReport(controllerReportedEnabled: Bool?,
                                             preflightReport: TunPreflightReport,
                                             interfaceEvidence: TunRuntimeInterfaceEvidence,
                                             routeEvidence: TunRouteRuntimeEvidence,
                                             dnsEvidence: TunDNSRuntimeEvidence) -> TunRuntimeVerificationReport {
        let verificationLevels = runtimeVerificationLevels(interfaceEvidence: interfaceEvidence,
                                                           routeEvidence: routeEvidence,
                                                           dnsEvidence: dnsEvidence)
        let message = passiveRuntimeSnapshotMessage(controllerReportedEnabled: controllerReportedEnabled,
                                                    preflightReport: preflightReport,
                                                    interfaceEvidence: interfaceEvidence,
                                                    routeEvidence: routeEvidence,
                                                    dnsEvidence: dnsEvidence)
        let recoverySuggestion = passiveRuntimeSnapshotRecoverySuggestion(controllerReportedEnabled: controllerReportedEnabled,
                                                                          interfaceEvidence: interfaceEvidence,
                                                                          routeEvidence: routeEvidence,
                                                                          dnsEvidence: dnsEvidence)
        return TunRuntimeVerificationReport(expectedEnabled: controllerReportedEnabled ?? false,
                                            controllerReportedEnabled: controllerReportedEnabled,
                                            interfaceEvidence: interfaceEvidence,
                                            routeEvidence: routeEvidence,
                                            dnsEvidence: dnsEvidence,
                                            verificationLevels: verificationLevels,
                                            isRuntimeConsistentWithController: nil,
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

    private static func runtimeVerificationLevels(interfaceEvidence: TunRuntimeInterfaceEvidence,
                                                  routeEvidence: TunRouteRuntimeEvidence,
                                                  dnsEvidence: TunDNSRuntimeEvidence) -> [TunRuntimeVerificationLevel] {
        var levels = [TunRuntimeVerificationLevel.controllerConfigOnly]
        if interfaceEvidence.evidenceState != .notChecked {
            levels.append(.interfacePresenceOnly)
        }
        if routeEvidence.evidenceState != .notChecked {
            levels.append(.routeVerificationNotImplemented)
        }
        if dnsEvidence.evidenceState != .notChecked {
            levels.append(.dnsRuntimeVerificationNotImplemented)
        }
        levels.append(.packetFlowVerificationNotImplemented)
        return levels
    }

    private static func runtimeConsistency(controllerReportedEnabled: Bool?,
                                           interfaceEvidence: TunRuntimeInterfaceEvidence,
                                           routeEvidence: TunRouteRuntimeEvidence) -> Bool? {
        guard let controllerReportedEnabled else { return nil }

        let positiveInterface = interfaceEvidence.evidenceState == .tunLikeInterfacePresent
        let negativeInterface = interfaceEvidence.evidenceState == .noTunLikeInterface
        let positiveRoute = routeEvidence.evidenceState == .tunLikeRouteEvidencePresent
        let negativeRoute = routeEvidence.evidenceState == .noTunLikeRouteEvidence
        let anyPositive = positiveInterface || positiveRoute
        let anyNegative = negativeInterface || negativeRoute
        let allUnknown = [interfaceEvidence.evidenceState == .notChecked || interfaceEvidence.evidenceState == .unavailable || interfaceEvidence.evidenceState == .inconclusive,
                          routeEvidence.evidenceState == .notChecked || routeEvidence.evidenceState == .unavailable || routeEvidence.evidenceState == .inconclusive]
            .allSatisfy { $0 }

        if allUnknown {
            return nil
        }

        switch (controllerReportedEnabled, anyPositive, anyNegative) {
        case (true, true, _), (false, _, true):
            return true
        case (true, false, true), (false, true, false):
            return false
        default:
            return nil
        }
    }

    private static func runtimeVerificationMessage(expectedEnabled: Bool,
                                                   controllerReportedEnabled: Bool?,
                                                   didFailToReload: Bool,
                                                   preflightReport: TunPreflightReport,
                                                   interfaceEvidence: TunRuntimeInterfaceEvidence,
                                                   routeEvidence: TunRouteRuntimeEvidence,
                                                   dnsEvidence: TunDNSRuntimeEvidence,
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
                                                  routeEvidence: routeEvidence,
                                                  dnsEvidence: dnsEvidence,
                                                  consistency: consistency)

        let verificationLine = "Route evidence is read-only and not packet-flow proof. DNS runtime evidence is read-only and not DNS hijack proof. Packet-flow verification is not implemented."
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
                                                  interfaceEvidence: TunRuntimeInterfaceEvidence,
                                                  routeEvidence: TunRouteRuntimeEvidence,
                                                  dnsEvidence: TunDNSRuntimeEvidence) -> String {
        if didFailToReload {
            return "Refresh controller config, inspect the current core log, and compare the latest tun.enable state with the read-only interface, route, and DNS runtime evidence. Packet-flow verification is not implemented."
        }

        guard let controllerReportedEnabled else {
            return "Re-read /configs when available and compare it with the read-only interface, route, and DNS runtime evidence. Packet-flow verification is not implemented."
        }

        if controllerReportedEnabled != expectedEnabled {
            return "Inspect controller config first, then compare it with the read-only interface, route, and DNS runtime evidence. SmartX will not mutate routes, DNS, or helper state to force runtime alignment."
        }

        if expectedEnabled {
            if interfaceEvidence.evidenceState == .noTunLikeInterface && routeEvidence.evidenceState == .noTunLikeRouteEvidence {
                return "No tun-like interface or route evidence was observed. This does not prove failure; inspect the core log and current controller state before assuming TUN is broken."
            }
            if dnsEvidence.evidenceState == .dnsRuntimeEvidencePresent {
                return "DNS runtime evidence is present, but it is read-only evidence and not DNS hijack proof. Packet-flow verification remains unimplemented."
            }
            return "Treat interface, route, and DNS runtime evidence as supporting evidence only. Packet-flow verification remains future work."
        }

        if interfaceEvidence.evidenceState == .tunLikeInterfacePresent || routeEvidence.evidenceState == .tunLikeRouteEvidencePresent {
            return "Tun-like interface or route evidence remains even though controller config now says tun.enable=false. It may belong to another app or require manual inspection."
        }
        switch dnsEvidence.evidenceState {
        case .dnsRuntimeEvidencePresent:
            return "Controller config now says tun.enable=false, but DNS runtime evidence is still present. That is read-only evidence only and may require manual inspection."
        case .noDNSRuntimeEvidence, .unavailable, .inconclusive, .notChecked:
            return "Runtime interface evidence is unavailable or inconclusive, so only controller config state is confirmed."
        }
    }

    private static func passiveRuntimeSnapshotMessage(controllerReportedEnabled: Bool?,
                                                      preflightReport: TunPreflightReport,
                                                      interfaceEvidence: TunRuntimeInterfaceEvidence,
                                                      routeEvidence: TunRouteRuntimeEvidence,
                                                      dnsEvidence: TunDNSRuntimeEvidence) -> String {
        let base: String
        if let controllerReportedEnabled {
            base = "This is a passive diagnostics snapshot, not a post-toggle verification. Current cached/controller config reports tun.enable=\(controllerReportedEnabled ? "true" : "false"), and that cached/current value may be stale."
        } else {
            base = "This is a passive diagnostics snapshot, not a post-toggle verification. Current cached/controller config did not provide a tun.enable value, and cached/current state may be stale or unavailable."
        }

        let evidenceLine = runtimeEvidenceSummary(expectedEnabled: false,
                                                  controllerReportedEnabled: controllerReportedEnabled,
                                                  interfaceEvidence: interfaceEvidence,
                                                  routeEvidence: routeEvidence,
                                                  dnsEvidence: dnsEvidence,
                                                  consistency: nil)
        let verificationLine = "Interface, route, and DNS runtime evidence are read-only evidence only. Route evidence is not packet-flow proof. DNS runtime evidence is not DNS hijack proof. Packet-flow verification is not implemented."
        let helperLine = preflightReport.helperTunCommandsReserved
            ? "Helper-backed TUN remains reserved only."
            : nil
        return [base, evidenceLine, helperLine, verificationLine]
            .compactMap { $0 }
            .joined(separator: " ")
    }

    private static func passiveRuntimeSnapshotRecoverySuggestion(controllerReportedEnabled: Bool?,
                                                                 interfaceEvidence: TunRuntimeInterfaceEvidence,
                                                                 routeEvidence: TunRouteRuntimeEvidence,
                                                                 dnsEvidence: TunDNSRuntimeEvidence) -> String {
        guard let controllerReportedEnabled else {
            return "Re-read /configs when available and compare it with the read-only interface, route, and DNS runtime evidence. Cached/current state may be stale, and this snapshot does not verify a toggle request."
        }

        if controllerReportedEnabled,
           interfaceEvidence.evidenceState == .noTunLikeInterface,
           routeEvidence.evidenceState == .noTunLikeRouteEvidence {
            return "Cached/controller config currently says tun.enable=true, but cached/current state may be stale and no tun-like interface or route evidence was observed. This is read-only evidence only and does not prove failure."
        }

        if !controllerReportedEnabled,
           interfaceEvidence.evidenceState == .tunLikeInterfacePresent || routeEvidence.evidenceState == .tunLikeRouteEvidencePresent {
            return "Cached/controller config currently says tun.enable=false, but cached/current state may be stale and tun-like interface or route evidence is still present. It may belong to another app or require manual inspection."
        }

        switch dnsEvidence.evidenceState {
        case .dnsRuntimeEvidencePresent:
            return "DNS runtime evidence is present, but cached/current state may be stale and the DNS evidence remains read-only evidence only, not DNS hijack proof. This snapshot does not verify a toggle request."
        case .noDNSRuntimeEvidence, .unavailable, .inconclusive, .notChecked:
            return "Treat interface, route, and DNS runtime evidence as read-only supporting evidence only. Cached/current state may be stale, and this snapshot does not verify a toggle request."
        }
    }

    private static func runtimeEvidenceSummary(expectedEnabled: Bool,
                                               controllerReportedEnabled: Bool?,
                                               interfaceEvidence: TunRuntimeInterfaceEvidence,
                                               routeEvidence: TunRouteRuntimeEvidence,
                                               dnsEvidence: TunDNSRuntimeEvidence,
                                               consistency: Bool?) -> String {
        let interfaceSummary: String = {
            switch interfaceEvidence.evidenceState {
            case .notChecked:
                return "Interface evidence was not checked."
            case .unavailable, .inconclusive:
                return interfaceEvidence.message
            case .tunLikeInterfacePresent:
                let names = interfaceEvidence.tunLikeInterfaceNames.joined(separator: ", ")
                return "Tun-like interface evidence is present: \(names)."
            case .noTunLikeInterface:
                return "No tun-like interface evidence was observed."
            }
        }()

        let routeSummary: String = {
            switch routeEvidence.evidenceState {
            case .notChecked:
                return "Route evidence was not checked."
            case .unavailable, .inconclusive, .noTunLikeRouteEvidence, .tunLikeRouteEvidencePresent:
                return routeEvidence.message
            }
        }()

        let dnsSummary: String = {
            switch dnsEvidence.evidenceState {
            case .notChecked:
                return "DNS runtime evidence was not checked."
            case .unavailable, .inconclusive, .noDNSRuntimeEvidence, .dnsRuntimeEvidencePresent:
                return dnsEvidence.message
            }
        }()

        if controllerReportedEnabled == true || expectedEnabled,
           interfaceEvidence.evidenceState == .noTunLikeInterface,
           routeEvidence.evidenceState == .noTunLikeRouteEvidence {
            return "No tun-like interface or route evidence was observed. This does not prove failure; inspect the core log and current controller state. \(dnsSummary)"
        }

        if controllerReportedEnabled == false,
           interfaceEvidence.evidenceState == .tunLikeInterfacePresent || routeEvidence.evidenceState == .tunLikeRouteEvidencePresent {
            return "Tun-like interface or route evidence remains even though controller config now says tun.enable=false. It may belong to another app or require manual inspection. \(dnsSummary)"
        }

        if consistency == true, controllerReportedEnabled == false {
            return "\(interfaceSummary) \(routeSummary) \(dnsSummary)"
        }

        return "\(interfaceSummary) \(routeSummary) \(dnsSummary)"
    }

    private static func ordered(_ blockers: [TunPreflightBlocker]) -> [TunPreflightBlocker] {
        TunPreflightBlocker.allCases.filter { blockers.contains($0) }
    }

    private static func deduplicated(_ warnings: [String]) -> [String] {
        var seen = Set<String>()
        return warnings.filter { seen.insert($0).inserted }
    }
}
