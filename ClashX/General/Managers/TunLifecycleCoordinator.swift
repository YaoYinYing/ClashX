//
//  TunLifecycleCoordinator.swift
//  ClashX
//
//  Created by Codex on 2026/5/4.
//

import Foundation

struct TunLifecycleUIState {
    let enabled: Bool
}

private struct TunLifecycleLoadError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}

enum TunLifecycleResult {
    case success(message: String, previousState: TunLifecycleUIState)
    case requestedButUnverified(message: String, previousState: TunLifecycleUIState)
    case unsupported(message: String, previousState: TunLifecycleUIState)
    case unauthorized(message: String, previousState: TunLifecycleUIState)
    case blockedByValidation(issues: [ConfigValidationIssue], recoveryText: String, previousState: TunLifecycleUIState)
    case failed(message: String, previousState: TunLifecycleUIState)

    var previousState: TunLifecycleUIState {
        switch self {
        case let .success(_, previousState),
             let .requestedButUnverified(_, previousState),
             let .unsupported(_, previousState),
             let .unauthorized(_, previousState),
             let .blockedByValidation(_, _, previousState),
             let .failed(_, previousState):
            return previousState
        }
    }

    var recoveryText: String {
        switch self {
        case let .success(message, _),
             let .requestedButUnverified(message, _),
             let .unsupported(message, _),
             let .unauthorized(message, _),
             let .failed(message, _):
            return message
        case let .blockedByValidation(_, recoveryText, _):
            return recoveryText
        }
    }
}

final class TunLifecycleCoordinator {
    func setTunEnabled(_ enabled: Bool, completion: @escaping (TunLifecycleResult) -> Void) {
        let fallbackPreviousState = TunLifecycleUIState(enabled: ConfigManager.shared.currentConfig?.tun?.enable ?? false)
        let helperStatus = HelperDiagnosticsProbe.currentStatus()
        let helperTunDescriptors = HelperCommandRegistry.reservedTunDescriptors()
        let configPatchAvailability = CapabilityCache.shared.status(for: .configPatch)?.availability ?? .unknown

        let initialReport = TunPreflightPlanner.buildReport(config: ConfigManager.shared.currentConfig,
                                                            isControllerRunning: ConfigManager.shared.isRunning,
                                                            isUsingEmbeddedCore: Settings.isUsingEmbeddedCore,
                                                            configPatchAvailability: configPatchAvailability,
                                                            helperStatus: helperStatus,
                                                            helperTunDescriptors: helperTunDescriptors)

        guard ConfigManager.shared.isRunning else {
            completion(.failed(message: initialReport.userMessage,
                               previousState: fallbackPreviousState))
            return
        }

        guard !Settings.isUsingEmbeddedCore else {
            completion(.unsupported(message: initialReport.userMessage,
                                    previousState: fallbackPreviousState))
            return
        }

        loadCurrentConfig { result in
            switch result {
            case let .failure(error):
                completion(.failed(message: error.localizedDescription, previousState: fallbackPreviousState))
            case let .success(config):
                let previousState = TunLifecycleUIState(enabled: config.tun?.enable ?? fallbackPreviousState.enabled)
                let preflight = TunPreflightPlanner.buildReport(config: config,
                                                                isControllerRunning: ConfigManager.shared.isRunning,
                                                                isUsingEmbeddedCore: Settings.isUsingEmbeddedCore,
                                                                configPatchAvailability: configPatchAvailability,
                                                                helperStatus: helperStatus,
                                                                helperTunDescriptors: helperTunDescriptors)

                if preflight.blockers.contains(.tunSectionMissing) {
                    completion(.unsupported(message: preflight.userMessage, previousState: previousState))
                    return
                }

                if enabled {
                    let blockingIssues = TunConfigValidator.validate(config.tun).blockingErrors
                        + DNSConfigValidator.validate(config.dns).issues.filter { $0.severity == .blocking }
                    if !blockingIssues.isEmpty {
                        completion(.blockedByValidation(issues: blockingIssues,
                                                        recoveryText: preflight.recoverySuggestion,
                                                        previousState: previousState))
                        return
                    }
                }

                if preflight.blockers.contains(.configPatchUnsupported) {
                    completion(.unsupported(message: preflight.userMessage, previousState: previousState))
                    return
                }
                if preflight.blockers.contains(.controllerUnauthorized) {
                    completion(.unauthorized(message: preflight.userMessage, previousState: previousState))
                    return
                }

                ApiRequest.updateTunResult(enable: enabled) { endpointResult in
                    switch endpointResult {
                    case .success:
                        self.verifyTunState(expected: enabled,
                                            preflightReport: preflight,
                                            previousState: previousState,
                                            completion: completion)
                    case .unsupported:
                        completion(.unsupported(message: preflight.userMessage, previousState: previousState))
                    case let .unauthorized(message):
                        completion(.unauthorized(message: [message, preflight.recoverySuggestion].joined(separator: " "),
                                                 previousState: previousState))
                    case let .failed(message):
                        completion(.failed(message: [message, preflight.recoverySuggestion].joined(separator: " "),
                                           previousState: previousState))
                    }
                }
            }
        }
    }

    private func loadCurrentConfig(completion: @escaping (Result<ClashConfig, TunLifecycleLoadError>) -> Void) {
        if ApiRequest.useDirectApi(), let config = ConfigManager.shared.currentConfig {
            completion(.success(config))
            return
        }

        ApiRequest.requestControllerConfig { result in
            switch result {
            case let .success(config):
                completion(.success(config))
            case .unsupported:
                completion(.failure(TunLifecycleLoadError(message: NSLocalizedString("/configs is unsupported by the active controller.", comment: ""))))
            case let .unauthorized(message), let .failed(message):
                completion(.failure(TunLifecycleLoadError(message: message)))
            }
        }
    }

    private func verifyTunState(expected: Bool,
                                preflightReport: TunPreflightReport,
                                previousState: TunLifecycleUIState,
                                completion: @escaping (TunLifecycleResult) -> Void) {
        loadCurrentConfig { result in
            switch result {
            case .failure:
                let interfaceEvidence = TunRuntimeInterfaceProbe.currentEvidence()
                let routeEvidence = TunRuntimeRouteProbe.currentEvidence(tunLikeInterfaceNames: interfaceEvidence.tunLikeInterfaceNames)
                let dnsEvidence = TunRuntimeDNSProbe.currentEvidence()
                let report = TunPreflightPlanner.verificationReport(expectedEnabled: expected,
                                                                    controllerReportedEnabled: nil,
                                                                    didFailToReload: true,
                                                                    preflightReport: preflightReport,
                                                                    interfaceEvidence: interfaceEvidence,
                                                                    routeEvidence: routeEvidence,
                                                                    dnsEvidence: dnsEvidence)
                completion(.requestedButUnverified(message: report.message,
                                                   previousState: previousState))
            case let .success(config):
                ConfigManager.shared.currentConfig = config
                let interfaceEvidence = TunRuntimeInterfaceProbe.currentEvidence()
                let routeEvidence = TunRuntimeRouteProbe.currentEvidence(tunLikeInterfaceNames: interfaceEvidence.tunLikeInterfaceNames)
                let dnsEvidence = TunRuntimeDNSProbe.currentEvidence()
                let report = TunPreflightPlanner.verificationReport(expectedEnabled: expected,
                                                                    controllerReportedEnabled: config.tun?.enable,
                                                                    didFailToReload: false,
                                                                    preflightReport: preflightReport,
                                                                    interfaceEvidence: interfaceEvidence,
                                                                    routeEvidence: routeEvidence,
                                                                    dnsEvidence: dnsEvidence)
                switch report.outcome {
                case .controllerStateMatches:
                    completion(.success(message: report.message, previousState: previousState))
                case .controllerStateMismatch, .failed:
                    completion(.failed(message: report.message, previousState: previousState))
                case .requestedButUnverified:
                    completion(.requestedButUnverified(message: report.message, previousState: previousState))
                case .notAttempted:
                    completion(.failed(message: report.message, previousState: previousState))
                }
            }
        }
    }
}
