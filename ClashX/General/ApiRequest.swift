//
//  ApiRequest.swift
//  ClashX
//
//  Created by CYC on 2018/7/30.
//  Copyright © 2018年 yichengchen. All rights reserved.
//

import Alamofire
import Cocoa
import Starscream
import SwiftyJSON

protocol ApiRequestStreamDelegate: AnyObject {
    func didUpdateTraffic(up: Int, down: Int)
    func didGetLog(log: String, level: String)
}

typealias ErrorString = String

struct SmartNodeWeight: Decodable {
    let name: String
    let rank: String
    let weight: Double
    let lastUpdated: Int

    private enum CodingKeys: String, CodingKey {
        case name, rank, weight, lastUpdated
        case capitalizedName = "Name"
        case capitalizedRank = "Rank"
        case capitalizedWeight = "Weight"
        case capitalizedLastUpdated = "LastUpdated"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? container.decodeIfPresent(String.self, forKey: .capitalizedName) ?? ""
        rank = try container.decodeIfPresent(String.self, forKey: .rank) ?? container.decodeIfPresent(String.self, forKey: .capitalizedRank) ?? ""
        weight = try container.decodeIfPresent(Double.self, forKey: .weight) ?? container.decodeIfPresent(Double.self, forKey: .capitalizedWeight) ?? 0
        lastUpdated = try container.decodeIfPresent(Int.self, forKey: .lastUpdated) ?? container.decodeIfPresent(Int.self, forKey: .capitalizedLastUpdated) ?? 0
    }
}

struct SmartWeightsResponse: Decodable {
    let weights: [String: [SmartNodeWeight]]
    let errors: [String: String]?
    let message: String?
}

enum ControllerEndpointResult {
    case success
    case unsupported
    case unauthorized(String)
    case failed(String)
}

enum ControllerJSONResult {
    case success(JSON)
    case unsupported
    case unauthorized(String)
    case failed(String)
}

enum ControllerDecodedResult<T> {
    case success(T)
    case unsupported
    case unauthorized(String)
    case failed(String)
}

struct CoreVersionInfo: Decodable {
    let version: String
}

class ApiRequest {
    static let shared = ApiRequest()

    private var proxyRespCache: ClashProxyResp?

    private lazy var logQueue = DispatchQueue(label: "com.ClashX.core.log")

    static let clashRequestQueue = DispatchQueue(label: "com.clashx.clashRequestQueue")

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 604800
        configuration.timeoutIntervalForResource = 604800
        configuration.httpMaximumConnectionsPerHost = 100
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        alamoFireManager = Session(configuration: configuration)
    }

    static func authHeader() -> HTTPHeaders {
        let secret = ConfigManager.shared.overrideSecret ?? ConfigManager.shared.apiSecret
        return (!secret.isEmpty) ? ["Authorization": "Bearer \(secret)"] : [:]
    }

    private static func req(
        _ path: String,
        method: HTTPMethod = .get,
        parameters: Parameters? = nil,
        encoding: ParameterEncoding = URLEncoding.default,
        queryItems: [URLQueryItem] = []
    )
        -> DataRequest? {
        do {
            let url = try ControllerEndpointBuilder.httpURL(path: path, queryItems: queryItems)
            return shared.alamoFireManager
                .request(url,
                         method: method,
                         parameters: parameters,
                         encoding: encoding,
                         headers: authHeader())
        } catch {
            Logger.log("[ApiRequest] request unavailable path=\(path) error=\(error.localizedDescription)", level: .warning)
            return nil
        }
    }

    private static func req(
        pathComponents: [String],
        method: HTTPMethod = .get,
        parameters: Parameters? = nil,
        encoding: ParameterEncoding = URLEncoding.default,
        queryItems: [URLQueryItem] = []
    ) -> DataRequest? {
        do {
            let url = try ControllerEndpointBuilder.httpURL(pathComponents: pathComponents, queryItems: queryItems)
            return shared.alamoFireManager
                .request(url,
                         method: method,
                         parameters: parameters,
                         encoding: encoding,
                         headers: authHeader())
        } catch {
            Logger.log("[ApiRequest] request unavailable pathComponents=\(pathComponents) error=\(error.localizedDescription)", level: .warning)
            return nil
        }
    }

    private static func controllerUnavailableMessage() -> String {
        NSLocalizedString("Core is stopped or controller is unavailable.", comment: "")
    }

    private static func unavailableEndpointResult() -> ControllerEndpointResult {
        .failed(controllerUnavailableMessage())
    }

    private static func unavailableJSONResult() -> ControllerJSONResult {
        .failed(controllerUnavailableMessage())
    }

    private static func unavailableDecodedResult<T>() -> ControllerDecodedResult<T> {
        .failed(controllerUnavailableMessage())
    }

    private static func endpointResult(from response: AFDataResponse<Data>, defaultMessage: String, unsupportedStatusCodes: Set<Int> = [400, 404, 405, 501]) -> ControllerEndpointResult {
        let statusCode = response.response?.statusCode
        if let statusCode, (200 ..< 300).contains(statusCode) {
            return .success
        }

        if let statusCode, [401, 403].contains(statusCode) {
            let message = response.error?.localizedDescription ?? NSLocalizedString("The active controller rejected authentication for this endpoint.", comment: "")
            return .unauthorized(message)
        }

        if let statusCode, unsupportedStatusCodes.contains(statusCode) {
            return .unsupported
        }

        let data = try? response.result.get()
        let controllerMessage = data.flatMap { rawData in
            JSON(rawData)["message"].string?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let message: String
        if let controllerMessage, !controllerMessage.isEmpty {
            message = controllerMessage
        } else {
            message = response.error?.localizedDescription ?? defaultMessage
        }
        return .failed(message)
    }

    private static func jsonResult(from response: AFDataResponse<Data>, defaultMessage: String, unsupportedStatusCodes: Set<Int> = [400, 404, 405, 501]) -> ControllerJSONResult {
        switch endpointResult(from: response, defaultMessage: defaultMessage, unsupportedStatusCodes: unsupportedStatusCodes) {
        case .success:
            guard let data = try? response.result.get() else {
                return .failed(defaultMessage)
            }
            return .success(JSON(data))
        case .unsupported:
            return .unsupported
        case let .unauthorized(message):
            return .unauthorized(message)
        case let .failed(message):
            return .failed(message)
        }
    }

    private static func decodedResult<T: Decodable>(from response: AFDataResponse<Data>,
                                                    as type: T.Type,
                                                    defaultMessage: String,
                                                    unsupportedStatusCodes: Set<Int> = [400, 404, 405, 501],
                                                    decoder: JSONDecoder = JSONDecoder()) -> ControllerDecodedResult<T> {
        switch endpointResult(from: response, defaultMessage: defaultMessage, unsupportedStatusCodes: unsupportedStatusCodes) {
        case .success:
            guard let data = try? response.result.get() else {
                return .failed(defaultMessage)
            }
            do {
                return try .success(decoder.decode(type, from: data))
            } catch {
                return .failed(error.localizedDescription)
            }
        case .unsupported:
            return .unsupported
        case let .unauthorized(message):
            return .unauthorized(message)
        case let .failed(message):
            return .failed(message)
        }
    }

    weak var delegate: ApiRequestStreamDelegate?

    private var trafficWebSocket: WebSocket?
    private var loggingWebSocket: WebSocket?

    private var trafficWebSocketRetryDelay: TimeInterval = 1
    private var loggingWebSocketRetryDelay: TimeInterval = 1
    private var trafficWebSocketRetryTimer: Timer?
    private var loggingWebSocketRetryTimer: Timer?

    private var alamoFireManager: Session

    static func useDirectApi() -> Bool {
        if ConfigManager.shared.overrideApiURL != nil {
            return false
        }
        return Settings.builtInApiMode
    }

    static func requestConfig(completeHandler: @escaping ((ClashConfig) -> Void)) {
        if !useDirectApi() {
            guard let request = req("/configs") else {
                Logger.log("request config unavailable: controller not running", level: .warning)
                return
            }
            request.responseDecodable(of: ClashConfig.self) {
                resp in
                switch resp.result {
                case let .success(config):
                    completeHandler(config)
                case let .failure(err):
                    Logger.log(err.localizedDescription)
                    NSUserNotificationCenter.default.post(title: "Error", info: err.localizedDescription)
                }
            }
            return
        }

        let data = clashGetConfigs()?.toString().data(using: .utf8) ?? Data()
        guard let config = ClashConfig.fromData(data) else {
            NSUserNotificationCenter.default.post(title: "Error", info: "Get clash config failed. Try fixing your config file, then reload the config or restart SmartX.")
            (NSApplication.shared.delegate as? AppDelegate)?.startProxy()
            return
        }
        completeHandler(config)
    }

    static func requestConfigUpdate(configName: String, callback: @escaping ((ErrorString?) -> Void)) {
        ConfigManager.getConfigPath(configName: configName) {
            switch $0 {
            case let .success(path):
                requestConfigUpdate(configPath: path, callback: callback)
            case let .failure(error):
                callback(error.localizedDescription)
            }
        }
    }

    static func requestConfigUpdate(configPath: String, callback: @escaping ((ErrorString?) -> Void)) {
        let placeHolderErrorDesp = "An error occurred. Try fixing it by restarting SmartX. "

        // DEV MODE: Use API
        if !useDirectApi() {
            guard let request = req("/configs", method: .put, parameters: ["Path": configPath], encoding: JSONEncoding.default) else {
                callback(controllerUnavailableMessage())
                return
            }
            request.responseData { res in
                if res.response?.statusCode == 204 {
                    ConfigManager.shared.isRunning = true
                    callback(nil)
                } else {
                    let errorJson = try? res.result.get()
                    let err = JSON(errorJson ?? "")["message"].string ?? placeHolderErrorDesp
                    Logger.log(err)
                    callback(err)
                }
            }
            return
        }

        // NORMAL MODE: Use internal api
        clashRequestQueue.async {
            Settings.syncSmartLightGBMOptionsToCore()
            let res = clashUpdateConfig(configPath.goStringBuffer())?.toString() ?? placeHolderErrorDesp
            DispatchQueue.main.async {
                if res == "success" {
                    callback(nil)
                } else {
                    Logger.log(res)
                    callback(res)
                }
            }
        }
    }

    static func updateOutBoundMode(mode: ClashProxyMode, callback: ((Bool) -> Void)? = nil) {
        guard let request = req("/configs", method: .patch, parameters: ["mode": mode.rawValue], encoding: JSONEncoding.default) else {
            callback?(false)
            return
        }
        request
            .responseData { response in
                switch response.result {
                case .success:
                    callback?(true)
                case .failure:
                    callback?(false)
                }
            }
    }

    static func updateLogLevel(level: ClashLogLevel, callback: ((Bool) -> Void)? = nil) {
        guard let request = req("/configs", method: .patch, parameters: ["log-level": level.rawValue], encoding: JSONEncoding.default) else {
            callback?(false)
            return
        }
        request.responseData(completionHandler: { response in
            switch response.result {
            case .success:
                callback?(true)
            case .failure:
                callback?(false)
            }
        })
    }

    static func requestProxyGroupList(completeHandler: ((ClashProxyResp) -> Void)? = nil) {
        guard let request = req("/proxies") else {
            completeHandler?(ClashProxyResp(nil))
            return
        }
        request.responseData {
            res in
            let proxies = ClashProxyResp(try? res.result.get())
            ApiRequest.shared.proxyRespCache = proxies
            completeHandler?(proxies)
        }
    }

    static func requestProxyProviderList(completeHandler: ((ClashProviderResp) -> Void)? = nil) {
        guard let request = req("/providers/proxies") else {
            completeHandler?(ClashProviderResp())
            return
        }
        request
            .responseDecodable(of: ClashProviderResp.self, decoder: ClashProviderResp.decoder) { resp in
                switch resp.result {
                case let .success(providerResp):
                    completeHandler?(providerResp)
                case let .failure(err):
                    Logger.log("request proxy providers failed: \(err)", level: .warning)
                    completeHandler?(ClashProviderResp())
                }
            }
    }

    static func updateAllowLan(allow: Bool, completeHandler: (() -> Void)? = nil) {
        Logger.log("update allow lan:\(allow)", level: .debug)
        guard let request = req("/configs",
                                method: .patch,
                                parameters: ["allow-lan": allow],
                                encoding: JSONEncoding.default) else {
            completeHandler?()
            return
        }
        request.response {
            _ in
            completeHandler?()
        }
    }

    static func updateTun(enable: Bool, completeHandler: @escaping (Bool, ErrorString?) -> Void) {
        updateTunResult(enable: enable) { result in
            switch result {
            case .success:
                completeHandler(true, nil)
            case .unsupported:
                completeHandler(false, NSLocalizedString("The active controller does not support guarded TUN updates.", comment: ""))
            case let .unauthorized(message), let .failed(message):
                completeHandler(false, message)
            }
        }
    }

    static func updateTunResult(enable: Bool, completeHandler: @escaping (ControllerEndpointResult) -> Void) {
        let controllerMode = Settings.isUsingEmbeddedCore ? "embedded core" : "external controller"
        guard let request = req("/configs",
                                method: .patch,
                                parameters: ["tun": ["enable": enable]],
                                encoding: JSONEncoding.default) else {
            completeHandler(unavailableEndpointResult())
            return
        }
        request.responseData { response in
            if response.response?.statusCode == 204 {
                completeHandler(.success)
                return
            }

            let data = try? response.result.get()
            let controllerMessage = data.flatMap { JSON($0)["message"].string?.trimmingCharacters(in: .whitespacesAndNewlines) }
            let statusCode = response.response?.statusCode
            let fallback = response.error?.localizedDescription ?? NSLocalizedString("Failed to update TUN settings.", comment: "")

            var messageParts = [String(format: NSLocalizedString("TUN update failed while using %@.", comment: ""), controllerMode)]
            if let statusCode {
                messageParts.append("HTTP \(statusCode).")
            }
            if let controllerMessage, !controllerMessage.isEmpty {
                messageParts.append(controllerMessage)
            } else {
                messageParts.append(fallback)
            }

            Logger.log("[ApiRequest] updateTun failed enable=\(enable) mode=\(controllerMode) status=\(statusCode.map(String.init) ?? "none") controllerMessage=\(controllerMessage ?? "none")", level: .warning)
            if let statusCode, [401, 403].contains(statusCode) {
                completeHandler(.unauthorized(messageParts.joined(separator: " ")))
            } else if let statusCode, [400, 404, 405, 501].contains(statusCode) {
                completeHandler(.unsupported)
            } else {
                completeHandler(.failed(messageParts.joined(separator: " ")))
            }
        }
    }

    static func updateProxyGroup(group: String, selectProxy: String, callback: @escaping ((Bool) -> Void)) {
        guard let request = req(pathComponents: ["proxies", group],
                                method: .put,
                                parameters: ["name": selectProxy],
                                encoding: JSONEncoding.default) else {
            callback(false)
            return
        }
        request
            .responseData { response in
                callback(response.response?.statusCode == 204)
            }
    }

    static func getAllProxyList(callback: @escaping (([ClashProxyName]) -> Void)) {
        requestProxyGroupList {
            proxyInfo in
            let lists: [ClashProxyName] = proxyInfo.proxiesMap["GLOBAL"]?.all ?? []
            callback(lists)
        }
    }

    static func getMergedProxyData(complete: ((ClashProxyResp?) -> Void)? = nil) {
        let group = DispatchGroup()
        group.enter()
        group.enter()

        var provider: ClashProviderResp?
        var proxyInfo: ClashProxyResp?

        group.notify(queue: .main) {
            guard let proxyInfo = proxyInfo else {
                complete?(nil)
                return
            }
            proxyInfo.updateProvider(provider ?? ClashProviderResp())
            complete?(proxyInfo)
        }

        ApiRequest.requestProxyProviderList {
            proxyprovider in
            provider = proxyprovider
            group.leave()
        }

        ApiRequest.requestProxyGroupList {
            proxy in
            proxyInfo = proxy
            group.leave()
        }
    }

    static func getProxyDelay(proxyName: String, callback: @escaping ((Int) -> Void)) {
        guard let request = req(pathComponents: ["proxies", proxyName, "delay"],
                                method: .get,
                                parameters: ["timeout": 5000, "url": Settings.benchMarkUrl]) else {
            callback(0)
            return
        }
        request
            .responseData { res in
                switch res.result {
                case let .success(value):
                    let json = JSON(value)
                    callback(json["delay"].intValue)
                case .failure:
                    callback(0)
                }
            }
    }

    static func getRules(completeHandler: @escaping ([ClashRule]) -> Void) {
        guard let request = req("/rules") else {
            completeHandler([])
            return
        }
        request.responseData { res in
            guard let data = try? res.result.get() else { return }
            let rule = ClashRuleResponse.fromData(data)
            completeHandler(rule.rules ?? [])
        }
    }

    static func healthCheck(proxy: ClashProviderName, completeHandler: (() -> Void)? = nil) {
        Logger.log("HeathCheck for \(proxy) started")
        guard let request = req(pathComponents: ["providers", "proxies", proxy, "healthcheck"]) else {
            completeHandler?()
            return
        }
        request.response { res in
            if res.response?.statusCode == 204 {
                Logger.log("HeathCheck for \(proxy) finished")
            } else {
                Logger.log("HeathCheck for \(proxy) failed:\(res.response?.statusCode ?? -1)")
            }
            completeHandler?()
        }
    }

    static func healthCheckProvider(proxy: ClashProviderName, completeHandler: ((Bool) -> Void)? = nil) {
        Logger.log("HeathCheck for \(proxy) started")
        guard let request = req(pathComponents: ["providers", "proxies", proxy, "healthcheck"]) else {
            completeHandler?(false)
            return
        }
        request.response { res in
            let success = res.response?.statusCode == 204
            if success {
                Logger.log("HeathCheck for \(proxy) finished")
            } else {
                Logger.log("HeathCheck for \(proxy) failed:\(res.response?.statusCode ?? -1)")
            }
            completeHandler?(success)
        }
    }

    static func requestMemorySnapshot(completeHandler: @escaping (ControllerJSONResult) -> Void) {
        guard let request = req("/memory") else {
            completeHandler(unavailableJSONResult())
            return
        }
        request.responseData { response in
            completeHandler(jsonResult(from: response, defaultMessage: NSLocalizedString("Failed to load memory diagnostics.", comment: "")))
        }
    }

    static func requestProxyProvidersDiagnostics(completeHandler: @escaping (ControllerJSONResult) -> Void) {
        guard let request = req("/providers/proxies") else {
            completeHandler(unavailableJSONResult())
            return
        }
        request.responseData { response in
            completeHandler(jsonResult(from: response, defaultMessage: NSLocalizedString("Failed to load proxy provider diagnostics.", comment: "")))
        }
    }

    static func requestRuleProvidersDiagnostics(completeHandler: @escaping (ControllerJSONResult) -> Void) {
        guard let request = req("/providers/rules") else {
            completeHandler(unavailableJSONResult())
            return
        }
        request.responseData { response in
            completeHandler(jsonResult(from: response, defaultMessage: NSLocalizedString("Failed to load rule provider diagnostics.", comment: "")))
        }
    }

    static func requestDNSQuery(name: String, type: String? = nil, completeHandler: @escaping (ControllerJSONResult) -> Void) {
        var queryItems = [URLQueryItem(name: "name", value: name)]
        if let type, !type.isEmpty {
            queryItems.append(URLQueryItem(name: "type", value: type))
        }
        guard let request = req("/dns/query", queryItems: queryItems) else {
            completeHandler(unavailableJSONResult())
            return
        }
        request.responseData { response in
            completeHandler(jsonResult(from: response, defaultMessage: NSLocalizedString("Failed to query DNS diagnostics.", comment: "")))
        }
    }

    static func resetDNSCache(completeHandler: ((ControllerEndpointResult) -> Void)? = nil) {
        guard let request = req("/cache/dns/flush", method: .post) else {
            completeHandler?(unavailableEndpointResult())
            return
        }
        request.responseData { response in
            completeHandler?(endpointResult(from: response, defaultMessage: NSLocalizedString("Failed to flush DNS cache.", comment: "")))
        }
    }

    static func reloadGeoDatabase(completeHandler: ((ControllerEndpointResult) -> Void)? = nil) {
        guard let request = req("/configs/geo", method: .post) else {
            completeHandler?(unavailableEndpointResult())
            return
        }
        request.responseData { response in
            completeHandler?(endpointResult(from: response, defaultMessage: NSLocalizedString("Failed to reload GEO data.", comment: "")))
        }
    }

    static func restartCore(completeHandler: ((ControllerEndpointResult) -> Void)? = nil) {
        guard let request = req("/restart", method: .post) else {
            completeHandler?(unavailableEndpointResult())
            return
        }
        request.responseData { response in
            completeHandler?(endpointResult(from: response, defaultMessage: NSLocalizedString("Failed to restart the active core.", comment: "")))
        }
    }

    static func updateDashboardAssets(completeHandler: ((ControllerEndpointResult) -> Void)? = nil) {
        guard let request = req("/upgrade/ui", method: .post) else {
            completeHandler?(unavailableEndpointResult())
            return
        }
        request.responseData { response in
            completeHandler?(endpointResult(from: response, defaultMessage: NSLocalizedString("Failed to update dashboard assets.", comment: "")))
        }
    }

    static func updateGeoAssets(completeHandler: ((ControllerEndpointResult) -> Void)? = nil) {
        guard let request = req("/upgrade/geo", method: .post) else {
            completeHandler?(unavailableEndpointResult())
            return
        }
        request.responseData { response in
            completeHandler?(endpointResult(from: response, defaultMessage: NSLocalizedString("Failed to update GEO assets.", comment: "")))
        }
    }

    static func runDebugGC(completeHandler: ((ControllerEndpointResult) -> Void)? = nil) {
        guard let request = req("/debug/gc", method: .put) else {
            completeHandler?(unavailableEndpointResult())
            return
        }
        request.responseData { response in
            completeHandler?(endpointResult(from: response, defaultMessage: NSLocalizedString("Failed to trigger controller garbage collection.", comment: "")))
        }
    }

    static func requestPolicyGroups(completeHandler: @escaping (ControllerJSONResult) -> Void) {
        guard let request = req("/group") else {
            completeHandler(unavailableJSONResult())
            return
        }
        request.responseData { response in
            completeHandler(jsonResult(from: response, defaultMessage: NSLocalizedString("Failed to load policy group diagnostics.", comment: "")))
        }
    }

    static func requestPolicyGroup(name: String, completeHandler: @escaping (ControllerJSONResult) -> Void) {
        guard let request = req(pathComponents: ["group", name]) else {
            completeHandler(unavailableJSONResult())
            return
        }
        request.responseData { response in
            completeHandler(jsonResult(from: response, defaultMessage: NSLocalizedString("Failed to load policy group details.", comment: "")))
        }
    }

    static func deletePolicyGroup(name: String, completeHandler: ((ControllerEndpointResult) -> Void)? = nil) {
        guard let request = req(pathComponents: ["group", name], method: .delete) else {
            completeHandler?(unavailableEndpointResult())
            return
        }
        request.responseData { response in
            completeHandler?(endpointResult(from: response, defaultMessage: NSLocalizedString("Failed to delete policy group state.", comment: "")))
        }
    }

    static func requestPolicyGroupDelay(name: String, timeout: Int = 5000, url: String = Settings.benchMarkUrl, completeHandler: @escaping (ControllerJSONResult) -> Void) {
        let queryItems = [
            URLQueryItem(name: "timeout", value: String(timeout)),
            URLQueryItem(name: "url", value: url)
        ]
        guard let request = req(pathComponents: ["group", name, "delay"], queryItems: queryItems) else {
            completeHandler(unavailableJSONResult())
            return
        }
        request.responseData { response in
            completeHandler(jsonResult(from: response, defaultMessage: NSLocalizedString("Failed to load policy group delay diagnostics.", comment: "")))
        }
    }
}

// MARK: - Connections

extension ApiRequest {
    static func getConnections(completeHandler: @escaping ([ClashConnectionBaseSnapShot.Connection]) -> Void) {
        guard let request = req("/connections") else {
            completeHandler([])
            return
        }
        request.responseDecodable(of: ClashConnectionBaseSnapShot.self) { resp in
            switch resp.result {
            case let .success(snapshot):
                completeHandler(snapshot.connections)
            case .failure:
                assertionFailure()
                completeHandler([])
            }
        }
    }

    static func closeConnection(_ id: String) {
        req(pathComponents: ["connections", id], method: .delete)?.response { _ in }
    }

    static func closeAllConnection() {
        if useDirectApi() {
            clash_closeAllConnections()
        } else {
            req("/connections", method: .delete)?.response { _ in }
        }
    }

    // MARK: - Providers

    struct AllProviders {
        var proxies = [String]()
        var rules = [String]()
    }

    static func requestExternalProviderNames(completeHandler: @escaping (AllProviders) -> Void) {
        var providers = AllProviders()
        let group = DispatchGroup()
        group.enter()
        if let request = ApiRequest.req("/providers/proxies") {
            request.responseData { resp in
                switch resp.result {
                case let .success(res):
                    let json = JSON(res)
                    let provoders = json["providers"].dictionaryValue
                        .filter { $0.value["vehicleType"] == "HTTP" }.map(\.key)
                    providers.proxies = provoders
                case let .failure(err):
                    Logger.log(err.localizedDescription, level: .warning)
                }
                group.leave()
            }
        } else {
            group.leave()
        }

        group.enter()
        if let request = ApiRequest.req("/providers/rules") {
            request.responseData { resp in
                switch resp.result {
                case let .success(res):
                    let json = JSON(res)
                    let provoders = json["providers"].dictionaryValue
                        .filter { $0.value["vehicleType"] == "HTTP" }.map(\.key)
                    providers.rules = provoders
                case let .failure(err):
                    Logger.log("request rule providers failed: \(err.localizedDescription)", level: .warning)
                }
                group.leave()
            }
        } else {
            group.leave()
        }
        group.notify(queue: .main) {
            completeHandler(providers)
        }
    }

    enum ProviderType {
        case proxy
        case rule
    }

    static func updateProvider(name: String, type: ProviderType, completeHandler: @escaping (Bool) -> Void) {
        updateProviderResult(name: name, type: type) { result in
            completeHandler({
                if case .success = result { return true }
                return false
            }())
        }
    }

    static func updateProviderResult(name: String, type: ProviderType, completeHandler: @escaping (ControllerEndpointResult) -> Void) {
        let pathComponents: [String]
        switch type {
        case .proxy:
            pathComponents = ["providers", "proxies", name]
        case .rule:
            pathComponents = ["providers", "rules", name]
        }
        guard let request = ApiRequest.req(pathComponents: pathComponents, method: .put) else {
            completeHandler(unavailableEndpointResult())
            return
        }
        request.responseData { resp in
            completeHandler(endpointResult(from: resp, defaultMessage: NSLocalizedString("Failed to update the selected provider.", comment: "")))
        }
    }

    static func resetFakeIpCache(completeHandler: ((ControllerEndpointResult) -> Void)? = nil) {
        guard let request = ApiRequest.req("/cache/fakeip/flush", method: .post) else {
            completeHandler?(unavailableEndpointResult())
            return
        }
        request.responseData { resp in
            Logger.log("flush fake ip: \(resp.response?.statusCode ?? -1)")
            completeHandler?(endpointResult(from: resp, defaultMessage: NSLocalizedString("Failed to flush the fake-IP cache.", comment: "")))
        }
    }

    static func requestSmartWeights(completeHandler: @escaping (ControllerDecodedResult<SmartWeightsResponse>) -> Void) {
        guard let request = req("/group/weights") else {
            completeHandler(unavailableDecodedResult())
            return
        }
        request.responseData { resp in
            let result: ControllerDecodedResult<SmartWeightsResponse> = decodedResult(from: resp,
                                                                                      as: SmartWeightsResponse.self,
                                                                                      defaultMessage: NSLocalizedString("Failed to load Smart weights.", comment: ""))
            if case let .failed(message) = result {
                Logger.log("request smart weights failed: \(message)", level: .warning)
            }
            completeHandler(result)
        }
    }

    static func requestSmartWeights(group: String, completeHandler: @escaping (ControllerDecodedResult<[SmartNodeWeight]>) -> Void) {
        guard let request = req(pathComponents: ["group", group, "weights"]) else {
            completeHandler(unavailableDecodedResult())
            return
        }
        request.responseData { resp in
            switch jsonResult(from: resp, defaultMessage: NSLocalizedString("Failed to load Smart group weights.", comment: "")) {
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
            request = req(pathComponents: ["cache", "smart", "flush", configName], method: .post)
        } else {
            request = req("/cache/smart/flush", method: .post)
        }
        guard let request else {
            completeHandler?(unavailableEndpointResult())
            return
        }
        request.responseData { resp in
            completeHandler?(endpointResult(from: resp, defaultMessage: NSLocalizedString("Failed to flush the Smart cache.", comment: "")))
        }
    }

    static func blockSmartConnection(_ id: String, completeHandler: ((ControllerEndpointResult) -> Void)? = nil) {
        guard let request = req(pathComponents: ["connections", "smart", id], method: .delete) else {
            completeHandler?(unavailableEndpointResult())
            return
        }
        request.responseData { resp in
            completeHandler?(endpointResult(from: resp, defaultMessage: NSLocalizedString("Failed to block the Smart connection.", comment: "")))
        }
    }

    static func updateSmartLightGBMModel(completeHandler: @escaping (ControllerEndpointResult) -> Void) {
        guard let request = req("/upgrade/lgbm", method: .post) else {
            completeHandler(unavailableEndpointResult())
            return
        }
        request.responseData { resp in
            completeHandler(endpointResult(from: resp, defaultMessage: NSLocalizedString("LightGBM model update failed.", comment: "")))
        }
    }

    static func requestCoreVersion(completeHandler: @escaping (String?) -> Void) {
        requestCoreVersionResult { result in
            switch result {
            case let .success(info):
                completeHandler(info.version)
            case .unsupported:
                Logger.log("request core version unsupported", level: .warning)
                completeHandler(nil)
            case let .unauthorized(message), let .failed(message):
                Logger.log("request core version failed: \(message)", level: .warning)
                completeHandler(nil)
            }
        }
    }

    static func requestCoreVersionResult(completeHandler: @escaping (ControllerDecodedResult<CoreVersionInfo>) -> Void) {
        guard let request = req("/version") else {
            completeHandler(unavailableDecodedResult())
            return
        }
        request.responseData { response in
            completeHandler(decodedResult(from: response, as: CoreVersionInfo.self, defaultMessage: NSLocalizedString("Failed to load core version.", comment: "")))
        }
    }

    static func requestControllerConfig(completeHandler: @escaping (ControllerDecodedResult<ClashConfig>) -> Void) {
        guard let request = req("/configs") else {
            completeHandler(unavailableDecodedResult())
            return
        }
        request.responseData { response in
            completeHandler(decodedResult(from: response, as: ClashConfig.self, defaultMessage: NSLocalizedString("Failed to load config state.", comment: "")))
        }
    }
}

// MARK: - Stream Apis

extension ApiRequest {
    func resetStreamApis() {
        resetLogStreamApi()
        resetTrafficStreamApi()
    }

    func resetLogStreamApi() {
        loggingWebSocketRetryTimer?.invalidate()
        loggingWebSocketRetryTimer = nil
        loggingWebSocketRetryDelay = 1
        requestLog()
    }

    func resetTrafficStreamApi() {
        trafficWebSocketRetryTimer?.invalidate()
        trafficWebSocketRetryTimer = nil
        trafficWebSocketRetryDelay = 1
        requestTrafficInfo()
    }

    private func requestTrafficInfo() {
        if ApiRequest.useDirectApi() {
            trafficWebSocket?.disconnect(forceTimeout: 0.5)
            return
        }
        trafficWebSocketRetryTimer?.invalidate()
        trafficWebSocketRetryTimer = nil
        trafficWebSocket?.disconnect(forceTimeout: 0.5)

        guard let url = try? ControllerEndpointBuilder.websocketURL(path: "/traffic") else {
            Logger.log("traffic websocket unavailable: invalid controller URL", level: .warning)
            return
        }
        let socket = WebSocket(url: url)

        for header in ApiRequest.authHeader() {
            socket.request.setValue(header.value, forHTTPHeaderField: header.name)
        }
        socket.delegate = self
        socket.connect()
        trafficWebSocket = socket
    }

    private func requestLog() {
        if ApiRequest.useDirectApi() {
            loggingWebSocket?.disconnect(forceTimeout: 1)
            return
        }
        loggingWebSocketRetryTimer?.invalidate()
        loggingWebSocketRetryTimer = nil
        loggingWebSocket?.disconnect(forceTimeout: 1)

        guard let url = try? ControllerEndpointBuilder.websocketURL(path: "/logs",
                                                                    queryItems: [URLQueryItem(name: "level",
                                                                                              value: ConfigManager.selectLoggingApiLevel.rawValue)]) else {
            Logger.log("log websocket unavailable: invalid controller URL", level: .warning)
            return
        }
        let socket = WebSocket(url: url)
        for header in ApiRequest.authHeader() {
            socket.request.setValue(header.value, forHTTPHeaderField: header.name)
        }
        socket.delegate = self
        socket.callbackQueue = logQueue
        socket.connect()
        loggingWebSocket = socket
    }
}

extension ApiRequest: WebSocketDelegate {
    func websocketDidConnect(socket: WebSocketClient) {
        guard let webSocket = socket as? WebSocket else { return }
        if webSocket == trafficWebSocket {
            trafficWebSocketRetryDelay = 1
            Logger.log("trafficWebSocket did Connect", level: .debug)
        } else {
            loggingWebSocketRetryDelay = 1
            Logger.log("loggingWebSocket did Connect", level: .debug)
        }
    }

    func websocketDidDisconnect(socket: WebSocketClient, error: Error?) {
        guard let err = error else {
            return
        }

        Logger.log(err.localizedDescription, level: .error)

        guard let webSocket = socket as? WebSocket else { return }

        if webSocket == trafficWebSocket {
            Logger.log("trafficWebSocket did disconnect", level: .debug)
            trafficWebSocketRetryTimer?.invalidate()
            trafficWebSocketRetryTimer =
                Timer.scheduledTimer(withTimeInterval: trafficWebSocketRetryDelay, repeats: false, block: {
                    [weak self] _ in
                    if self?.trafficWebSocket?.isConnected == true { return }
                    self?.requestTrafficInfo()
                })
            trafficWebSocketRetryDelay *= 2
        } else {
            Logger.log("loggingWebSocket did disconnect", level: .debug)
            loggingWebSocketRetryTimer =
                Timer.scheduledTimer(withTimeInterval: loggingWebSocketRetryDelay, repeats: false, block: {
                    [weak self] _ in
                    if self?.loggingWebSocket?.isConnected == true { return }
                    self?.requestLog()
                })
            loggingWebSocketRetryDelay *= 2
        }
    }

    func websocketDidReceiveMessage(socket: WebSocketClient, text: String) {
        guard let webSocket = socket as? WebSocket else { return }
        let json = JSON(parseJSON: text)
        if webSocket == trafficWebSocket {
            delegate?.didUpdateTraffic(up: json["up"].intValue, down: json["down"].intValue)
        } else {
            delegate?.didGetLog(log: json["payload"].stringValue, level: json["type"].string ?? "info")
        }
    }

    func websocketDidReceiveData(socket: WebSocketClient, data: Data) {}
}
