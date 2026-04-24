//
//  ClashProvider.swift
//  ClashX
//
//  Created by yichengchen on 2019/12/14.
//  Copyright © 2019 west2online. All rights reserved.
//

import Cocoa

class ClashProviderResp: Codable {
    let allProviders: [ClashProxyName: ClashProvider]
    lazy var providers: [ClashProxyName: ClashProvider] = allProviders.filter { $0.value.vehicleType != .Compatible }

    private enum CodingKeys: String, CodingKey {
        case allProviders = "providers"
    }

    init() {
        allProviders = [:]
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let nested = try container.nestedContainer(keyedBy: DynamicCodingKey.self, forKey: .allProviders)
        var providers = [ClashProxyName: ClashProvider]()
        for key in nested.allKeys {
            var provider = try nested.decode(ClashProvider.self, forKey: key)
            if provider.name.isEmpty {
                provider.name = key.stringValue
            }
            providers[key.stringValue] = provider
        }
        allProviders = providers
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .formatted(DateFormatter.js)
        return decoder
    }
}

private struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

class ClashProvider: Codable {
    enum ProviderType: String, Codable {
        case Proxy
        case stringProvider = "String"
        case unknown

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(Swift.String.self).lowercased()
            switch rawValue {
            case "proxy":
                self = .Proxy
            case "string":
                self = .stringProvider
            default:
                self = .unknown
            }
        }
    }

    enum ProviderVehicleType: String, Codable {
        case HTTP
        case File
        case Compatible
        case Unknown

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(String.self).lowercased()
            switch rawValue {
            case "http":
                self = .HTTP
            case "file":
                self = .File
            case "compatible":
                self = .Compatible
            default:
                self = .Unknown
            }
        }
    }

    var name: ClashProviderName
    let proxies: [ClashProxy]
    let type: ProviderType
    let vehicleType: ProviderVehicleType

    private enum CodingKeys: String, CodingKey {
        case name, proxies, type, vehicleType
    }

    init(name: ClashProviderName = "",
         proxies: [ClashProxy] = [],
         type: ProviderType = .unknown,
         vehicleType: ProviderVehicleType = .Unknown) {
        self.name = name
        self.proxies = proxies
        self.type = type
        self.vehicleType = vehicleType
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        proxies = try container.decodeIfPresent([ClashProxy].self, forKey: .proxies) ?? []
        type = try container.decodeIfPresent(ProviderType.self, forKey: .type) ?? .unknown
        vehicleType = try container.decodeIfPresent(ProviderVehicleType.self, forKey: .vehicleType) ?? .Unknown
    }
}
