//
//  CoreCapability.swift
//  ClashX
//
//  Created by Codex on 2026/5/2.
//

import Foundation

enum CoreCapability: String, CaseIterable {
    case configRead
    case configPatch
    case configReload
    case proxyProviders
    case ruleProviders
    case logsStream
    case trafficStream
    case memoryStream
    case tunConfigRead
    case tunGuardedUpdate
    case smartWeights
    case smartCacheFlush
    case smartConnectionBlock
    case lightGBMUpgrade
    case dnsCacheFlush
    case dnsQuery
    case geoUpdate
    case uiUpgrade
    case restart
    case debugGC
    case debugPprof
}

enum CoreEndpointAvailability {
    case available
    case unavailable
    case unauthorized
    case unsupported
    case unknown
    case degraded
}

struct CoreCapabilityStatus {
    var availability: CoreEndpointAvailability
    var message: String?
    var updatedAt: Date
}

final class CapabilityCache {
    static let shared = CapabilityCache()

    private var controllerIdentity = ""
    private var statuses = [CoreCapability: CoreCapabilityStatus]()

    private init() {}

    private func activeIdentity() -> String {
        let mode = Settings.isUsingEmbeddedCore ? "embedded" : "external"
        let running = ConfigManager.shared.isRunning ? "running" : "stopped"
        let secret = ConfigManager.shared.overrideSecret ?? ConfigManager.shared.apiSecret
        return [mode, running, ConfigManager.apiUrl, secret].joined(separator: "|")
    }

    private func synchronizeIdentity() {
        let identity = activeIdentity()
        guard controllerIdentity != identity else { return }
        controllerIdentity = identity
        statuses.removeAll()
    }

    func reset() {
        synchronizeIdentity()
        statuses.removeAll()
    }

    func status(for capability: CoreCapability) -> CoreCapabilityStatus? {
        synchronizeIdentity()
        return statuses[capability]
    }

    func availability(for capability: CoreCapability) -> CoreEndpointAvailability {
        synchronizeIdentity()
        return statuses[capability]?.availability ?? .unknown
    }

    func message(for capability: CoreCapability) -> String? {
        synchronizeIdentity()
        return statuses[capability]?.message
    }

    func set(_ capability: CoreCapability, availability: CoreEndpointAvailability, message: String? = nil) {
        synchronizeIdentity()
        statuses[capability] = CoreCapabilityStatus(availability: availability, message: message, updatedAt: Date())
    }

    func mark(_ capability: CoreCapability, endpointResult: ControllerEndpointResult, successMessage: String? = nil) {
        switch endpointResult {
        case .success:
            set(capability, availability: .available, message: successMessage)
        case .unsupported:
            set(capability, availability: .unsupported)
        case let .unauthorized(message):
            set(capability, availability: .unauthorized, message: message)
        case let .failed(message):
            set(capability, availability: .degraded, message: message)
        }
    }

    func mark(_ capability: CoreCapability, jsonResult: ControllerJSONResult, successMessage: String? = nil) {
        switch jsonResult {
        case .success:
            set(capability, availability: .available, message: successMessage)
        case .unsupported:
            set(capability, availability: .unsupported)
        case let .unauthorized(message):
            set(capability, availability: .unauthorized, message: message)
        case let .failed(message):
            set(capability, availability: .degraded, message: message)
        }
    }

    func markUnavailable(_ capability: CoreCapability, message: String? = nil) {
        set(capability, availability: .unavailable, message: message)
    }
}
