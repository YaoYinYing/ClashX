import Foundation

final class ConfigManager {
    static let shared = ConfigManager()

    var isRunning = true
    var overrideApiURL: URL?
    var apiPort = "9090"
}

@inline(__always)
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("controller_endpoint_builder_smoke failed: \(message)\n", stderr)
        exit(1)
    }
}

func expectURL(_ url: URL, equals expected: String, _ message: String) {
    expect(url.absoluteString == expected, "\(message) expected=\(expected) actual=\(url.absoluteString)")
}

func runControllerEndpointBuilderSmoke() throws {
    ConfigManager.shared.isRunning = true
    ConfigManager.shared.overrideApiURL = nil
    ConfigManager.shared.apiPort = "9090"

    try expectURL(ControllerEndpointBuilder.httpURL(path: "/configs"),
                  equals: "http://127.0.0.1:9090/configs",
                  "embedded http path with leading slash")
    try expectURL(ControllerEndpointBuilder.websocketURL(path: "/traffic"),
                  equals: "ws://127.0.0.1:9090/traffic",
                  "embedded websocket path")

    ConfigManager.shared.overrideApiURL = URL(string: "http://127.0.0.1:9090/")
    try expectURL(ControllerEndpointBuilder.httpURL(path: "/configs"),
                  equals: "http://127.0.0.1:9090/configs",
                  "external base with trailing slash")

    ConfigManager.shared.overrideApiURL = URL(string: "https://example.com:9443")
    try expectURL(ControllerEndpointBuilder.websocketURL(path: "/logs"),
                  equals: "wss://example.com:9443/logs",
                  "https converts to wss")

    try expectURL(ControllerEndpointBuilder.httpURL(path: "configs"),
                  equals: "https://example.com:9443/configs",
                  "path without leading slash")

    try expectURL(ControllerEndpointBuilder.httpURL(path: "/group/test", queryItems: [
        URLQueryItem(name: "timeout", value: "5000"),
        URLQueryItem(name: "url", value: "https://example.net/ping")
    ]),
    equals: "https://example.com:9443/group/test?timeout=5000&url=https://example.net/ping",
    "query items")

    ConfigManager.shared.overrideApiURL = URL(string: "https://example.com:9443/base?token=secret#frag")
    try expectURL(ControllerEndpointBuilder.httpURL(path: "/configs"),
                  equals: "https://example.com:9443/base/configs",
                  "query and fragment stripped from base")

    ConfigManager.shared.overrideApiURL = URL(string: "https://user:pass@example.com:9443/base")
    let userInfoURL = try ControllerEndpointBuilder.httpURL(path: "/configs")
    expectURL(userInfoURL,
              equals: "https://example.com:9443/base/configs",
              "userinfo stripped from base")
    expect(!userInfoURL.absoluteString.contains("user"), "userinfo leaked into endpoint")

    let proxySpaceURL = try ControllerEndpointBuilder.httpURL(pathComponents: ["proxies", "Proxy A"])
    expectURL(proxySpaceURL,
              equals: "https://example.com:9443/base/proxies/Proxy%20A",
              "raw space component encoded exactly once")
    expect(!proxySpaceURL.absoluteString.contains("%2520"), "space component double-encoded")

    let chineseURL = try ControllerEndpointBuilder.httpURL(pathComponents: ["group", "香港 节点"])
    expectURL(chineseURL,
              equals: "https://example.com:9443/base/group/%E9%A6%99%E6%B8%AF%20%E8%8A%82%E7%82%B9",
              "raw Chinese component encoded exactly once")
    expect(!chineseURL.absoluteString.contains("%25E9"), "Chinese component double-encoded")

    let slashURL = try ControllerEndpointBuilder.httpURL(pathComponents: ["providers", "proxies", "Group/A"])
    expectURL(slashURL,
              equals: "https://example.com:9443/base/providers/proxies/Group%2FA",
              "slash inside raw component stays in one path segment")

    let percentURL = try ControllerEndpointBuilder.httpURL(pathComponents: ["proxies", "50% Node"])
    expectURL(percentURL,
              equals: "https://example.com:9443/base/proxies/50%25%20Node",
              "literal percent encoded as %25")

    // Static string paths are only for literal endpoints, not pre-encoded names.
    let staticPathURL = try ControllerEndpointBuilder.httpURL(path: "/group/test")
    expectURL(staticPathURL,
              equals: "https://example.com:9443/base/group/test",
              "static path API remains available for literal endpoints")
}

@main
enum ControllerEndpointBuilderSmokeMain {
    static func main() {
        do {
            try runControllerEndpointBuilderSmoke()
            print("controller_endpoint_builder_smoke passed")
        } catch {
            fputs("controller_endpoint_builder_smoke failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
