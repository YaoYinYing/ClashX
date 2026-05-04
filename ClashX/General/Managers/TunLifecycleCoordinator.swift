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
    case unsupported(message: String, previousState: TunLifecycleUIState)
    case unauthorized(message: String, previousState: TunLifecycleUIState)
    case blockedByValidation(issues: [ConfigValidationIssue], recoveryText: String, previousState: TunLifecycleUIState)
    case failed(message: String, previousState: TunLifecycleUIState)

    var previousState: TunLifecycleUIState {
        switch self {
        case let .success(_, previousState),
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

        guard ConfigManager.shared.isRunning else {
            completion(.failed(message: NSLocalizedString("The active controller is not running, so SmartX cannot attempt a TUN update.", comment: ""),
                               previousState: fallbackPreviousState))
            return
        }

        guard !Settings.isUsingEmbeddedCore else {
            completion(.unsupported(message: NSLocalizedString("Embedded core TUN cannot be enabled from SmartX yet. It requires a privileged core startup path or another TUN-capable architecture.", comment: ""),
                                    previousState: fallbackPreviousState))
            return
        }

        loadCurrentConfig { result in
            switch result {
            case let .failure(error):
                completion(.failed(message: error.localizedDescription, previousState: fallbackPreviousState))
            case let .success(config):
                let previousState = TunLifecycleUIState(enabled: config.tun?.enable ?? fallbackPreviousState.enabled)
                guard config.tun != nil else {
                    completion(.unsupported(message: NSLocalizedString("The current controller config does not expose a tun section, so SmartX keeps TUN disabled.", comment: ""),
                                            previousState: previousState))
                    return
                }

                if enabled {
                    let tunValidation = TunConfigValidator.validate(config.tun)
                    let dnsValidation = DNSConfigValidator.validate(config.dns)
                    let blockingIssues = tunValidation.blockingErrors + dnsValidation.issues.filter { $0.severity == .blocking }
                    if !blockingIssues.isEmpty {
                        completion(.blockedByValidation(issues: blockingIssues,
                                                        recoveryText: NSLocalizedString("SmartX blocked the TUN update because the current config has blocking validation issues. SmartX will restore the previous UI state, but it does not roll back controller state automatically. Review the warnings on the Core settings page, fix the config, and try again.", comment: ""),
                                                        previousState: previousState))
                        return
                    }
                }

                ApiRequest.updateTunResult(enable: enabled) { endpointResult in
                    switch endpointResult {
                    case .success:
                        self.verifyTunState(expected: enabled, previousState: previousState, completion: completion)
                    case .unsupported:
                        completion(.unsupported(message: NSLocalizedString("The active controller does not support guarded TUN updates.", comment: ""),
                                                previousState: previousState))
                    case let .unauthorized(message):
                        completion(.unauthorized(message: message, previousState: previousState))
                    case let .failed(message):
                        completion(.failed(message: message, previousState: previousState))
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
                                previousState: TunLifecycleUIState,
                                completion: @escaping (TunLifecycleResult) -> Void) {
        loadCurrentConfig { result in
            switch result {
            case .failure:
                completion(.success(message: NSLocalizedString("SmartX requested the TUN update successfully, but could not verify the new controller state.", comment: ""),
                                    previousState: previousState))
            case let .success(config):
                ConfigManager.shared.currentConfig = config
                if config.tun?.enable == expected {
                    completion(.success(message: NSLocalizedString("SmartX updated the controller TUN state successfully.", comment: ""),
                                        previousState: previousState))
                } else {
                    completion(.failed(message: NSLocalizedString("SmartX requested a TUN update, but the controller reported a different final state after reload.", comment: ""),
                                       previousState: previousState))
                }
            }
        }
    }
}
