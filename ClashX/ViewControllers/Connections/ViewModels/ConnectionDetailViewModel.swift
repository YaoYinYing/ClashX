//
//  ConnectionDetailViewModel.swift
//  ClashX
//
//  Created by yicheng on 2023/7/8.
//  Copyright © 2023 west2online. All rights reserved.
//

import AppKit
import Combine

@available(macOS 10.15, *)
class ConnectionDetailViewModel {
    @Published var processName = ""
    @Published var processImage: NSImage?
    @Published var remoteHost = ""

    @Published var entry = ""
    @Published var networkType = ""
    @Published var totalUpload = ""
    @Published var totalDownload = ""
    @Published var maxUpload = ""
    @Published var maxDownload = ""
    @Published var currentUpload = ""
    @Published var currentDownload = ""
    @Published var rule = ""
    @Published var chain = ""
    @Published var sourceIP = ""
    @Published var destination = ""
    @Published var applicationPath: String? = ""
    @Published var otherText = ""
    @Published var showCloseButton = false
    @Published var showSmartBlockButton = false

    private var uuid = ""
    var cancellable = Set<AnyCancellable>()

    func accept(connection: ClashConnectionSnapShot.Connection?) {
        cancellable.removeAll()
        guard let connection else { return }
        if let pid = connection.metadata.pid {
            processName = "\(connection.metadata.processName ?? NSLocalizedString("Unknown", comment: "")) (\(pid))"
        } else {
            processName = connection.metadata.processName ?? NSLocalizedString("Unknown", comment: "")
        }
        uuid = connection.id
        showCloseButton = connection.status == .connecting
        showSmartBlockButton = connection.status == .connecting && !(connection.metadata.smartTarget ?? "").isEmpty
        processImage = connection.metadata.processImage
        applicationPath = connection.metadata.processPath
        let area = clash_getCountryForIp(connection.metadata.destinationIP.goStringBuffer()).toString()
        let areaString = "\(flag(from: area))\(area)"
        if connection.metadata.host.isEmpty {
            remoteHost = "\(connection.metadata.destinationIP):\(connection.metadata.destinationPort) \(areaString)"
        } else {
            remoteHost = "\(connection.metadata.host):\(connection.metadata.destinationPort) \(areaString)"
        }

        entry = connection.metadata.type
        networkType = formatNetworkType(connection.metadata)

        connection.$download.map { SpeedUtils.getNetString(for: $0) }.weakAssign(to: \.totalDownload, on: self).store(in: &cancellable)
        connection.$upload.map { SpeedUtils.getNetString(for: $0) }.weakAssign(to: \.totalUpload, on: self).store(in: &cancellable)

        connection.$maxUploadSpeed.map { SpeedUtils.getSpeedString(for: $0) }.weakAssign(to: \.maxUpload, on: self).store(in: &cancellable)
        connection.$maxDownloadSpeed.map { SpeedUtils.getSpeedString(for: $0) }.weakAssign(to: \.maxDownload, on: self).store(in: &cancellable)

        connection.$uploadSpeed.map { SpeedUtils.getSpeedString(for: $0) }.weakAssign(to: \.currentUpload, on: self).store(in: &cancellable)
        connection.$downloadSpeed.map { SpeedUtils.getSpeedString(for: $0) }.weakAssign(to: \.currentDownload, on: self).store(in: &cancellable)

        rule = formatRuleSummary(for: connection)
        chain = formatRouteSummary(for: connection)
        sourceIP = connection.metadata.sourceIP.appending(":").appending(connection.metadata.sourcePort)
        destination = connection.metadata.destinationIP.appending(":").appending(connection.metadata.destinationPort)
        otherText = formatOtherSummary(for: connection)
    }

    func flag(from country: String) -> String {
        if country.isEmpty { return "" }
        let base: UInt32 = 127397
        var s = ""
        for v in country.uppercased().unicodeScalars {
            s.unicodeScalars.append(UnicodeScalar(base + v.value)!)
        }
        return s
    }

    func closeConnection() {
        ApiRequest.closeConnection(uuid)
    }

    func blockSmartConnection() {
        ApiRequest.blockSmartConnection(uuid)
    }

    private func formatNetworkType(_ metadata: ClashConnectionSnapShot.MetaData) -> String {
        var parts = [metadata.network]
        if !metadata.dnsMode.isEmpty {
            parts.append("DNS \(metadata.dnsMode)")
        }
        return parts.joined(separator: " / ")
    }

    private func formatRuleSummary(for connection: ClashConnectionSnapShot.Connection) -> String {
        var lines = [String]()
        let matchedRule = connection.rule.isEmpty ? NSLocalizedString("Unknown", comment: "") : connection.rule
        lines.append("Matched: \(matchedRule)")

        let payload = connection.rulePayload.trimmingCharacters(in: .whitespacesAndNewlines)
        if !payload.isEmpty {
            lines.append("Payload: \(payload)")
        } else {
            lines.append("Payload: \(NSLocalizedString("none", comment: ""))")
        }

        if let specialProxy = connection.metadata.specialProxy, !specialProxy.isEmpty {
            lines.append("Special Proxy: \(specialProxy)")
        }

        return lines.joined(separator: "\n")
    }

    private func formatRouteSummary(for connection: ClashConnectionSnapShot.Connection) -> String {
        let chain = connection.chains.filter { !$0.isEmpty }
        var lines = [String]()

        if let selectedProxy = chain.last {
            lines.append("Selected: \(selectedProxy)")
        } else {
            lines.append("Selected: \(NSLocalizedString("Direct or not reported", comment: ""))")
        }

        if chain.isEmpty {
            lines.append("Path: \(NSLocalizedString("No proxy chain was reported by the controller.", comment: ""))")
        } else {
            lines.append("Path: \(chain.joined(separator: " -> "))")
            if chain.count > 1 {
                lines.append("Hops: \(chain.count)")
            }
        }

        if let smartTarget = connection.metadata.smartTarget, !smartTarget.isEmpty {
            lines.append("Smart Target: \(smartTarget)")
        }

        return lines.joined(separator: "\n")
    }

    private func formatOtherSummary(for connection: ClashConnectionSnapShot.Connection) -> String {
        var lines = [String]()

        if let error = connection.error, !error.isEmpty {
            lines.append("Error: \(error)")
        }

        lines.append("Started: \(DateFormatter.localizedString(from: connection.start, dateStyle: .short, timeStyle: .medium))")
        if let duration = DateComponentsFormatter.connectionDetailDuration.string(from: connection.start, to: Date()) {
            lines.append("Duration: \(duration)")
        }

        if let processPath = applicationPath, !processPath.isEmpty {
            lines.append("Process Path: \(processPath)")
        }

        if let smartBlock = connection.metadata.smartBlock, !smartBlock.isEmpty {
            lines.append("Smart Block: \(smartBlock)")
        }

        if let sourceIPASN = connection.metadata.sourceIPASN, !sourceIPASN.isEmpty {
            lines.append("Source ASN: \(sourceIPASN)")
        }
        if let destinationIPASN = connection.metadata.destinationIPASN, !destinationIPASN.isEmpty {
            lines.append("Destination ASN: \(destinationIPASN)")
        }
        if let sourceGeoIP = connection.metadata.sourceGeoIP, !sourceGeoIP.isEmpty {
            lines.append("Source GeoIP: \(sourceGeoIP.joined(separator: ", "))")
        }
        if let destinationGeoIP = connection.metadata.destinationGeoIP, !destinationGeoIP.isEmpty {
            lines.append("Destination GeoIP: \(destinationGeoIP.joined(separator: ", "))")
        }

        return lines.joined(separator: "\n")
    }
}

private extension DateComponentsFormatter {
    static let connectionDetailDuration: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .dropLeading
        return formatter
    }()
}
