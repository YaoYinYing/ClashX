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
                .debugGC: .unavailable
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
                    assign(.configPatch, .available)
                    if config.tun == nil {
                        assign(.tunConfigRead, .unsupported)
                        assign(.tunGuardedUpdate, .unsupported)
                    } else {
                        assign(.tunConfigRead, .available)
                        assign(.tunGuardedUpdate, Settings.isUsingEmbeddedCore ? .unsupported : .available)
                    }
                case .unsupported:
                    assign(.configRead, .unsupported)
                    assign(.tunConfigRead, .unsupported)
                    assign(.tunGuardedUpdate, .unsupported)
                case let .unauthorized(message):
                    assign(.configRead, .unauthorized, message: message)
                    assign(.tunConfigRead, .unauthorized, message: message)
                    assign(.tunGuardedUpdate, .unauthorized, message: message)
                case let .failed(message):
                    assign(.configRead, .degraded, message: message)
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
