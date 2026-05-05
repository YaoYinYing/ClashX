//
//  SmartAPI.swift
//  ClashX
//
//  Created by Codex on 2026/5/4.
//
//  Smart extension client. These endpoints are optional and must degrade
//  cleanly when the active controller is plain mihomo-compatible.
//

import Alamofire
import Foundation
import SwiftyJSON

enum SmartAPI {
    static func requestSmartWeights(completeHandler: @escaping (ControllerDecodedResult<SmartWeightsResponse>) -> Void) {
        guard let request = ApiRequest.req("/group/weights") else {
            completeHandler(ApiRequest.unavailableDecodedResult())
            return
        }
        request.responseData { response in
            let result: ControllerDecodedResult<SmartWeightsResponse> = ApiRequest.decodedResult(from: response,
                                                                                                 as: SmartWeightsResponse.self,
                                                                                                 defaultMessage: NSLocalizedString("Failed to load Smart weights.", comment: ""))
            if case let .failed(message) = result {
                Logger.log("request smart weights failed: \(message)", level: .warning)
            }
            completeHandler(result)
        }
    }

    static func requestSmartWeights(group: String, completeHandler: @escaping (ControllerDecodedResult<[SmartNodeWeight]>) -> Void) {
        guard let request = ApiRequest.req(pathComponents: ["group", group, "weights"]) else {
            completeHandler(ApiRequest.unavailableDecodedResult())
            return
        }
        request.responseData { response in
            switch ApiRequest.jsonResult(from: response,
                                         defaultMessage: NSLocalizedString("Failed to load Smart group weights.", comment: "")) {
            case let .success(json):
                let weights = json["weights"].arrayValue.compactMap {
                    try? JSONDecoder().decode(SmartNodeWeight.self, from: $0.rawData())
                }
                completeHandler(.success(weights))
            case .unsupported:
                completeHandler(.unsupported)
            case let .unauthorized(message):
                completeHandler(.unauthorized(message))
            case let .failed(message):
                completeHandler(.failed(message))
            }
        }
    }

    static func flushSmartCache(configName: String? = nil, completeHandler: ((ControllerEndpointResult) -> Void)? = nil) {
        let request: DataRequest?
        if let configName {
            request = ApiRequest.req(pathComponents: ["cache", "smart", "flush", configName], method: .post)
        } else {
            request = ApiRequest.req("/cache/smart/flush", method: .post)
        }
        guard let request else {
            completeHandler?(ApiRequest.unavailableEndpointResult())
            return
        }
        request.responseData { response in
            completeHandler?(ApiRequest.endpointResult(from: response,
                                                       defaultMessage: NSLocalizedString("Failed to flush the Smart cache.", comment: "")))
        }
    }

    static func blockSmartConnection(_ id: String, completeHandler: ((ControllerEndpointResult) -> Void)? = nil) {
        guard let request = ApiRequest.req(pathComponents: ["connections", "smart", id], method: .delete) else {
            completeHandler?(ApiRequest.unavailableEndpointResult())
            return
        }
        request.responseData { response in
            completeHandler?(ApiRequest.endpointResult(from: response,
                                                       defaultMessage: NSLocalizedString("Failed to block the Smart connection.", comment: "")))
        }
    }

    static func updateSmartLightGBMModel(completeHandler: @escaping (ControllerEndpointResult) -> Void) {
        guard let request = ApiRequest.req("/upgrade/lgbm", method: .post) else {
            completeHandler(ApiRequest.unavailableEndpointResult())
            return
        }
        request.responseData { response in
            completeHandler(ApiRequest.endpointResult(from: response,
                                                      defaultMessage: NSLocalizedString("LightGBM model update failed.", comment: "")))
        }
    }
}
