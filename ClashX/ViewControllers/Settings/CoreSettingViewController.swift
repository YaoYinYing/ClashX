//
//  CoreSettingViewController.swift
//  ClashX
//
//  Created by Codex on 2026/4/24.
//

import Cocoa

class CoreSettingViewController: NSViewController {
    private let scrollView = NSScrollView()
    private let contentStack = NSStackView()

    private let modeLabel = NSTextField(labelWithString: "")
    private let controllerLabel = NSTextField(labelWithString: "")
    private let versionLabel = NSTextField(labelWithString: "")
    private let buildLabel = NSTextField(labelWithString: "")

    private let tunStatusLabel = NSTextField(labelWithString: "")
    private let tunDetailLabel = NSTextField(labelWithString: "")
    private let tunEnabledButton = NSButton(checkboxWithTitle: NSLocalizedString("Enable TUN", comment: ""), target: nil, action: nil)

    private let modelStatusLabel = NSTextField(labelWithString: "")
    private let modelPathLabel = NSTextField(labelWithString: "")
    private let modelOverrideButton = NSButton(checkboxWithTitle: NSLocalizedString("Use ClashX LightGBM Settings", comment: ""), target: nil, action: nil)
    private let modelAutoUpdateButton = NSButton(checkboxWithTitle: NSLocalizedString("Auto Update", comment: ""), target: nil, action: nil)
    private let modelUrlField = NSTextField(string: "")
    private let modelIntervalField = NSTextField(string: "")
    private let updateModelButton = NSButton(title: NSLocalizedString("Update LightGBM Model", comment: ""), target: nil, action: nil)
    private let resetModelUrlButton = NSButton(title: NSLocalizedString("Reset URL", comment: ""), target: nil, action: nil)
    private let openConfigFolderButton = NSButton(title: NSLocalizedString("Open Config Folder", comment: ""), target: nil, action: nil)

    private var currentTunEnabled = false
    private var lightGBMEndpointAvailable = true

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 420))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = NSLocalizedString("Core", comment: "")
        setupView()
        refreshAll()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        refreshAll()
    }

    private func setupView() {
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        let contentView = NSView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = contentView

        contentStack.orientation = .vertical
        contentStack.spacing = 14
        contentStack.alignment = .leading
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            contentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            contentStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 18),
            contentStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            contentStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20)
        ])

        [modeLabel, controllerLabel, versionLabel, buildLabel, tunStatusLabel, tunDetailLabel, modelStatusLabel, modelPathLabel].forEach {
            $0.lineBreakMode = .byTruncatingMiddle
            $0.maximumNumberOfLines = 2
            $0.textColor = .secondaryLabelColor
        }

        contentStack.addArrangedSubview(makeSection(title: NSLocalizedString("Core Info", comment: ""), rows: [
            labeledRow(title: NSLocalizedString("Mode", comment: ""), view: modeLabel),
            labeledRow(title: NSLocalizedString("Controller", comment: ""), view: controllerLabel),
            labeledRow(title: NSLocalizedString("Version", comment: ""), view: versionLabel),
            labeledRow(title: NSLocalizedString("Build", comment: ""), view: buildLabel)
        ]))

        tunEnabledButton.target = self
        tunEnabledButton.action = #selector(actionToggleTun)
        contentStack.addArrangedSubview(makeSection(title: NSLocalizedString("TUN", comment: ""), rows: [
            labeledRow(title: NSLocalizedString("State", comment: ""), view: tunStatusLabel),
            labeledRow(title: NSLocalizedString("Details", comment: ""), view: tunDetailLabel),
            tunEnabledButton
        ]))

        modelOverrideButton.target = self
        modelOverrideButton.action = #selector(actionModelSettingsChanged)
        modelAutoUpdateButton.target = self
        modelAutoUpdateButton.action = #selector(actionModelSettingsChanged)
        modelUrlField.target = self
        modelUrlField.action = #selector(actionModelSettingsChanged)
        modelIntervalField.target = self
        modelIntervalField.action = #selector(actionModelSettingsChanged)
        modelIntervalField.alignment = .right
        modelIntervalField.placeholderString = "72"
        modelIntervalField.widthAnchor.constraint(equalToConstant: 70).isActive = true

        updateModelButton.target = self
        updateModelButton.action = #selector(actionUpdateLightGBMModel)
        resetModelUrlButton.target = self
        resetModelUrlButton.action = #selector(actionResetModelURL)
        openConfigFolderButton.target = self
        openConfigFolderButton.action = #selector(actionOpenConfigFolder)

        let modelControls = NSStackView(views: [modelOverrideButton, modelAutoUpdateButton, NSTextField(labelWithString: NSLocalizedString("Interval Hours", comment: "")), modelIntervalField])
        modelControls.orientation = .horizontal
        modelControls.spacing = 8

        let modelURLControls = NSStackView(views: [modelUrlField, resetModelUrlButton])
        modelURLControls.orientation = .horizontal
        modelURLControls.spacing = 8
        modelUrlField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let modelButtons = NSStackView(views: [updateModelButton, openConfigFolderButton])
        modelButtons.orientation = .horizontal
        modelButtons.spacing = 8

        contentStack.addArrangedSubview(makeSection(title: NSLocalizedString("LightGBM", comment: ""), rows: [
            labeledRow(title: NSLocalizedString("Model", comment: ""), view: modelStatusLabel),
            labeledRow(title: NSLocalizedString("Path", comment: ""), view: modelPathLabel),
            modelControls,
            labeledRow(title: NSLocalizedString("Model URL", comment: ""), view: modelURLControls),
            modelButtons
        ]))
    }

    private func makeSection(title: String, rows: [NSView]) -> NSView {
        let box = NSBox()
        box.boxType = .custom
        box.borderType = .lineBorder
        box.cornerRadius = 6
        box.titlePosition = .noTitle
        box.contentViewMargins = NSSize(width: 14, height: 14)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
        stack.addArrangedSubview(titleLabel)
        rows.forEach { stack.addArrangedSubview($0) }

        box.contentView?.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: box.contentView!.topAnchor),
            stack.leadingAnchor.constraint(equalTo: box.contentView!.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: box.contentView!.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: box.contentView!.bottomAnchor)
        ])
        box.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
        return box
    }

    private func labeledRow(title: String, view: NSView) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        titleLabel.textColor = .labelColor
        titleLabel.widthAnchor.constraint(equalToConstant: 78).isActive = true

        let row = NSStackView(views: [titleLabel, view])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.detachesHiddenViews = true
        return row
    }

    private func refreshAll() {
        refreshCoreInfo()
        refreshTunInfo()
        refreshLightGBMInfo()
    }

    private func refreshCoreInfo() {
        modeLabel.stringValue = Settings.isUsingEmbeddedCore ? NSLocalizedString("Embedded Vernesong mihomo", comment: "") : NSLocalizedString("External Controller", comment: "")
        controllerLabel.stringValue = Settings.activeControllerURL

        if Settings.isUsingEmbeddedCore {
            versionLabel.stringValue = Settings.embeddedCoreVersion
            buildLabel.stringValue = "\(Settings.embeddedCoreCommit) @ \(Settings.embeddedCoreBranch) \(Settings.embeddedCoreBuildTime)"
        } else {
            buildLabel.stringValue = NSLocalizedString("Remote core metadata is not trusted from the embedded bundle.", comment: "")
            ApiRequest.requestCoreVersion { [weak self] version in
                guard let self else { return }
                self.versionLabel.stringValue = version ?? NSLocalizedString("unknown", comment: "")
            }
        }
    }

    private func refreshTunInfo() {
        let tun = ConfigManager.shared.currentConfig?.tun
        currentTunEnabled = tun?.enable ?? false
        tunEnabledButton.state = currentTunEnabled ? .on : .off

        if let tun {
            tunStatusLabel.stringValue = tun.enable ? NSLocalizedString("Enabled", comment: "") : NSLocalizedString("Disabled", comment: "")
            let dnsHijack = (tun.dnsHijack ?? []).joined(separator: ", ")
            let detailParts = [
                tun.device.map { "device=\($0)" },
                tun.stack.map { "stack=\($0)" },
                tun.autoRoute.map { "auto-route=\($0 ? "true" : "false")" },
                dnsHijack.isEmpty ? nil : "dns-hijack=\(dnsHijack)"
            ].compactMap { $0 }
            tunDetailLabel.stringValue = detailParts.isEmpty ? NSLocalizedString("No additional TUN details from the current config.", comment: "") : detailParts.joined(separator: "  ")
        } else {
            tunStatusLabel.stringValue = NSLocalizedString("Unavailable", comment: "")
            tunDetailLabel.stringValue = NSLocalizedString("This controller does not expose a tun section in /configs.", comment: "")
        }

        let canEditTun = RemoteControlManager.selectConfig == nil ? tun != nil : tun != nil
        tunEnabledButton.isEnabled = canEditTun
    }

    private func refreshLightGBMInfo() {
        modelOverrideButton.state = Settings.smartLightGBMOverrideConfig ? .on : .off
        modelAutoUpdateButton.state = Settings.smartLightGBMAutoUpdate ? .on : .off
        modelUrlField.stringValue = Settings.effectiveSmartLightGBMModelUrl
        modelIntervalField.stringValue = "\(Settings.smartLightGBMUpdateIntervalHours)"

        let enabled = Settings.smartLightGBMOverrideConfig
        modelAutoUpdateButton.isEnabled = enabled
        modelUrlField.isEnabled = enabled
        modelIntervalField.isEnabled = enabled
        resetModelUrlButton.isEnabled = enabled

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

        let isManualUpdateSupported = Settings.isUsingEmbeddedCore || lightGBMEndpointAvailable
        updateModelButton.isHidden = !isManualUpdateSupported
        updateModelButton.isEnabled = ConfigManager.shared.isRunning && isManualUpdateSupported
    }

    @objc private func actionToggleTun() {
        let targetState = tunEnabledButton.state == .on
        ApiRequest.updateTun(enable: targetState) { [weak self] success, message in
            guard let self else { return }
            if success {
                Logger.log("[TUN] updated enable=\(targetState)")
                AppDelegate.shared.syncConfig {
                    self.refreshTunInfo()
                }
            } else {
                self.tunEnabledButton.state = self.currentTunEnabled ? .on : .off
                let info = message ?? NSLocalizedString("Failed to update TUN settings.", comment: "")
                Logger.log("[TUN] \(info)", level: .error)
                NSUserNotificationCenter.default.post(title: "TUN", info: info)
            }
        }
    }

    @objc private func actionModelSettingsChanged() {
        saveLightGBMSettings()
        refreshLightGBMInfo()
    }

    @objc private func actionUpdateLightGBMModel() {
        saveLightGBMSettings()
        updateModelButton.isEnabled = false
        ApiRequest.updateSmartLightGBMModel { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                Logger.log("[Smart] LightGBM model update requested")
            case .unsupported:
                self.lightGBMEndpointAvailable = false
                Logger.log("[Smart] LightGBM model update is not supported by this core", level: .warning)
            case .failed:
                Logger.log("[Smart] LightGBM model update failed", level: .warning)
            }
            self.refreshLightGBMInfo()
        }
    }

    @objc private func actionResetModelURL() {
        Settings.smartLightGBMModelUrl = Settings.defaultSmartLightGBMModelUrl
        saveLightGBMSettings()
        refreshLightGBMInfo()
    }

    @objc private func actionOpenConfigFolder() {
        NSWorkspace.shared.openFile(kConfigFolderPath)
    }

    private func saveLightGBMSettings() {
        Settings.smartLightGBMOverrideConfig = modelOverrideButton.state == .on
        Settings.smartLightGBMAutoUpdate = modelAutoUpdateButton.state == .on
        Settings.smartLightGBMModelUrl = modelUrlField.stringValue.isEmpty ? Settings.defaultSmartLightGBMModelUrl : modelUrlField.stringValue
        Settings.smartLightGBMUpdateIntervalHours = max(1, modelIntervalField.integerValue)
        Settings.syncSmartLightGBMOptionsToCore()
    }
}
