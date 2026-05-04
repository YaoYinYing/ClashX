//
//  LightGBMSettingsViewModel.swift
//  ClashX
//
//  Created by Codex on 2026/5/4.
//

import Foundation

struct LightGBMSettingsState {
    let overrideEnabled: Bool
    let autoUpdateEnabled: Bool
    let modelURL: String
    let updateIntervalHours: Int
    let modelPath: String
    let modelStatusText: String
    let modelModifiedText: String
    let overrideSummaryText: String
    let manualUpdateText: String
}

enum LightGBMSettingsUpdateResult {
    case success
    case unsupported
    case unauthorized(String)
    case failed(String)
}

enum LightGBMSettingsViewModel {
    static let overrideExplanation = NSLocalizedString("This override is stored by SmartX. It is not written into remote subscription files. Full generated effective config support is planned.", comment: "")

    static func currentState(isCoreRunning: Bool, capabilityAvailability: CoreEndpointAvailability) -> LightGBMSettingsState {
        SmartXManagedOverrideManager.bootstrapIfNeeded()

        let path = Paths.smartLightGBMModelPath
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)

        let modelStatusText: String
        let modelModifiedText: String
        if let size = attributes?[.size] as? NSNumber {
            modelStatusText = String(format: NSLocalizedString("present (%@)", comment: ""),
                                     ByteCountFormatter.string(fromByteCount: size.int64Value, countStyle: .file))
            if let modified = attributes?[.modificationDate] as? Date {
                modelModifiedText = DateFormatter.localizedString(from: modified, dateStyle: .short, timeStyle: .medium)
            } else {
                modelModifiedText = NSLocalizedString("unknown", comment: "")
            }
        } else {
            modelStatusText = NSLocalizedString("missing", comment: "")
            modelModifiedText = NSLocalizedString("not available", comment: "")
        }

        let overrideStatus = Settings.smartLightGBMOverrideConfig ? NSLocalizedString("enabled", comment: "") : NSLocalizedString("disabled", comment: "")
        let autoUpdateStatus = Settings.smartLightGBMAutoUpdate ? NSLocalizedString("auto update on", comment: "") : NSLocalizedString("auto update off", comment: "")
        let manualUpdateText = manualUpdateSummary(isCoreRunning: isCoreRunning, capabilityAvailability: capabilityAvailability)

        return LightGBMSettingsState(overrideEnabled: Settings.smartLightGBMOverrideConfig,
                                     autoUpdateEnabled: Settings.smartLightGBMAutoUpdate,
                                     modelURL: Settings.effectiveSmartLightGBMModelUrl,
                                     updateIntervalHours: Settings.smartLightGBMUpdateIntervalHours,
                                     modelPath: path,
                                     modelStatusText: modelStatusText,
                                     modelModifiedText: modelModifiedText,
                                     overrideSummaryText: "\(overrideStatus), \(autoUpdateStatus), \(Settings.smartLightGBMUpdateIntervalHours)h",
                                     manualUpdateText: manualUpdateText)
    }

    static func save(overrideEnabled: Bool,
                     modelURL: String,
                     autoUpdate: Bool,
                     updateIntervalHours: Int,
                     isCoreRunning: Bool,
                     capabilityAvailability: CoreEndpointAvailability) -> LightGBMSettingsState {
        SmartXManagedOverrideManager.bootstrapIfNeeded()

        Settings.smartLightGBMOverrideConfig = overrideEnabled
        Settings.smartLightGBMAutoUpdate = autoUpdate
        Settings.smartLightGBMModelUrl = modelURL
        Settings.smartLightGBMUpdateIntervalHours = max(1, updateIntervalHours)
        SmartXManagedOverrideManager.persistCurrentSettings()
        Settings.syncSmartLightGBMOptionsToCore()

        return currentState(isCoreRunning: isCoreRunning, capabilityAvailability: capabilityAvailability)
    }

    static func resetModelURL(isCoreRunning: Bool, capabilityAvailability: CoreEndpointAvailability) -> LightGBMSettingsState {
        save(overrideEnabled: Settings.smartLightGBMOverrideConfig,
             modelURL: Settings.defaultSmartLightGBMModelUrl,
             autoUpdate: Settings.smartLightGBMAutoUpdate,
             updateIntervalHours: Settings.smartLightGBMUpdateIntervalHours,
             isCoreRunning: isCoreRunning,
             capabilityAvailability: capabilityAvailability)
    }

    static func requestModelUpdate(overrideEnabled: Bool,
                                   modelURL: String,
                                   autoUpdate: Bool,
                                   updateIntervalHours: Int,
                                   isCoreRunning: Bool,
                                   completion: @escaping (LightGBMSettingsUpdateResult, LightGBMSettingsState) -> Void) {
        let initialState = save(overrideEnabled: overrideEnabled,
                                modelURL: modelURL,
                                autoUpdate: autoUpdate,
                                updateIntervalHours: updateIntervalHours,
                                isCoreRunning: isCoreRunning,
                                capabilityAvailability: CapabilityCache.shared.availability(for: .lightGBMUpgrade))

        guard isCoreRunning else {
            completion(.failed(NSLocalizedString("LightGBM model update is unavailable while the core is stopped.", comment: "")),
                       initialState)
            return
        }

        ApiRequest.updateSmartLightGBMModel { result in
            switch result {
            case .success:
                CapabilityCache.shared.set(.lightGBMUpgrade, availability: .available)
                completion(.success,
                           currentState(isCoreRunning: isCoreRunning,
                                        capabilityAvailability: .available))
            case .unsupported:
                CapabilityCache.shared.set(.lightGBMUpgrade, availability: .unsupported)
                completion(.unsupported,
                           currentState(isCoreRunning: isCoreRunning,
                                        capabilityAvailability: .unsupported))
            case let .unauthorized(message):
                CapabilityCache.shared.set(.lightGBMUpgrade, availability: .unauthorized, message: message)
                completion(.unauthorized(message),
                           currentState(isCoreRunning: isCoreRunning,
                                        capabilityAvailability: .unauthorized))
            case let .failed(message):
                CapabilityCache.shared.set(.lightGBMUpgrade, availability: .degraded, message: message)
                completion(.failed(message),
                           currentState(isCoreRunning: isCoreRunning,
                                        capabilityAvailability: .degraded))
            }
        }
    }

    static func controlsEnabled(for state: LightGBMSettingsState) -> Bool {
        state.overrideEnabled
    }

    private static func manualUpdateSummary(isCoreRunning: Bool, capabilityAvailability: CoreEndpointAvailability) -> String {
        guard isCoreRunning else {
            return NSLocalizedString("unavailable while the core is stopped", comment: "")
        }

        if Settings.isUsingEmbeddedCore {
            return NSLocalizedString("appears available for the embedded core", comment: "")
        }

        switch capabilityAvailability {
        case .unsupported:
            return NSLocalizedString("unsupported by the current controller", comment: "")
        case .unauthorized:
            return NSLocalizedString("controller authentication rejected this endpoint", comment: "")
        case .available, .degraded:
            return NSLocalizedString("appears available", comment: "")
        case .unknown, .unavailable:
            return NSLocalizedString("not checked yet", comment: "")
        }
    }
}
