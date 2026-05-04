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
    // `path` is for static literal endpoint paths such as "/configs" or
    // "/providers/proxies". `pathComponents` accepts raw, unescaped
    // components only; callers must not pass `.encoded` values there because
    // each component is percent-encoded exactly once by the builder.
    static func httpURL(path: String, queryItems: [URLQueryItem] = []) throws -> URL {
        try composeURL(baseURL: baseHTTPURL(), path: path, queryItems: queryItems)
    }

    static func httpURL(pathComponents: [String], queryItems: [URLQueryItem] = []) throws -> URL {
        try composeURL(baseURL: baseHTTPURL(), pathComponents: pathComponents, queryItems: queryItems)
    }

    static func websocketURL(path: String, queryItems: [URLQueryItem] = []) throws -> URL {
        try composeURL(baseURL: baseWebSocketURL(), path: path, queryItems: queryItems)
    }

    static func websocketURL(pathComponents: [String], queryItems: [URLQueryItem] = []) throws -> URL {
        try composeURL(baseURL: baseWebSocketURL(), pathComponents: pathComponents, queryItems: queryItems)
    }

    static func baseHTTPURL() throws -> URL {
        guard ConfigManager.shared.isRunning else {
            throw ControllerEndpointError.coreStopped
        }
        if let override = ConfigManager.shared.overrideApiURL {
            return try normalizeExternalHTTPBaseURL(override)
        }
        guard let url = URL(string: "http://127.0.0.1:\(ConfigManager.shared.apiPort)") else {
            throw ControllerEndpointError.invalidBaseURL(ConfigManager.shared.apiPort)
        }
        return url
    }

    static func baseWebSocketURL() throws -> URL {
        guard ConfigManager.shared.isRunning else {
            throw ControllerEndpointError.coreStopped
        }
        if let override = ConfigManager.shared.overrideApiURL {
            return try normalizeExternalWebSocketBaseURL(override)
        }
        guard var components = URLComponents(string: "http://127.0.0.1:\(ConfigManager.shared.apiPort)") else {
            throw ControllerEndpointError.invalidBaseURL(ConfigManager.shared.apiPort)
        }
        components.scheme = "ws"
        guard let url = components.url else {
            throw ControllerEndpointError.invalidBaseURL(ConfigManager.shared.apiPort)
        }
        return url
    }

    static func sanitizedControllerIdentityBaseString() -> String {
        if let override = ConfigManager.shared.overrideApiURL,
           let sanitized = try? normalizeExternalHTTPBaseURL(override) {
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
        return try composeURL(baseURL: baseURL, pathComponents: segments, queryItems: queryItems)
    }

    static func composeURL(baseURL: URL, pathComponents: [String], queryItems: [URLQueryItem] = []) throws -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw ControllerEndpointError.invalidEndpoint(pathComponents.joined(separator: "/"))
        }
        let encodedBasePath = components.percentEncodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let encodedComponents = try pathComponents.map { component in
            guard let encoded = component.addingPercentEncoding(withAllowedCharacters: pathComponentAllowedCharacters) else {
                throw ControllerEndpointError.invalidEndpoint(component)
            }
            return encoded
        }
        let joinedPath = ([encodedBasePath] + encodedComponents)
            .filter { !$0.isEmpty }
            .joined(separator: "/")
        components.percentEncodedPath = "/" + joinedPath
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let finalURL = components.url else {
            throw ControllerEndpointError.invalidEndpoint(pathComponents.joined(separator: "/"))
        }
        return finalURL
    }

    private static let pathComponentAllowedCharacters: CharacterSet = {
        var set = CharacterSet.urlPathAllowed
        set.remove(charactersIn: "/%")
        return set
    }()

    // HTTP callers may receive a controller URL written in WebSocket form.
    // We map ws->http and wss->https so one override can still serve both
    // HTTP endpoint requests and WebSocket streams without leaking userinfo,
    // queries, or fragments into the derived endpoint URLs.
    private static func normalizeExternalHTTPBaseURL(_ baseURL: URL) throws -> URL {
        try normalizeExternalBaseURL(baseURL) { scheme in
            switch scheme {
            case "http", "https":
                return scheme
            case "ws":
                return "http"
            case "wss":
                return "https"
            default:
                return nil
            }
        }
    }

    private static func normalizeExternalWebSocketBaseURL(_ baseURL: URL) throws -> URL {
        try normalizeExternalBaseURL(baseURL) { scheme in
            switch scheme {
            case "http":
                return "ws"
            case "https":
                return "wss"
            case "ws", "wss":
                return scheme
            default:
                return nil
            }
        }
    }

    private static func normalizeExternalBaseURL(_ baseURL: URL, schemeTransform: (String) -> String?) throws -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              let normalizedScheme = schemeTransform(scheme),
              components.host != nil else {
            throw ControllerEndpointError.invalidBaseURL(baseURL.absoluteString)
        }

        components.scheme = normalizedScheme
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
