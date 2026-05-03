//
//  SmartXRedactor.swift
//  ClashX
//
//  Created by Codex on 2026/5/3.
//

import Foundation

enum SmartXRedactor {
    private static let tokenLikeQueryKeys = Set([
        "token", "secret", "password", "passwd", "apikey", "api-key",
        "access_token", "access-key", "key", "signature", "sig"
    ])

    static func redactURLString(_ rawURL: String?) -> String? {
        guard let rawURL else { return nil }
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard var components = URLComponents(string: trimmed) else {
            return "<redacted-url>"
        }

        components.user = nil
        components.password = nil
        components.fragment = nil
        if components.queryItems != nil {
            components.queryItems = redactedQueryItems(components.queryItems)
        }
        return components.string ?? "<redacted-url>"
    }

    static func redactPath(_ path: String?) -> String? {
        guard let path else { return nil }
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let home = NSHomeDirectory()
        if trimmed == home {
            return "~"
        }
        if trimmed.hasPrefix(home + "/") {
            return "~" + String(trimmed.dropFirst(home.count))
        }
        return trimmed
    }

    static func sanitizeText(_ text: String) -> String {
        var result = text
        result = redactHomeDirectory(in: result)
        result = redactProxyURIs(in: result)
        result = redactHTTPURLs(in: result)
        result = redactAuthorizationStyleValues(in: result)
        result = redactTokenStyleKeyValues(in: result)
        return result
    }

    private static func redactedQueryItems(_ queryItems: [URLQueryItem]?) -> [URLQueryItem]? {
        queryItems?.map { item in
            let lowered = item.name.lowercased()
            if tokenLikeQueryKeys.contains(lowered) {
                return URLQueryItem(name: item.name, value: "<redacted>")
            }
            if item.value != nil {
                return URLQueryItem(name: item.name, value: "<redacted>")
            }
            return item
        }
    }

    private static func redactProxyURIs(in text: String) -> String {
        redactMatches(in: text,
                      pattern: #"(?i)\b(?:ss|ssr|vmess|vless|trojan|hysteria2?|tuic|wireguard|mieru|anytls|masque)://\S+"#) { _, _ in
            "<redacted-proxy-uri>"
        }
    }

    private static func redactHTTPURLs(in text: String) -> String {
        redactMatches(in: text,
                      pattern: #"(?i)\b(?:https?|wss?)://\S+"#) { match, source in
            let rawURL = source.substring(with: match.range)
            return redactURLString(rawURL) ?? "<redacted-url>"
        }
    }

    private static func redactAuthorizationStyleValues(in text: String) -> String {
        redactMatches(in: text,
                      pattern: #"(?i)\b(?:authorization|proxy-authorization)\s*[:=]\s*(?:bearer|basic)?\s*[^\s,;]+"#) { match, source in
            let raw = source.substring(with: match.range)
            guard let separator = raw.firstIndex(where: { $0 == ":" || $0 == "=" }) else {
                return "authorization: <redacted>"
            }
            return "\(raw[..<separator])\(raw[separator]) <redacted>"
        }
    }

    private static func redactTokenStyleKeyValues(in text: String) -> String {
        redactMatches(in: text,
                      pattern: #"(?i)(?<![?&])\b(?:token|secret|password|passwd|apikey|api-key|access-key|proxy-secret)\s*[:=]\s*[^\s,;]+"#) { match, source in
            let raw = source.substring(with: match.range)
            guard let separator = raw.firstIndex(where: { $0 == ":" || $0 == "=" }) else {
                return "<redacted>"
            }
            return "\(raw[..<separator])\(raw[separator]) <redacted>"
        }
    }

    private static func redactHomeDirectory(in text: String) -> String {
        let home = NSHomeDirectory()
        guard !home.isEmpty else { return text }
        return text.replacingOccurrences(of: home, with: "~")
    }

    private static func redactMatches(in text: String,
                                      pattern: String,
                                      replacement: (NSTextCheckingResult, NSString) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return text
        }

        let source = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: source.length))
        guard !matches.isEmpty else { return text }

        var result = text
        for match in matches.reversed() {
            let replacementText = replacement(match, source)
            if let range = Range(match.range, in: result) {
                result.replaceSubrange(range, with: replacementText)
            }
        }
        return result
    }
}
