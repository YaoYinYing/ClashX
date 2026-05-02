//
//  SmartDashboardViewController.swift
//  ClashX
//
//  Created by Codex on 2026/4/24.
//

import AppKit

@available(macOS 10.15, *)
private struct SmartDashboardRow {
    let group: ClashProxy
    let node: String
    let rank: String
    let weight: Double
    let lastUpdated: Int

    var isCurrent: Bool {
        group.now == node
    }
}

@available(macOS 10.15, *)
class SmartDashboardViewController: NSViewController {
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let refreshButton = NSButton(title: NSLocalizedString("Refresh", comment: ""), target: nil, action: nil)
    private let flushAllButton = NSButton(title: NSLocalizedString("Flush Smart Cache", comment: ""), target: nil, action: nil)
    private let flushConfigButton = NSButton(title: NSLocalizedString("Flush Current Config", comment: ""), target: nil, action: nil)
    private let updateModelButton = NSButton(title: NSLocalizedString("Update LightGBM Model", comment: ""), target: nil, action: nil)
    private let resetModelUrlButton = NSButton(title: NSLocalizedString("Reset URL", comment: ""), target: nil, action: nil)
    private let openConfigFolderButton = NSButton(title: NSLocalizedString("Open Config Folder", comment: ""), target: nil, action: nil)
    private let modelOverrideButton = NSButton(checkboxWithTitle: NSLocalizedString("Use ClashX LightGBM Settings", comment: ""), target: nil, action: nil)
    private let modelAutoUpdateButton = NSButton(checkboxWithTitle: NSLocalizedString("Auto Update", comment: ""), target: nil, action: nil)
    private let modelUrlField = NSTextField(string: "")
    private let modelIntervalField = NSTextField(string: "")
    private let modelStatusLabel = NSTextField(labelWithString: "")
    private let modelPathLabel = NSTextField(labelWithString: "")
    private let emptyLabel = NSTextField(labelWithString: "")

    private var rows = [SmartDashboardRow]()
    private var smartGroups = [ClashProxy]()
    private var lastSearch = ""
    private var smartEndpointsAvailable = true
    private var lightGBMEndpointAvailable = true

    override func loadView() {
        view = NSView(frame: NSRect(origin: .zero, size: CGSize(width: 900, height: 600)))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setup()
        reloadData()
    }

    private func setup() {
        let toolbar = NSStackView(views: [refreshButton, flushConfigButton, flushAllButton, updateModelButton, openConfigFolderButton])
        toolbar.orientation = .horizontal
        toolbar.spacing = 8
        toolbar.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 8, right: 12)

        refreshButton.target = self
        refreshButton.action = #selector(actionRefresh)
        flushAllButton.target = self
        flushAllButton.action = #selector(actionFlushAll)
        flushConfigButton.target = self
        flushConfigButton.action = #selector(actionFlushConfig)
        updateModelButton.target = self
        updateModelButton.action = #selector(actionUpdateLightGBMModel)
        openConfigFolderButton.target = self
        openConfigFolderButton.action = #selector(actionOpenConfigFolder)

        view.addSubview(toolbar)
        toolbar.makeConstraints {
            [$0.topAnchor.constraint(equalTo: view.topAnchor),
             $0.leftAnchor.constraint(equalTo: view.leftAnchor),
             $0.rightAnchor.constraint(lessThanOrEqualTo: view.rightAnchor)]
        }

        let modelPanel = NSStackView()
        modelPanel.orientation = .vertical
        modelPanel.spacing = 8
        modelPanel.edgeInsets = NSEdgeInsets(top: 4, left: 12, bottom: 10, right: 12)

        modelOverrideButton.target = self
        modelOverrideButton.action = #selector(actionModelSettingsChanged)
        modelAutoUpdateButton.target = self
        modelAutoUpdateButton.action = #selector(actionModelSettingsChanged)
        resetModelUrlButton.target = self
        resetModelUrlButton.action = #selector(actionResetModelURL)
        modelUrlField.target = self
        modelUrlField.action = #selector(actionModelSettingsChanged)
        modelIntervalField.target = self
        modelIntervalField.action = #selector(actionModelSettingsChanged)
        modelIntervalField.placeholderString = "72"
        modelIntervalField.maximumNumberOfLines = 1
        modelIntervalField.alignment = .right
        modelIntervalField.widthAnchor.constraint(equalToConstant: 58).isActive = true

        let modelStatusRow = NSStackView(views: [modelStatusLabel, modelPathLabel])
        modelStatusRow.orientation = .horizontal
        modelStatusRow.spacing = 12

        let modelOptionsRow = NSStackView(views: [modelOverrideButton, modelAutoUpdateButton, NSTextField(labelWithString: NSLocalizedString("Interval Hours", comment: "")), modelIntervalField])
        modelOptionsRow.orientation = .horizontal
        modelOptionsRow.spacing = 8

        let modelURLRow = NSStackView(views: [NSTextField(labelWithString: NSLocalizedString("Model URL", comment: "")), modelUrlField, resetModelUrlButton])
        modelURLRow.orientation = .horizontal
        modelURLRow.spacing = 8
        modelUrlField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        modelPanel.addArrangedSubview(modelStatusRow)
        modelPanel.addArrangedSubview(modelOptionsRow)
        modelPanel.addArrangedSubview(modelURLRow)
        view.addSubview(modelPanel)
        modelPanel.makeConstraints {
            [$0.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
             $0.leftAnchor.constraint(equalTo: view.leftAnchor),
             $0.rightAnchor.constraint(equalTo: view.rightAnchor)]
        }
        updateModelSettingsUI()

        emptyLabel.alignment = .center
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.stringValue = NSLocalizedString("No Smart groups or weight data available.", comment: "")
        view.addSubview(emptyLabel)
        emptyLabel.makeConstraints {
            [$0.centerXAnchor.constraint(equalTo: view.centerXAnchor),
             $0.centerYAnchor.constraint(equalTo: view.centerYAnchor)]
        }

        scrollView.hasVerticalScroller = true
        scrollView.documentView = tableView
        view.addSubview(scrollView)
        scrollView.makeConstraints {
            [$0.topAnchor.constraint(equalTo: modelPanel.bottomAnchor),
             $0.leftAnchor.constraint(equalTo: view.leftAnchor),
             $0.rightAnchor.constraint(equalTo: view.rightAnchor),
             $0.bottomAnchor.constraint(equalTo: view.bottomAnchor)]
        }

        addColumn("group", title: NSLocalizedString("Group", comment: ""), width: 170)
        addColumn("mode", title: NSLocalizedString("Mode", comment: ""), width: 90)
        addColumn("node", title: NSLocalizedString("Node", comment: ""), width: 260)
        addColumn("rank", title: NSLocalizedString("Rank", comment: ""), width: 120)
        addColumn("weight", title: NSLocalizedString("Weight", comment: ""), width: 90)
        addColumn("current", title: NSLocalizedString("Current", comment: ""), width: 90)
        addColumn("updated", title: NSLocalizedString("Updated", comment: ""), width: 160)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.usesAlternatingRowBackgroundColors = true
    }

    private func addColumn(_ identifier: String, title: String, width: CGFloat) {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
        column.title = title
        column.width = width
        tableView.addTableColumn(column)
    }

    private func reloadData() {
        updateModelStatus()
        let smartWeightAvailability = CapabilityCache.shared.availability(for: .smartWeights)
        if smartWeightAvailability == .unsupported || smartWeightAvailability == .unauthorized {
            smartEndpointsAvailable = false
        }
        guard smartEndpointsAvailable else {
            updateRows(groups: [], weights: [:])
            return
        }

        ApiRequest.getMergedProxyData { [weak self] proxyInfo in
            guard let self else { return }
            let groups = proxyInfo?.proxyGroups.filter { $0.type == .smart } ?? []
            self.smartGroups = groups

            ApiRequest.requestSmartWeights { [weak self] response in
                guard let self else { return }
                if response == nil, !groups.isEmpty {
                    self.smartEndpointsAvailable = false
                    CapabilityCache.shared.set(.smartWeights, availability: .degraded, message: NSLocalizedString("Smart weights could not be loaded from the active controller.", comment: ""))
                } else if response != nil {
                    CapabilityCache.shared.set(.smartWeights, availability: .available)
                }
                self.updateRows(groups: groups, weights: response?.weights ?? [:])
            }
        }
    }

    private func updateRows(groups: [ClashProxy], weights: [String: [SmartNodeWeight]]) {
        var nextRows = [SmartDashboardRow]()
        for group in groups {
            let nodeWeights = (weights[group.name] ?? []).reduce(into: [String: SmartNodeWeight]()) { result, weight in
                result[weight.name] = weight
            }
            for node in group.all ?? [] {
                let weight = nodeWeights[node]
                nextRows.append(SmartDashboardRow(group: group,
                                                  node: node,
                                                  rank: weight?.rank ?? "",
                                                  weight: weight?.weight ?? 0,
                                                  lastUpdated: weight?.lastUpdated ?? 0))
            }
        }
        rows = filter(nextRows)
        tableView.reloadData()
        emptyLabel.isHidden = !rows.isEmpty
        scrollView.isHidden = rows.isEmpty
        let smartCacheBlocked = {
            let availability = CapabilityCache.shared.availability(for: .smartCacheFlush)
            return availability == .unsupported || availability == .unauthorized
        }()
        flushAllButton.isEnabled = smartEndpointsAvailable && !groups.isEmpty && !smartCacheBlocked
        flushConfigButton.isEnabled = smartEndpointsAvailable && !groups.isEmpty && !smartCacheBlocked

        let lightGBMAvailability = CapabilityCache.shared.availability(for: .lightGBMUpgrade)
        if lightGBMAvailability == .unsupported || lightGBMAvailability == .unauthorized {
            lightGBMEndpointAvailable = false
        }
        updateModelButton.isEnabled = lightGBMEndpointAvailable && ConfigManager.shared.isRunning
    }

    private func filter(_ source: [SmartDashboardRow]) -> [SmartDashboardRow] {
        guard !lastSearch.isEmpty else { return source }
        return source.filter {
            $0.group.name.localizedCaseInsensitiveContains(lastSearch) ||
                $0.node.localizedCaseInsensitiveContains(lastSearch) ||
                $0.rank.localizedCaseInsensitiveContains(lastSearch)
        }
    }

    @objc private func actionRefresh() {
        let smartWeightAvailability = CapabilityCache.shared.availability(for: .smartWeights)
        smartEndpointsAvailable = smartWeightAvailability != .unsupported && smartWeightAvailability != .unauthorized
        reloadData()
    }

    @objc private func actionFlushAll() {
        ApiRequest.flushSmartCache { [weak self] success in
            CapabilityCache.shared.set(.smartCacheFlush, availability: success ? .available : .degraded)
            self?.reloadData()
        }
    }

    @objc private func actionFlushConfig() {
        ApiRequest.flushSmartCache(configName: ConfigManager.selectConfigName) { [weak self] success in
            CapabilityCache.shared.set(.smartCacheFlush, availability: success ? .available : .degraded)
            self?.reloadData()
        }
    }

    @objc private func actionUpdateLightGBMModel() {
        saveModelSettings()
        updateModelButton.isEnabled = false
        ApiRequest.updateSmartLightGBMModel { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                CapabilityCache.shared.set(.lightGBMUpgrade, availability: .available)
                Logger.log("[Smart] LightGBM model update requested")
            case .unsupported:
                self.lightGBMEndpointAvailable = false
                CapabilityCache.shared.set(.lightGBMUpgrade, availability: .unsupported)
                Logger.log("[Smart] LightGBM model update is not supported by this core", level: .warning)
            case let .unauthorized(message):
                self.lightGBMEndpointAvailable = false
                CapabilityCache.shared.set(.lightGBMUpgrade, availability: .unauthorized, message: message)
                Logger.log("[Smart] LightGBM model update was rejected by controller authentication", level: .warning)
            case .failed:
                CapabilityCache.shared.set(.lightGBMUpgrade, availability: .degraded, message: NSLocalizedString("LightGBM model update failed.", comment: ""))
                Logger.log("[Smart] LightGBM model update failed", level: .warning)
            }
            self.reloadData()
        }
    }

    @objc private func actionOpenConfigFolder() {
        NSWorkspace.shared.openFile(kConfigFolderPath)
    }

    @objc private func actionResetModelURL() {
        Settings.smartLightGBMModelUrl = Settings.defaultSmartLightGBMModelUrl
        updateModelSettingsUI()
        saveModelSettings()
    }

    @objc private func actionModelSettingsChanged() {
        saveModelSettings()
        updateModelSettingsUI()
    }

    private func updateModelSettingsUI() {
        modelOverrideButton.state = Settings.smartLightGBMOverrideConfig ? .on : .off
        modelAutoUpdateButton.state = Settings.smartLightGBMAutoUpdate ? .on : .off
        modelUrlField.stringValue = Settings.effectiveSmartLightGBMModelUrl
        modelIntervalField.stringValue = "\(Settings.smartLightGBMUpdateIntervalHours)"
        let enabled = Settings.smartLightGBMOverrideConfig
        modelUrlField.isEnabled = enabled
        modelAutoUpdateButton.isEnabled = enabled
        modelIntervalField.isEnabled = enabled
        resetModelUrlButton.isEnabled = enabled
        updateModelStatus()
    }

    private func saveModelSettings() {
        Settings.smartLightGBMOverrideConfig = modelOverrideButton.state == .on
        Settings.smartLightGBMAutoUpdate = modelAutoUpdateButton.state == .on
        Settings.smartLightGBMModelUrl = modelUrlField.stringValue.isEmpty ? Settings.defaultSmartLightGBMModelUrl : modelUrlField.stringValue
        Settings.smartLightGBMUpdateIntervalHours = max(1, modelIntervalField.integerValue)
        Settings.syncSmartLightGBMOptionsToCore()
    }

    private func updateModelStatus() {
        let path = Paths.smartLightGBMModelPath
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        if let size = attributes?[.size] as? NSNumber {
            let modified = attributes?[.modificationDate] as? Date
            let modifiedText = modified.map {
                DateFormatter.localizedString(from: $0, dateStyle: .short, timeStyle: .medium)
            } ?? NSLocalizedString("unknown", comment: "")
            modelStatusLabel.stringValue = String(format: NSLocalizedString("Model.bin: %@, modified %@", comment: ""), ByteCountFormatter.string(fromByteCount: size.int64Value, countStyle: .file), modifiedText)
        } else {
            modelStatusLabel.stringValue = NSLocalizedString("Model.bin: missing", comment: "")
        }
        modelPathLabel.stringValue = path
        updateModelButton.isHidden = !lightGBMEndpointAvailable
    }
}

@available(macOS 10.15, *)
extension SmartDashboardViewController: DashboardSubViewControllerProtocol {
    func actionSearch(string: String) {
        lastSearch = string
        reloadData()
    }
}

@available(macOS 10.15, *)
extension SmartDashboardViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumn else { return nil }
        let identifier = tableColumn.identifier
        let view = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? NSTableCellView()
        view.identifier = identifier
        if view.textField == nil {
            let label = NSTextField(labelWithString: "")
            label.lineBreakMode = .byTruncatingMiddle
            view.addSubview(label)
            label.makeConstraintsToBindToSuperview(.init(top: 0, left: 6, bottom: 0, right: 6))
            view.textField = label
        }

        let item = rows[row]
        switch identifier.rawValue {
        case "group":
            view.textField?.stringValue = item.group.name
        case "mode":
            view.textField?.stringValue = item.group.type.rawValue
        case "node":
            view.textField?.stringValue = item.node
        case "rank":
            view.textField?.stringValue = item.rank
        case "weight":
            view.textField?.stringValue = item.weight > 0 ? String(format: "%.2f", item.weight) : ""
        case "current":
            view.textField?.stringValue = item.isCurrent ? NSLocalizedString("Yes", comment: "") : ""
        case "updated":
            if item.lastUpdated > 0 {
                view.textField?.stringValue = DateFormatter.localizedString(from: Date(timeIntervalSince1970: TimeInterval(item.lastUpdated)), dateStyle: .short, timeStyle: .medium)
            } else {
                view.textField?.stringValue = ""
            }
        default:
            view.textField?.stringValue = ""
        }
        return view
    }
}
