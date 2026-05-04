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
    private var baseOtherText = ""
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
        baseOtherText = formatOtherSummary(for: connection)
        otherText = baseOtherText
        refreshSmartExplanation(for: connection)
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
        ApiRequest.blockSmartConnection(uuid) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                Logger.log("[Connection Detail] Smart block requested for \(self.uuid)", level: .debug)
            case .unsupported:
                Logger.log("[Connection Detail] Smart block unsupported for current controller", level: .warning)
                self.appendSmartStatusLine(NSLocalizedString("Smart block request is unsupported by the active controller.", comment: ""))
            case let .unauthorized(message):
                Logger.log("[Connection Detail] Smart block unauthorized: \(message)", level: .warning)
                self.appendSmartStatusLine(String(format: NSLocalizedString("Smart block request was rejected: %@", comment: ""), message))
            case let .failed(message):
                Logger.log("[Connection Detail] Smart block failed: \(message)", level: .warning)
                self.appendSmartStatusLine(String(format: NSLocalizedString("Smart block request failed: %@", comment: ""), message))
            }
        }
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

    private func refreshSmartExplanation(for connection: ClashConnectionSnapShot.Connection) {
        let smartTarget = connection.metadata.smartTarget?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let smartBlock = connection.metadata.smartBlock?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !smartTarget.isEmpty || !smartBlock.isEmpty else { return }

        let connectionID = connection.id
        let modelStatus = formatModelStatus()
        let loadingText = [baseOtherText, "Smart Explanation\n-----------------\nLoading Smart group and weight context...\n\(modelStatus)"]
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        otherText = loadingText

        ApiRequest.getMergedProxyData { [weak self] proxyInfo in
            guard let self, self.uuid == connectionID else { return }
            let smartGroups = proxyInfo?.proxyGroups.filter { $0.type == .smart } ?? []
            let candidateGroups = self.matchingSmartGroups(for: connection, in: smartGroups)

            ApiRequest.requestSmartWeights { [weak self] response in
                guard let self, self.uuid == connectionID else { return }
                let explanation = self.formatSmartExplanation(for: connection,
                                                              candidateGroups: candidateGroups,
                                                              weightsResult: response,
                                                              modelStatus: modelStatus)
                self.otherText = [self.baseOtherText, explanation]
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n\n")
            }
        }
    }

    private func matchingSmartGroups(for connection: ClashConnectionSnapShot.Connection, in groups: [ClashProxy]) -> [ClashProxy] {
        let smartTarget = connection.metadata.smartTarget?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let chainEntries = Set(connection.chains.filter { !$0.isEmpty })

        let chainMatches = groups.filter { chainEntries.contains($0.name) }
        let currentMatches = groups.filter { $0.now == smartTarget }
        let memberMatches = groups.filter { ($0.all ?? []).contains(smartTarget) }

        var ordered = [ClashProxy]()
        for group in chainMatches + currentMatches + memberMatches {
            if !ordered.contains(where: { $0.name == group.name }) {
                ordered.append(group)
            }
        }
        return ordered
    }

    private func formatSmartExplanation(for connection: ClashConnectionSnapShot.Connection,
                                        candidateGroups: [ClashProxy],
                                        weightsResult: ControllerDecodedResult<SmartWeightsResponse>,
                                        modelStatus: String) -> String {
        let smartTarget = connection.metadata.smartTarget?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let smartBlock = connection.metadata.smartBlock?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var lines = [
            "Smart Explanation",
            "-----------------"
        ]

        if !smartTarget.isEmpty {
            lines.append("Target Node: \(smartTarget)")
        } else {
            lines.append("Target Node: not reported")
        }

        if !smartBlock.isEmpty {
            lines.append("Block Reason: \(smartBlock)")
        }

        lines.append(modelStatus)

        let weightsResponse: SmartWeightsResponse?
        switch weightsResult {
        case let .success(response):
            weightsResponse = response
        case .unsupported:
            weightsResponse = nil
            lines.append("Weights Endpoint: unsupported by the active controller.")
        case let .unauthorized(message):
            weightsResponse = nil
            lines.append("Weights Endpoint: unauthorized (\(message))")
        case let .failed(message):
            weightsResponse = nil
            lines.append("Weights Endpoint: failed (\(message))")
        }

        guard !candidateGroups.isEmpty else {
            lines.append("Smart Group: unable to map this connection to a Smart group from current proxy data.")
            if weightsResponse == nil {
                lines.append("Weights: unavailable from the active controller.")
            }
            lines.append("Decision Note: this is only partial Smart context because no matching Smart group could be inferred.")
            return lines.joined(separator: "\n")
        }

        let weightMap = weightsResponse?.weights ?? [:]
        for group in candidateGroups.prefix(2) {
            lines.append("Smart Group: \(group.name)")
            lines.append("Current Selection: \(group.now ?? NSLocalizedString("not reported", comment: ""))")

            let groupWeights = weightMap[group.name] ?? []
            if let targetWeight = groupWeights.first(where: { $0.name == smartTarget }) {
                lines.append("Target Rank: \(targetWeight.rank.isEmpty ? NSLocalizedString("not reported", comment: "") : targetWeight.rank)")
                lines.append("Target Weight: \(String(format: "%.2f", targetWeight.weight))")
            } else if !smartTarget.isEmpty {
                lines.append("Target Weight: unavailable for the reported target node")
            }

            let topNodes = groupWeights
                .sorted { lhs, rhs in
                    if lhs.weight == rhs.weight {
                        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                    }
                    return lhs.weight > rhs.weight
                }
                .prefix(3)
                .map { weight in
                    let rank = weight.rank.isEmpty ? "?" : weight.rank
                    return "\(weight.name) (\(String(format: "%.2f", weight.weight)), #\(rank))"
                }

            if topNodes.isEmpty {
                lines.append(weightsResponse == nil
                    ? "Weights: unavailable from the active controller."
                    : "Weights: no entries were reported for this Smart group.")
            } else {
                lines.append("Top Candidates: \(topNodes.joined(separator: ", "))")
            }

            if !smartTarget.isEmpty {
                if group.now == smartTarget {
                    lines.append("Decision Note: the reported Smart target matches the current node selected by this group.")
                } else if let currentNode = group.now, !currentNode.isEmpty {
                    lines.append("Decision Note: the connection reported target \(smartTarget), but the group currently points at \(currentNode).")
                } else {
                    lines.append("Decision Note: the controller reported a target node, but the group's current selection was not available.")
                }
            }
        }

        if let message = weightsResponse?.message?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty {
            lines.append("Weights Message: \(message)")
        }

        return lines.joined(separator: "\n")
    }

    private func appendSmartStatusLine(_ line: String) {
        let next = [otherText, line]
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        otherText = next
    }

    private func formatModelStatus() -> String {
        let path = Paths.smartLightGBMModelPath
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: path) else {
            return "Model File: missing"
        }

        let attributes = try? fileManager.attributesOfItem(atPath: path)
        let size = (attributes?[.size] as? NSNumber).map {
            ByteCountFormatter.string(fromByteCount: $0.int64Value, countStyle: .file)
        } ?? "unknown size"
        let modified = (attributes?[.modificationDate] as? Date).map {
            DateFormatter.localizedString(from: $0, dateStyle: .short, timeStyle: .medium)
        } ?? "unknown date"
        return "Model File: present (\(size), modified \(modified))"
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
