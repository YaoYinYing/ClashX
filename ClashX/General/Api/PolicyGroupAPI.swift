//
//  PolicyGroupAPI.swift
//  ClashX
//
//  Created by Codex on 2026/5/15.
//

import Alamofire
import Foundation

enum PolicyGroupAPI {
    static func requestPolicyGroups(completeHandler: @escaping (ControllerJSONResult) -> Void) {
        guard let request = ApiRequest.req("/group") else {
            completeHandler(ApiRequest.unavailableJSONResult())
            return
        }
        request.responseData { response in
            completeHandler(ApiRequest.jsonResult(from: response,
                                                  defaultMessage: NSLocalizedString("Failed to load policy group diagnostics.", comment: "")))
        }
    }

    static func requestPolicyGroup(name: String, completeHandler: @escaping (ControllerJSONResult) -> Void) {
        guard let request = ApiRequest.req(pathComponents: ["group", name]) else {
            completeHandler(ApiRequest.unavailableJSONResult())
            return
        }
        request.responseData { response in
            completeHandler(ApiRequest.jsonResult(from: response,
                                                  defaultMessage: NSLocalizedString("Failed to load policy group details.", comment: "")))
        }
    }

    static func deletePolicyGroup(name: String, completeHandler: ((ControllerEndpointResult) -> Void)? = nil) {
        guard let request = ApiRequest.req(pathComponents: ["group", name], method: .delete) else {
            completeHandler?(ApiRequest.unavailableEndpointResult())
            return
        }
        request.responseData { response in
            completeHandler?(ApiRequest.endpointResult(from: response,
                                                       defaultMessage: NSLocalizedString("Failed to delete policy group state.", comment: "")))
        }
    }

    static func requestPolicyGroupDelay(name: String,
                                        timeout: Int = 5000,
                                        url: String = Settings.benchMarkUrl,
                                        completeHandler: @escaping (ControllerJSONResult) -> Void) {
        // Keep this boundary explicit: `/group/<name>/delay` is still treated as
        // a guarded diagnostics helper until SmartX verifies it as a stable
        // mihomo-compatible baseline endpoint across the runtimes it supports.
        let queryItems = [
            URLQueryItem(name: "timeout", value: String(timeout)),
            URLQueryItem(name: "url", value: url)
        ]
        guard let request = ApiRequest.req(pathComponents: ["group", name, "delay"], queryItems: queryItems) else {
            completeHandler(ApiRequest.unavailableJSONResult())
            return
        }
        request.responseData { response in
            completeHandler(ApiRequest.jsonResult(from: response,
                                                  defaultMessage: NSLocalizedString("Failed to load policy group delay diagnostics.", comment: "")))
        }
    }
}
