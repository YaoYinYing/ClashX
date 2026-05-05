//
//  DiagnosticsAPI.swift
//  ClashX
//
//  Created by Codex on 2026/5/4.
//
//  Baseline diagnostics and maintenance client for mihomo-compatible controller
//  endpoints. Smart-only operations should stay out of this file.
//

import Alamofire
import Foundation

enum DiagnosticsAPI {
    static func requestMemorySnapshot(completeHandler: @escaping (ControllerJSONResult) -> Void) {
        guard let request = ApiRequest.req("/memory") else {
            completeHandler(ApiRequest.unavailableJSONResult())
            return
        }
        request.responseData { response in
            completeHandler(ApiRequest.jsonResult(from: response,
                                                  defaultMessage: NSLocalizedString("Failed to load memory diagnostics.", comment: "")))
        }
    }

    static func requestDNSQuery(name: String, type: String? = nil, completeHandler: @escaping (ControllerJSONResult) -> Void) {
        var queryItems = [URLQueryItem(name: "name", value: name)]
        if let type, !type.isEmpty {
            queryItems.append(URLQueryItem(name: "type", value: type))
        }
        guard let request = ApiRequest.req("/dns/query", queryItems: queryItems) else {
            completeHandler(ApiRequest.unavailableJSONResult())
            return
        }
        request.responseData { response in
            completeHandler(ApiRequest.jsonResult(from: response,
                                                  defaultMessage: NSLocalizedString("Failed to query DNS diagnostics.", comment: "")))
        }
    }

    static func resetDNSCache(completeHandler: ((ControllerEndpointResult) -> Void)? = nil) {
        performMaintenanceRequest(path: "/cache/dns/flush",
                                  method: .post,
                                  defaultMessage: NSLocalizedString("Failed to flush DNS cache.", comment: ""),
                                  completeHandler: completeHandler)
    }

    static func resetFakeIPCache(completeHandler: ((ControllerEndpointResult) -> Void)? = nil) {
        performMaintenanceRequest(path: "/cache/fakeip/flush",
                                  method: .post,
                                  defaultMessage: NSLocalizedString("Failed to flush the fake-IP cache.", comment: ""),
                                  logPrefix: "flush fake ip",
                                  completeHandler: completeHandler)
    }

    static func reloadGeoDatabase(completeHandler: ((ControllerEndpointResult) -> Void)? = nil) {
        performMaintenanceRequest(path: "/configs/geo",
                                  method: .post,
                                  defaultMessage: NSLocalizedString("Failed to reload GEO data.", comment: ""),
                                  completeHandler: completeHandler)
    }

    static func restartCore(completeHandler: ((ControllerEndpointResult) -> Void)? = nil) {
        performMaintenanceRequest(path: "/restart",
                                  method: .post,
                                  defaultMessage: NSLocalizedString("Failed to restart the active core.", comment: ""),
                                  completeHandler: completeHandler)
    }

    static func updateDashboardAssets(completeHandler: ((ControllerEndpointResult) -> Void)? = nil) {
        performMaintenanceRequest(path: "/upgrade/ui",
                                  method: .post,
                                  defaultMessage: NSLocalizedString("Failed to update dashboard assets.", comment: ""),
                                  completeHandler: completeHandler)
    }

    static func updateGeoAssets(completeHandler: ((ControllerEndpointResult) -> Void)? = nil) {
        performMaintenanceRequest(path: "/upgrade/geo",
                                  method: .post,
                                  defaultMessage: NSLocalizedString("Failed to update GEO assets.", comment: ""),
                                  completeHandler: completeHandler)
    }

    static func runDebugGC(completeHandler: ((ControllerEndpointResult) -> Void)? = nil) {
        performMaintenanceRequest(path: "/debug/gc",
                                  method: .put,
                                  defaultMessage: NSLocalizedString("Failed to trigger controller garbage collection.", comment: ""),
                                  completeHandler: completeHandler)
    }

    static func pprofURLs() -> [URL]? {
        guard let baseURL = try? ControllerEndpointBuilder.baseHTTPURL() else {
            return nil
        }
        let paths = ["/debug/pprof", "/debug/pprof/goroutine", "/debug/pprof/heap", "/debug/pprof/profile"]
        return paths.compactMap { try? ControllerEndpointBuilder.composeURL(baseURL: baseURL, path: $0) }
    }

    private static func performMaintenanceRequest(path: String,
                                                  method: HTTPMethod,
                                                  defaultMessage: String,
                                                  unsupportedStatusCodes: Set<Int> = [400, 404, 405, 501],
                                                  logPrefix: String? = nil,
                                                  completeHandler: ((ControllerEndpointResult) -> Void)? = nil) {
        guard let request = ApiRequest.req(path, method: method) else {
            completeHandler?(ApiRequest.unavailableEndpointResult())
            return
        }
        request.responseData { response in
            if let logPrefix {
                Logger.log("\(logPrefix): \(response.response?.statusCode ?? -1)")
            }
            completeHandler?(ApiRequest.endpointResult(from: response,
                                                       defaultMessage: defaultMessage,
                                                       unsupportedStatusCodes: unsupportedStatusCodes))
        }
    }
}
