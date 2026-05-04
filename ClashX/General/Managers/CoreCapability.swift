//
//  CoreCapability.swift
//  ClashX
//
//  Created by Codex on 2026/5/2.
//

import Foundation

enum CoreCapability: String, CaseIterable {
    case versionRead
    case configRead
    case configPatch
    case configReload
    case proxyProviders
    case ruleProviders
    case logsStream
    case trafficStream
    case memorySnapshot
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

    private let queue = DispatchQueue(label: "com.smartx.capability.cache")
    private var controllerIdentity = ""
    private var statuses = [CoreCapability: CoreCapabilityStatus]()
    private var latestSnapshot: CoreCapabilitySnapshot?

    private init() {}

    private func activeIdentity() -> String {
        let mode = Settings.isUsingEmbeddedCore ? "embedded" : "external"
        let running = ConfigManager.shared.isRunning ? "running" : "stopped"
        let secret = ConfigManager.shared.overrideSecret ?? ConfigManager.shared.apiSecret
        let secretState = secretIdentityComponent(secret)
        return [mode, running, ControllerEndpointBuilder.sanitizedControllerIdentityBaseString(), secretState].joined(separator: "|")
    }

    // This is only a stable cache-identity discriminator. It is intentionally
    // non-reversible, but it is not a security primitive.
    private func secretIdentityComponent(_ secret: String) -> String {
        guard !secret.isEmpty else { return "no-secret" }

        var hash: UInt64 = 0xcbf29ce484222325
        for byte in secret.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(format: "secret-fnv1a64-%016llx", hash)
    }

    private func synchronizeIdentity() {
        let identity = activeIdentity()
        guard controllerIdentity != identity else { return }
        controllerIdentity = identity
        statuses.removeAll()
        latestSnapshot = nil
    }

    func reset() {
        queue.sync {
            synchronizeIdentity()
            statuses.removeAll()
            latestSnapshot = nil
        }
    }

    func status(for capability: CoreCapability) -> CoreCapabilityStatus? {
        queue.sync {
            synchronizeIdentity()
            return statuses[capability]
        }
    }

    func availability(for capability: CoreCapability) -> CoreEndpointAvailability {
        queue.sync {
            synchronizeIdentity()
            return statuses[capability]?.availability ?? .unknown
        }
    }

    func message(for capability: CoreCapability) -> String? {
        queue.sync {
            synchronizeIdentity()
            return statuses[capability]?.message
        }
    }

    func snapshot() -> CoreCapabilitySnapshot? {
        queue.sync {
            synchronizeIdentity()
            return latestSnapshot
        }
    }

    func set(_ capability: CoreCapability, availability: CoreEndpointAvailability, message: String? = nil) {
        queue.sync {
            synchronizeIdentity()
            statuses[capability] = CoreCapabilityStatus(availability: availability, message: message, updatedAt: Date())
        }
    }

    func apply(snapshot: CoreCapabilitySnapshot) {
        queue.sync {
            synchronizeIdentity()
            guard snapshot.controllerIdentity == controllerIdentity else { return }
            latestSnapshot = snapshot
            statuses = snapshot.statuses
        }
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

    func currentControllerIdentityForTesting() -> String {
        queue.sync {
            synchronizeIdentity()
            return controllerIdentity
        }
    }
}
