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
                                   preflightReport: TunPreflightReport) -> TunLifecycleVerificationReport {
        if didFailToReload {
            return TunLifecycleVerificationReport(expectedEnabled: expectedEnabled,
                                                  outcome: .requestedButUnverified,
                                                  verificationScope: .controllerConfigOnly,
                                                  controllerReportedEnabled: nil,
                                                  message: "SmartX sent the controller TUN update request, but could only keep controller-config verification at an unverified state. System-level TUN verification is not implemented.",
                                                  recoverySuggestion: "Refresh the controller config, review the reported tun.enable state, and remember that helper-backed TUN and system-level verification remain future work.")
        }

        guard let controllerReportedEnabled else {
            return TunLifecycleVerificationReport(expectedEnabled: expectedEnabled,
                                                  outcome: .failed,
                                                  verificationScope: preflightReport.verificationScope,
                                                  controllerReportedEnabled: nil,
                                                  message: "SmartX could not read a controller-config TUN state after the request. System-level TUN verification is not implemented.",
                                                  recoverySuggestion: "Re-read /configs when available. SmartX currently verifies only controller config state, not utun, route, or DNS runtime state.")
        }

        if controllerReportedEnabled == expectedEnabled {
            return TunLifecycleVerificationReport(expectedEnabled: expectedEnabled,
                                                  outcome: .controllerStateMatches,
                                                  verificationScope: .controllerConfigOnly,
                                                  controllerReportedEnabled: controllerReportedEnabled,
                                                  message: "SmartX verified that controller config state matches the requested tun.enable value. This remains controller-config verification only. System-level TUN verification is not implemented.",
                                                  recoverySuggestion: "Treat this as a controller-config match only. Helper-backed TUN, route checks, DNS runtime checks, and utun verification remain future work.")
        }

        return TunLifecycleVerificationReport(expectedEnabled: expectedEnabled,
                                              outcome: .controllerStateMismatch,
                                              verificationScope: .controllerConfigOnly,
                                              controllerReportedEnabled: controllerReportedEnabled,
                                              message: "SmartX requested a TUN update, but the controller reported a different tun.enable value after reload. System-level TUN verification is not implemented.",
                                              recoverySuggestion: "Inspect the current controller config and retry after fixing validation issues. SmartX does not perform route, interface, or DNS runtime verification.")
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

    private static func ordered(_ blockers: [TunPreflightBlocker]) -> [TunPreflightBlocker] {
        TunPreflightBlocker.allCases.filter { blockers.contains($0) }
    }

    private static func deduplicated(_ warnings: [String]) -> [String] {
        var seen = Set<String>()
        return warnings.filter { seen.insert($0).inserted }
    }
}
