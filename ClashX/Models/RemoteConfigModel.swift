//
//  RemoteConfigModel.swift
//  ClashX
//
//  Created by yicheng on 2019/7/28.
//  Copyright © 2019 west2online. All rights reserved.
//

import Cocoa

enum RemoteConfigValidationState: String, Codable {
    case unknown
    case valid
    case invalid
}

enum RemoteConfigUpdateState: String, Codable {
    case never
    case succeeded
    case failed
}

class RemoteConfigModel: Codable {
    var url: String
    var name: String
    var updateTime: Date?
    var updating = false
    var isPlaceHolderName = false
    var validationState: RemoteConfigValidationState = .unknown
    var lastUpdateState: RemoteConfigUpdateState = .never
    var lastUpdateMessage: String?

    init(url: String, name: String, updateTime: Date? = nil) {
        self.url = url
        self.name = name
        self.updateTime = updateTime
    }

    private enum CodingKeys: String, CodingKey {
        case url, name, updateTime, validationState, lastUpdateState, lastUpdateMessage
    }

    func displayingTimeString() -> String {
        if updating { return NSLocalizedString("Updating", comment: "") }
        let dateFormater = DateFormatter()
        dateFormater.dateFormat = "MM-dd HH:mm"
        if let date = updateTime {
            return dateFormater.string(from: date)
        }
        return NSLocalizedString("Never", comment: "")
    }

    func validationSummary() -> String {
        switch validationState {
        case .unknown:
            return NSLocalizedString("Validation unknown", comment: "")
        case .valid:
            return NSLocalizedString("Validation passed", comment: "")
        case .invalid:
            return NSLocalizedString("Validation failed", comment: "")
        }
    }

    func updateResultSummary() -> String {
        if updating {
            return NSLocalizedString("Update in progress", comment: "")
        }

        switch lastUpdateState {
        case .never:
            return NSLocalizedString("No update result recorded yet", comment: "")
        case .succeeded:
            if let lastUpdateMessage, !lastUpdateMessage.isEmpty {
                return lastUpdateMessage
            }
            return NSLocalizedString("Last update succeeded", comment: "")
        case .failed:
            if let lastUpdateMessage, !lastUpdateMessage.isEmpty {
                return lastUpdateMessage
            }
            return NSLocalizedString("Last update failed", comment: "")
        }
    }
}

extension RemoteConfigModel: Equatable {
    static func == (lhs: RemoteConfigModel, rhs: RemoteConfigModel) -> Bool {
        return lhs.name == rhs.name && lhs.url == rhs.url
    }
}
