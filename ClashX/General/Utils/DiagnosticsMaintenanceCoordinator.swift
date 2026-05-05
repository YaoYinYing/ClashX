//
//  DiagnosticsMaintenanceCoordinator.swift
//  ClashX
//
//  Created by Codex on 2026/5/5.
//

import Foundation

struct DiagnosticsMaintenanceDescriptor {
    let capability: CoreCapability
    let confirmationTitle: String
    let confirmationMessage: String
    let confirmationButtonTitle: String
    let startText: String
    let successText: String
    let unsupportedText: String
    let unauthorizedText: String
}

enum DiagnosticsMaintenanceAction {
    case restartCore
    case runDebugGC
    case updateGeoAssets
    case updateDashboardAssets

    var descriptor: DiagnosticsMaintenanceDescriptor {
        switch self {
        case .restartCore:
            return DiagnosticsMaintenanceDescriptor(
                capability: .restart,
                confirmationTitle: NSLocalizedString("Restart core?", comment: ""),
                confirmationMessage: NSLocalizedString("This will ask the active controller to restart immediately. Existing controller activity may be interrupted.", comment: ""),
                confirmationButtonTitle: NSLocalizedString("Restart", comment: ""),
                startText: NSLocalizedString("Requesting controller restart.", comment: ""),
                successText: NSLocalizedString("Controller restart requested successfully.", comment: ""),
                unsupportedText: NSLocalizedString("Controller restart is unsupported by the active controller.", comment: ""),
                unauthorizedText: NSLocalizedString("Controller restart was rejected by the active controller credentials.", comment: "")
            )
        case .runDebugGC:
            return DiagnosticsMaintenanceDescriptor(
                capability: .debugGC,
                confirmationTitle: NSLocalizedString("Run debug GC?", comment: ""),
                confirmationMessage: NSLocalizedString("This sends a debug garbage-collection request to the active controller. Use it only for diagnostics.", comment: ""),
                confirmationButtonTitle: NSLocalizedString("Run GC", comment: ""),
                startText: NSLocalizedString("Requesting controller garbage collection.", comment: ""),
                successText: NSLocalizedString("Controller garbage collection requested successfully.", comment: ""),
                unsupportedText: NSLocalizedString("Debug GC is unsupported by the active controller.", comment: ""),
                unauthorizedText: NSLocalizedString("Debug GC was rejected by the active controller credentials.", comment: "")
            )
        case .updateGeoAssets:
            return DiagnosticsMaintenanceDescriptor(
                capability: .geoUpdate,
                confirmationTitle: NSLocalizedString("Update GEO assets?", comment: ""),
                confirmationMessage: NSLocalizedString("This asks the active controller to refresh GEO databases and related assets. It is a maintenance action, not a read-only diagnostic.", comment: ""),
                confirmationButtonTitle: NSLocalizedString("Update GEO", comment: ""),
                startText: NSLocalizedString("Updating GEO assets.", comment: ""),
                successText: NSLocalizedString("GEO asset update requested successfully.", comment: ""),
                unsupportedText: NSLocalizedString("GEO asset update is unsupported by the active controller.", comment: ""),
                unauthorizedText: NSLocalizedString("GEO asset update was rejected by the active controller credentials.", comment: "")
            )
        case .updateDashboardAssets:
            return DiagnosticsMaintenanceDescriptor(
                capability: .uiUpgrade,
                confirmationTitle: NSLocalizedString("Update dashboard assets?", comment: ""),
                confirmationMessage: NSLocalizedString("This requests a dashboard asset update from the active controller. Use it only when you intend to modify installed assets.", comment: ""),
                confirmationButtonTitle: NSLocalizedString("Update Dashboard", comment: ""),
                startText: NSLocalizedString("Updating dashboard assets.", comment: ""),
                successText: NSLocalizedString("Dashboard asset update requested successfully.", comment: ""),
                unsupportedText: NSLocalizedString("Dashboard asset update is unsupported by the active controller.", comment: ""),
                unauthorizedText: NSLocalizedString("Dashboard asset update was rejected by the active controller credentials.", comment: "")
            )
        }
    }

    fileprivate func performRequest(_ completeHandler: @escaping (ControllerEndpointResult) -> Void) {
        switch self {
        case .restartCore:
            ApiRequest.restartCore(completeHandler: completeHandler)
        case .runDebugGC:
            ApiRequest.runDebugGC(completeHandler: completeHandler)
        case .updateGeoAssets:
            ApiRequest.updateGeoAssets(completeHandler: completeHandler)
        case .updateDashboardAssets:
            ApiRequest.updateDashboardAssets(completeHandler: completeHandler)
        }
    }
}

final class DiagnosticsMaintenanceCoordinator {
    typealias ConfirmationHandler = (_ title: String, _ message: String, _ confirmTitle: String) -> Bool
    typealias StatusHandler = (_ text: String) -> Void
    typealias ResultHandler = (_ action: DiagnosticsMaintenanceAction, _ result: ControllerEndpointResult) -> Void

    func perform(_ action: DiagnosticsMaintenanceAction,
                 confirm: ConfirmationHandler,
                 setStatus: StatusHandler,
                 handleResult: @escaping ResultHandler) {
        let descriptor = action.descriptor
        guard confirm(descriptor.confirmationTitle,
                      descriptor.confirmationMessage,
                      descriptor.confirmationButtonTitle) else {
            return
        }

        setStatus(descriptor.startText)
        action.performRequest { result in
            handleResult(action, result)
        }
    }
}
