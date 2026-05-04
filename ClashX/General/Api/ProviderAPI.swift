//
//  ProviderAPI.swift
//  ClashX
//
//  Created by Codex on 2026/5/4.
//
//  Baseline provider diagnostics and maintenance client. This boundary keeps
//  provider-specific controller behavior out of Smart-only endpoint helpers.
//

import Alamofire
import Foundation

enum ProviderAPI {
    static func requestProxyProvidersDiagnostics(completeHandler: @escaping (ControllerJSONResult) -> Void) {
        guard let request = ApiRequest.req("/providers/proxies") else {
            completeHandler(ApiRequest.unavailableJSONResult())
            return
        }
        request.responseData { response in
            completeHandler(ApiRequest.jsonResult(from: response,
                                                  defaultMessage: NSLocalizedString("Failed to load proxy provider diagnostics.", comment: "")))
        }
    }

    static func requestRuleProvidersDiagnostics(completeHandler: @escaping (ControllerJSONResult) -> Void) {
        guard let request = ApiRequest.req("/providers/rules") else {
            completeHandler(ApiRequest.unavailableJSONResult())
            return
        }
        request.responseData { response in
            completeHandler(ApiRequest.jsonResult(from: response,
                                                  defaultMessage: NSLocalizedString("Failed to load rule provider diagnostics.", comment: "")))
        }
    }

    static func updateProviderResult(name: String, type: ApiRequest.ProviderType, completeHandler: @escaping (ControllerEndpointResult) -> Void) {
        let pathComponents: [String]
        switch type {
        case .proxy:
            pathComponents = ["providers", "proxies", name]
        case .rule:
            pathComponents = ["providers", "rules", name]
        }
        guard let request = ApiRequest.req(pathComponents: pathComponents, method: .put) else {
            completeHandler(ApiRequest.unavailableEndpointResult())
            return
        }
        request.responseData { response in
            completeHandler(ApiRequest.endpointResult(from: response,
                                                      defaultMessage: NSLocalizedString("Failed to update the selected provider.", comment: "")))
        }
    }

    static func healthCheckProvider(proxy: ClashProviderName, completeHandler: ((Bool) -> Void)? = nil) {
        Logger.log("HeathCheck for \(proxy) started")
        guard let request = ApiRequest.req(pathComponents: ["providers", "proxies", proxy, "healthcheck"]) else {
            completeHandler?(false)
            return
        }
        request.response { response in
            let success = response.response?.statusCode == 204
            if success {
                Logger.log("HeathCheck for \(proxy) finished")
            } else {
                Logger.log("HeathCheck for \(proxy) failed:\(response.response?.statusCode ?? -1)")
            }
            completeHandler?(success)
        }
    }
}
