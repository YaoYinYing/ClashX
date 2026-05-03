//
//  ControllerEndpointBuilder.swift
//  ClashX
//
//  Created by Codex on 2026/5/3.
//

import Foundation

enum ControllerEndpointError: LocalizedError {
    case coreStopped
    case invalidBaseURL(String)
    case invalidEndpoint(String)

    var errorDescription: String? {
        switch self {
        case .coreStopped:
            return NSLocalizedString("Core is stopped or controller is unavailable.", comment: "")
        case let .invalidBaseURL(rawValue):
            return String(format: NSLocalizedString("The active controller base URL is invalid: %@", comment: ""), rawValue)
        case let .invalidEndpoint(path):
            return String(format: NSLocalizedString("The controller endpoint path is invalid: %@", comment: ""), path)
        }
    }
}

enum ControllerEndpointBuilder {
    static func httpURL(path: String, queryItems: [URLQueryItem] = []) throws -> URL {
        try composeURL(baseURL: baseHTTPURL(), path: path, queryItems: queryItems)
    }

    static func websocketURL(path: String, queryItems: [URLQueryItem] = []) throws -> URL {
        try composeURL(baseURL: baseWebSocketURL(), path: path, queryItems: queryItems)
    }

    static func baseHTTPURL() throws -> URL {
        guard ConfigManager.shared.isRunning else {
            throw ControllerEndpointError.coreStopped
        }
        if let override = ConfigManager.shared.overrideApiURL {
            return try normalizeExternalBaseURL(override)
        }
        guard let url = URL(string: "http://127.0.0.1:\(ConfigManager.shared.apiPort)") else {
            throw ControllerEndpointError.invalidBaseURL(ConfigManager.shared.apiPort)
        }
        return url
    }

    static func baseWebSocketURL() throws -> URL {
        let baseURL = try baseHTTPURL()
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw ControllerEndpointError.invalidBaseURL(baseURL.absoluteString)
        }
        switch components.scheme?.lowercased() {
        case "http":
            components.scheme = "ws"
        case "https":
            components.scheme = "wss"
        case "ws", "wss":
            break
        default:
            throw ControllerEndpointError.invalidBaseURL(baseURL.absoluteString)
        }
        guard let url = components.url else {
            throw ControllerEndpointError.invalidBaseURL(baseURL.absoluteString)
        }
        return url
    }

    static func sanitizedControllerIdentityBaseString() -> String {
        if let override = ConfigManager.shared.overrideApiURL,
           let sanitized = try? normalizeExternalBaseURL(override) {
            return sanitized.absoluteString
        }
        return "http://127.0.0.1:\(ConfigManager.shared.apiPort)"
    }

    static func composeURL(baseURL: URL, path: String, queryItems: [URLQueryItem] = []) throws -> URL {
        guard !path.contains("?"), !path.contains("#") else {
            throw ControllerEndpointError.invalidEndpoint(path)
        }

        let segments = path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        let url = segments.reduce(baseURL) { partial, segment in
            partial.appendingPathComponent(segment)
        }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw ControllerEndpointError.invalidEndpoint(path)
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let finalURL = components.url else {
            throw ControllerEndpointError.invalidEndpoint(path)
        }
        return finalURL
    }

    private static func normalizeExternalBaseURL(_ baseURL: URL) throws -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              ["http", "https", "ws", "wss"].contains(scheme),
              components.host != nil else {
            throw ControllerEndpointError.invalidBaseURL(baseURL.absoluteString)
        }

        components.scheme = scheme
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        components.percentEncodedQuery = nil
        components.percentEncodedFragment = nil

        let normalizedPath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = normalizedPath.isEmpty ? "" : "/" + normalizedPath

        guard let url = components.url else {
            throw ControllerEndpointError.invalidBaseURL(baseURL.absoluteString)
        }
        return url
    }
}
