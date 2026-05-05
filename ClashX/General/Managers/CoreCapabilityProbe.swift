//
//  CoreCapabilityProbe.swift
//  ClashX
//
//  Created by Codex on 2026/5/3.
//

import Foundation

struct CoreCapabilitySnapshot {
    let controllerIdentity: String
    let mode: String
    let running: Bool
    let coreVersion: String?
    let statuses: [CoreCapability: CoreCapabilityStatus]
    let probedAt: Date
}

final class CoreCapabilityProbe {
    static let shared = CoreCapabilityProbe()

    private init() {}

    func probeCurrentController(completion: @escaping (CoreCapabilitySnapshot) -> Void) {
        let identity = CapabilityCache.shared.currentControllerIdentityForTesting()
        let mode = Settings.isUsingEmbeddedCore ? "embedded" : "external"
        let probedAt = Date()

        guard ConfigManager.shared.isRunning else {
            let message = NSLocalizedString("Core is stopped or controller is unavailable.", comment: "")
            let statuses = baselineStatuses(probedAt: probedAt, defaults: [
                .versionRead: .unavailable,
                .configRead: .unavailable,
                .proxyProviders: .unavailable,
                .ruleProviders: .unavailable,
                .memorySnapshot: .unavailable,
                .tunConfigRead: .unavailable,
                .configPatch: .unavailable,
                .tunGuardedUpdate: .unavailable,
                .dnsCacheFlush: .unavailable,
                .dnsQuery: .unavailable,
                .geoUpdate: .unavailable,
                .uiUpgrade: .unavailable,
                .restart: .unavailable,
                .debugGC: .unavailable,
                .smartWeights: .unavailable,
                .smartCacheFlush: .unavailable,
                .smartConnectionBlock: .unavailable,
                .lightGBMUpgrade: .unavailable
            ], message: message)
            let snapshot = CoreCapabilitySnapshot(controllerIdentity: identity,
                                                  mode: mode,
                                                  running: false,
                                                  coreVersion: nil,
                                                  statuses: statuses,
                                                  probedAt: probedAt)
            CapabilityCache.shared.apply(snapshot: snapshot)
            completion(snapshot)
            return
        }

        let group = DispatchGroup()
        let queue = DispatchQueue(label: "com.smartx.capability.probe", attributes: .concurrent)
        let stateQueue = DispatchQueue(label: "com.smartx.capability.probe.state")
        var statuses = baselineStatuses(probedAt: probedAt)
        var coreVersion: String?

        func assign(_ capability: CoreCapability, _ availability: CoreEndpointAvailability, message: String? = nil) {
            stateQueue.sync {
                statuses[capability] = CoreCapabilityStatus(availability: availability, message: message, updatedAt: probedAt)
            }
        }

        group.enter()
        queue.async {
            ApiRequest.requestCoreVersionResult { result in
                switch result {
                case let .success(info):
                    stateQueue.sync {
                        coreVersion = info.version
                    }
                    assign(.versionRead, .available, message: NSLocalizedString("/version responded successfully.", comment: ""))
                case .unsupported:
                    assign(.versionRead, .unsupported)
                case let .unauthorized(message):
                    assign(.versionRead, .unauthorized, message: message)
                case let .failed(message):
                    assign(.versionRead, .degraded, message: message)
                }
                group.leave()
            }
        }

        group.enter()
        queue.async {
            ApiRequest.requestControllerConfig { result in
                switch result {
                case let .success(config):
                    assign(.configRead, .available, message: NSLocalizedString("Loaded config state from /configs.", comment: ""))
                    assign(.configPatch, .unknown, message: NSLocalizedString("PATCH /configs is intentionally not auto-probed because it mutates controller state.", comment: ""))
                    assign(.configReload, .unknown, message: NSLocalizedString("Config reload is intentionally not auto-probed because it mutates controller state.", comment: ""))
                    if config.tun == nil {
                        assign(.tunConfigRead, .unsupported)
                        assign(.tunGuardedUpdate, .unsupported)
                    } else {
                        assign(.tunConfigRead, .available)
                        if Settings.isUsingEmbeddedCore {
                            assign(.tunGuardedUpdate, .unsupported, message: NSLocalizedString("Embedded-core TUN is still unsupported in SmartX.", comment: ""))
                        } else {
                            assign(.tunGuardedUpdate, .unknown, message: NSLocalizedString("Guarded TUN update is available only after an explicit user-triggered config patch; SmartX does not auto-probe it.", comment: ""))
                        }
                    }
                case .unsupported:
                    assign(.configRead, .unsupported)
                    assign(.configPatch, .unsupported)
                    assign(.configReload, .unsupported)
                    assign(.tunConfigRead, .unsupported)
                    assign(.tunGuardedUpdate, .unsupported)
                case let .unauthorized(message):
                    assign(.configRead, .unauthorized, message: message)
                    assign(.configPatch, .unauthorized, message: message)
                    assign(.configReload, .unauthorized, message: message)
                    assign(.tunConfigRead, .unauthorized, message: message)
                    assign(.tunGuardedUpdate, .unauthorized, message: message)
                case let .failed(message):
                    assign(.configRead, .degraded, message: message)
                    assign(.configPatch, .degraded, message: message)
                    assign(.configReload, .degraded, message: message)
                    assign(.tunConfigRead, .degraded, message: message)
                    assign(.tunGuardedUpdate, .degraded, message: message)
                }
                group.leave()
            }
        }

        group.enter()
        queue.async {
            ApiRequest.requestProxyProvidersDiagnostics { [self] result in
                assignCapability(.proxyProviders, from: result, assign: assign)
                group.leave()
            }
        }

        group.enter()
        queue.async {
            ApiRequest.requestRuleProvidersDiagnostics { [self] result in
                assignCapability(.ruleProviders, from: result, assign: assign)
                group.leave()
            }
        }

        group.enter()
        queue.async {
            ApiRequest.requestMemorySnapshot { [self] result in
                assignCapability(.memorySnapshot, from: result, assign: assign)
                group.leave()
            }
        }

        group.enter()
        queue.async {
            SmartAPI.requestSmartWeights { [self] result in
                switch result {
                case let .success(response):
                    let weightCount = response.weights.values.reduce(0) { $0 + $1.count }
                    let message: String
                    if response.weights.isEmpty {
                        message = NSLocalizedString("Smart weight endpoint responded successfully, but no Smart weight entries were reported.", comment: "")
                    } else {
                        message = String(format: NSLocalizedString("Smart weight endpoint responded successfully with %d weight entries.", comment: ""), weightCount)
                    }
                    assign(.smartWeights, .available, message: message)
                    assign(.smartCacheFlush, .unknown, message: NSLocalizedString("Smart cache flush is intentionally not auto-probed because it mutates controller state.", comment: ""))
                    assign(.smartConnectionBlock, .unknown, message: NSLocalizedString("Smart connection block is intentionally not auto-probed because it mutates controller state.", comment: ""))
                    assign(.lightGBMUpgrade, .unknown, message: NSLocalizedString("LightGBM model upgrade is intentionally not auto-probed because it mutates controller state.", comment: ""))
                case .unsupported:
                    assign(.smartWeights, .unsupported, message: NSLocalizedString("Smart endpoints are unsupported by the active controller.", comment: ""))
                    assign(.smartCacheFlush, .unsupported, message: NSLocalizedString("Smart endpoints are unsupported by the active controller.", comment: ""))
                    assign(.smartConnectionBlock, .unsupported, message: NSLocalizedString("Smart endpoints are unsupported by the active controller.", comment: ""))
                    assign(.lightGBMUpgrade, .unsupported, message: NSLocalizedString("Smart endpoints are unsupported by the active controller.", comment: ""))
                case let .unauthorized(message):
                    assign(.smartWeights, .unauthorized, message: message)
                    assign(.smartCacheFlush, .unauthorized, message: message)
                    assign(.smartConnectionBlock, .unauthorized, message: message)
                    assign(.lightGBMUpgrade, .unauthorized, message: message)
                case let .failed(message):
                    assign(.smartWeights, .degraded, message: message)
                    assign(.smartCacheFlush, .unknown, message: NSLocalizedString("Smart cache flush was not auto-probed after Smart weight probing degraded.", comment: ""))
                    assign(.smartConnectionBlock, .unknown, message: NSLocalizedString("Smart connection block was not auto-probed after Smart weight probing degraded.", comment: ""))
                    assign(.lightGBMUpgrade, .unknown, message: NSLocalizedString("LightGBM upgrade was not auto-probed after Smart weight probing degraded.", comment: ""))
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            let snapshot = CoreCapabilitySnapshot(controllerIdentity: identity,
                                                  mode: mode,
                                                  running: true,
                                                  coreVersion: coreVersion,
                                                  statuses: stateQueue.sync { statuses },
                                                  probedAt: probedAt)
            CapabilityCache.shared.apply(snapshot: snapshot)
            completion(snapshot)
        }
    }

    private func baselineStatuses(probedAt: Date, defaults: [CoreCapability: CoreEndpointAvailability] = [:], message: String? = nil) -> [CoreCapability: CoreCapabilityStatus] {
        var statuses = [CoreCapability: CoreCapabilityStatus]()
        for capability in CoreCapability.allCases {
            let availability = defaults[capability] ?? .unknown
            statuses[capability] = CoreCapabilityStatus(availability: availability, message: message, updatedAt: probedAt)
        }
        return statuses
    }

    private func assignCapability(_ capability: CoreCapability,
                                  from result: ControllerJSONResult,
                                  assign: (CoreCapability, CoreEndpointAvailability, String?) -> Void) {
        switch result {
        case .success:
            assign(capability, .available, nil)
        case .unsupported:
            assign(capability, .unsupported, nil)
        case let .unauthorized(message):
            assign(capability, .unauthorized, message)
        case let .failed(message):
            assign(capability, .degraded, message)
        }
    }
}
