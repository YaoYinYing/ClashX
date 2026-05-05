//
//  ConnectionAPI.swift
//  ClashX
//
//  Created by Codex on 2026/5/5.
//
//  Connection-specific controller reads, deletes, and stream URL helpers.
//  Stream lifecycle still lives with ApiRequest / request objects that own
//  WebSocket delegates and retry timers.
//

import Alamofire
import Foundation

enum ConnectionAPI {
    static func requestConnections(completeHandler: @escaping ([ClashConnectionBaseSnapShot.Connection]) -> Void) {
        guard let request = ApiRequest.req("/connections") else {
            completeHandler([])
            return
        }
        request.responseDecodable(of: ClashConnectionBaseSnapShot.self) { response in
            switch response.result {
            case let .success(snapshot):
                completeHandler(snapshot.connections)
            case .failure:
                assertionFailure()
                completeHandler([])
            }
        }
    }

    static func closeConnection(_ id: String, completeHandler: (() -> Void)? = nil) {
        ApiRequest.req(pathComponents: ["connections", id], method: .delete)?.response { _ in
            completeHandler?()
        }
    }

    static func closeAllConnections(completeHandler: (() -> Void)? = nil) {
        if ApiRequest.useDirectApi() {
            clash_closeAllConnections()
            completeHandler?()
            return
        }

        ApiRequest.req("/connections", method: .delete)?.response { _ in
            completeHandler?()
        }
    }

    static func connectionWebSocketURL() throws -> URL {
        try ControllerEndpointBuilder.websocketURL(path: "/connections")
    }
}
