//
//  ConfigAPI.swift
//  ClashX
//
//  Created by Codex on 2026/5/4.
//
//  Baseline config client for mihomo-compatible controller reads and guarded
//  patches. Smart-only override generation should not live here.
//

import Alamofire
import Foundation

enum ConfigAPI {
    static func requestControllerConfig(completeHandler: @escaping (ControllerDecodedResult<ClashConfig>) -> Void) {
        guard let request = ApiRequest.req("/configs") else {
            completeHandler(ApiRequest.unavailableDecodedResult())
            return
        }
        request.responseData { response in
            completeHandler(ApiRequest.decodedResult(from: response,
                                                     as: ClashConfig.self,
                                                     defaultMessage: NSLocalizedString("Failed to load config state.", comment: "")))
        }
    }

    static func patchConfig(parameters: Parameters,
                            defaultMessage: String,
                            completeHandler: @escaping (ControllerEndpointResult) -> Void) {
        guard let request = ApiRequest.req("/configs",
                                           method: .patch,
                                           parameters: parameters,
                                           encoding: JSONEncoding.default) else {
            completeHandler(ApiRequest.unavailableEndpointResult())
            return
        }
        request.responseData { response in
            completeHandler(ApiRequest.endpointResult(from: response, defaultMessage: defaultMessage))
        }
    }

    static func updateTunResult(enable: Bool, completeHandler: @escaping (ControllerEndpointResult) -> Void) {
        let controllerMode = Settings.isUsingEmbeddedCore ? "embedded core" : "external controller"
        patchConfig(parameters: ["tun": ["enable": enable]],
                    defaultMessage: NSLocalizedString("Failed to update TUN settings.", comment: "")) { result in
            switch result {
            case .success, .unsupported, .unauthorized:
                completeHandler(result)
            case let .failed(message):
                let composed = String(format: NSLocalizedString("TUN update failed while using %@. %@", comment: ""),
                                      controllerMode,
                                      message)
                Logger.log("[ConfigAPI] updateTun failed enable=\(enable) mode=\(controllerMode) message=\(message)", level: .warning)
                completeHandler(.failed(composed))
            }
        }
    }

    /// Patches the full TUN block with the given parameters dictionary.
    /// The caller is responsible for building a valid "tun" parameter containing all desired fields.
    static func patchTunConfig(_ tunParameters: Parameters,
                               completeHandler: @escaping (ControllerEndpointResult) -> Void) {
        patchConfig(parameters: ["tun": tunParameters],
                    defaultMessage: NSLocalizedString("Failed to patch TUN configuration.", comment: ""),
                    completeHandler: completeHandler)
    }
}
