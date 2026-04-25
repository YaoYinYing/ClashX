//
//  CoreSettingViewController.swift
//  ClashX
//
//  Created by Codex on 2026/4/24.
//

import Alamofire
import Cocoa

class CoreSettingViewController: NSViewController {
    private let pageHorizontalPadding: CGFloat = 24
    private let pageVerticalPadding: CGFloat = 16
    private let rowTitleWidth: CGFloat = 120

    private let contentStack = NSStackView()

    private let summaryLabel = CoreSettingViewController.makeWrapLabel()

    private let modeLabel = CoreSettingViewController.makeWrapLabel()
    private let versionLabel = CoreSettingViewController.makeWrapLabel()
    private let buildLabel = CoreSettingViewController.makeWrapLabel()

    private let controllerStateLabel = CoreSettingViewController.makeWrapLabel()
    private let controllerURLLabel = CoreSettingViewController.makeWrapLabel()
    private let controllerDetailLabel = CoreSettingViewController.makeWrapLabel()

    private let configStatusLabel = CoreSettingViewController.makeWrapLabel()
    private let configSourceLabel = CoreSettingViewController.makeWrapLabel()
    private let configDetailLabel = CoreSettingViewController.makeWrapLabel()

    private let tunStatusLabel = CoreSettingViewController.makeWrapLabel()
    private let tunDetailLabel = CoreSettingViewController.makeWrapLabel()
    private let tunNoteLabel = CoreSettingViewController.makeSecondaryWrapLabel()
    private let tunEnabledButton = NSButton(checkboxWithTitle: NSLocalizedString("Enable TUN", comment: ""), target: nil, action: nil)

    private let modelStatusLabel = CoreSettingViewController.makeWrapLabel()
    private let modelModifiedLabel = CoreSettingViewController.makeWrapLabel()
    private let modelPathLabel = CoreSettingViewController.makeWrapLabel()
    private let modelEndpointLabel = CoreSettingViewController.makeWrapLabel()
    private let modelOverrideStatusLabel = CoreSettingViewController.makeWrapLabel()
    private let modelOverrideButton = NSButton(checkboxWithTitle: NSLocalizedString("Use ClashX LightGBM Settings", comment: ""), target: nil, action: nil)
    private let modelAutoUpdateButton = NSButton(checkboxWithTitle: NSLocalizedString("Auto Update", comment: ""), target: nil, action: nil)
    private let modelUrlField = NSTextField(string: "")
    private let modelIntervalField = NSTextField(string: "")
    private let updateModelButton = NSButton(title: NSLocalizedString("Update LightGBM Model", comment: ""), target: nil, action: nil)
    private let resetModelUrlButton = NSButton(title: NSLocalizedString("Reset URL", comment: ""), target: nil, action: nil)
    private let openConfigFolderButton = NSButton(title: NSLocalizedString("Open Config Folder", comment: ""), target: nil, action: nil)

    private var currentTunEnabled = false
    private var lightGBMEndpointSupported: Bool?

    private var tunSupportNote: String {
        NSLocalizedString("TUN is shown from the current mihomo config. Full macOS TUN support may require additional privileges and is not completed in this branch.", comment: "")
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 460))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = NSLocalizedString("Core", comment: "")
        Logger.log("[Core Settings] page loaded", level: .debug)
        setupView()
        applyLoadingState()
        refreshAll()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        refreshAll()
    }

    private static func makeWrapLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 2
        label.textColor = .secondaryLabelColor
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    private static func makeSecondaryWrapLabel() -> NSTextField {
        let label = makeWrapLabel()
        label.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        return label
    }

    private func setupView() {
        view.addSubview(contentStack)
        contentStack.orientation = .vertical
        contentStack.spacing = 14
        contentStack.alignment = .leading
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: view.topAnchor, constant: pageVerticalPadding),
            contentStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: pageHorizontalPadding),
            contentStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -pageHorizontalPadding),
            contentStack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -pageVerticalPadding)
        ])

        summaryLabel.stringValue = NSLocalizedString("Core settings are a status and control surface. Unsupported controller endpoints should degrade gracefully instead of leaving this page blank.", comment: "")
        addFullWidthArrangedSubview(summaryLabel)

        addFullWidthArrangedSubview(makeSection(title: NSLocalizedString("Core Info", comment: ""), rows: [
            labeledRow(title: NSLocalizedString("Mode", comment: ""), view: modeLabel),
            labeledRow(title: NSLocalizedString("Version", comment: ""), view: versionLabel),
            labeledRow(title: NSLocalizedString("Build", comment: ""), view: buildLabel)
        ]))

        addFullWidthArrangedSubview(makeSection(title: NSLocalizedString("Controller", comment: ""), rows: [
            labeledRow(title: NSLocalizedString("State", comment: ""), view: controllerStateLabel),
            labeledRow(title: NSLocalizedString("URL", comment: ""), view: controllerURLLabel),
            labeledRow(title: NSLocalizedString("Details", comment: ""), view: controllerDetailLabel)
        ]))

        addFullWidthArrangedSubview(makeSection(title: NSLocalizedString("Config Status", comment: ""), rows: [
            labeledRow(title: NSLocalizedString("Status", comment: ""), view: configStatusLabel),
            labeledRow(title: NSLocalizedString("Source", comment: ""), view: configSourceLabel),
            labeledRow(title: NSLocalizedString("Details", comment: ""), view: configDetailLabel)
        ]))

        tunEnabledButton.target = self
        tunEnabledButton.action = #selector(actionToggleTun)
        addFullWidthArrangedSubview(makeSection(title: NSLocalizedString("TUN Status", comment: ""), rows: [
            labeledRow(title: NSLocalizedString("State", comment: ""), view: tunStatusLabel),
            labeledRow(title: NSLocalizedString("Details", comment: ""), view: tunDetailLabel),
            tunNoteLabel,
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

        modelUrlField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let modelButtons = NSStackView(views: [updateModelButton, openConfigFolderButton])
        modelButtons.orientation = .horizontal
        modelButtons.spacing = 8

        addFullWidthArrangedSubview(makeSection(title: NSLocalizedString("Smart / LightGBM Status", comment: ""), rows: [
            labeledRow(title: NSLocalizedString("Model.bin", comment: ""), view: modelStatusLabel),
            labeledRow(title: NSLocalizedString("Modified", comment: ""), view: modelModifiedLabel),
            labeledRow(title: NSLocalizedString("Manual Update", comment: ""), view: modelEndpointLabel),
            labeledRow(title: NSLocalizedString("App Override", comment: ""), view: modelOverrideStatusLabel),
            modelControls,
            modelButtons
        ]))

        controllerURLLabel.lineBreakMode = .byTruncatingMiddle
        controllerURLLabel.maximumNumberOfLines = 1
        buildLabel.lineBreakMode = .byTruncatingMiddle
        buildLabel.maximumNumberOfLines = 1
        configDetailLabel.lineBreakMode = .byTruncatingTail
        tunDetailLabel.lineBreakMode = .byTruncatingTail
        modelPathLabel.lineBreakMode = .byTruncatingMiddle
        modelPathLabel.maximumNumberOfLines = 1
        modelUrlField.placeholderString = NSLocalizedString("Custom model URL", comment: "")
    }

    private func addFullWidthArrangedSubview(_ subview: NSView) {
        contentStack.addArrangedSubview(subview)
        subview.translatesAutoresizingMaskIntoConstraints = false
        subview.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
    }

    private func makeSection(title: String, rows: [NSView]) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
        stack.addArrangedSubview(titleLabel)
        rows.forEach { row in
            stack.addArrangedSubview(row)
            row.translatesAutoresizingMaskIntoConstraints = false
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        return stack
    }

    private func labeledRow(title: String, view: NSView) -> NSView {
        let row = NSView()
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        titleLabel.textColor = .labelColor
        titleLabel.alignment = .left

        row.addSubview(titleLabel)
        row.addSubview(view)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.translatesAutoresizingMaskIntoConstraints = false
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            titleLabel.topAnchor.constraint(equalTo: row.topAnchor),
            titleLabel.widthAnchor.constraint(equalToConstant: rowTitleWidth),

            view.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 8),
            view.topAnchor.constraint(equalTo: row.topAnchor),
            view.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor),

            row.bottomAnchor.constraint(greaterThanOrEqualTo: titleLabel.bottomAnchor),
            row.bottomAnchor.constraint(greaterThanOrEqualTo: view.bottomAnchor)
        ])
        return row
    }

    private func applyLoadingState() {
        if Settings.isUsingEmbeddedCore {
            lightGBMEndpointSupported = nil
        }
        modeLabel.stringValue = NSLocalizedString("unknown", comment: "")
        versionLabel.stringValue = NSLocalizedString("unknown", comment: "")
        buildLabel.stringValue = NSLocalizedString("unknown", comment: "")

        controllerStateLabel.stringValue = NSLocalizedString("not connected", comment: "")
        controllerURLLabel.stringValue = Settings.activeControllerURL
        controllerDetailLabel.stringValue = NSLocalizedString("Waiting for controller status.", comment: "")

        configStatusLabel.stringValue = NSLocalizedString("not loaded", comment: "")
        configSourceLabel.stringValue = NSLocalizedString("not checked", comment: "")
        configDetailLabel.stringValue = NSLocalizedString("Config status is not available yet.", comment: "")

        tunStatusLabel.stringValue = NSLocalizedString("unavailable", comment: "")
        tunDetailLabel.stringValue = NSLocalizedString("Current mihomo config has not been loaded yet.", comment: "")
        tunNoteLabel.stringValue = tunSupportNote
        tunEnabledButton.state = .off
        tunEnabledButton.isEnabled = false

        modelStatusLabel.stringValue = NSLocalizedString("missing or not checked", comment: "")
        modelModifiedLabel.stringValue = NSLocalizedString("not checked", comment: "")
        modelPathLabel.stringValue = Paths.smartLightGBMModelPath
        modelEndpointLabel.stringValue = NSLocalizedString("not checked", comment: "")
        modelOverrideStatusLabel.stringValue = NSLocalizedString("disabled", comment: "")
        updateModelSettingsUI()
    }

    private func refreshAll() {
        applyLoadingState()
        refreshCoreInfo()
        refreshConfigStatus()
        refreshLightGBMInfo()
    }

    private func refreshCoreInfo() {
        let isEmbedded = Settings.isUsingEmbeddedCore
        modeLabel.stringValue = isEmbedded ? NSLocalizedString("Embedded mihomo", comment: "") : NSLocalizedString("External controller", comment: "")
        buildLabel.stringValue = isEmbedded
            ? "\(Settings.embeddedCoreCommit) @ \(Settings.embeddedCoreBranch) \(Settings.embeddedCoreBuildTime)"
            : NSLocalizedString("Bundle build metadata is only available for the embedded core.", comment: "")

        controllerURLLabel.stringValue = Settings.activeControllerURL

        if !ConfigManager.shared.isRunning {
            controllerStateLabel.stringValue = NSLocalizedString("not connected", comment: "")
            controllerDetailLabel.stringValue = NSLocalizedString("Core is stopped or the active controller is unavailable.", comment: "")
            if isEmbedded {
                versionLabel.stringValue = Settings.embeddedCoreVersion
            }
            Logger.log("[Core Settings] core info refresh unavailable: controller not running", level: .warning)
            return
        }

        controllerStateLabel.stringValue = NSLocalizedString("checking", comment: "")
        controllerDetailLabel.stringValue = NSLocalizedString("Refreshing /version from the active controller.", comment: "")
        if isEmbedded {
            versionLabel.stringValue = Settings.embeddedCoreVersion
        }

        ApiRequest.requestCoreVersion { [weak self] version in
            guard let self else { return }
            if let version, !version.isEmpty {
                self.versionLabel.stringValue = version
                self.controllerStateLabel.stringValue = NSLocalizedString("connected", comment: "")
                self.controllerDetailLabel.stringValue = NSLocalizedString("/version responded successfully.", comment: "")
                Logger.log("[Core Settings] core info refresh succeeded: version=\(version)", level: .debug)
            } else {
                self.controllerStateLabel.stringValue = NSLocalizedString("not connected", comment: "")
                self.controllerDetailLabel.stringValue = NSLocalizedString("/version is unavailable for the active controller.", comment: "")
                Logger.log("[Core Settings] core info refresh failed: /version unavailable", level: .warning)
            }
        }
    }

    private func refreshConfigStatus() {
        let fallbackConfig = ConfigManager.shared.currentConfig
        if let fallbackConfig {
            applyConfig(fallbackConfig, source: NSLocalizedString("app state", comment: ""), detail: NSLocalizedString("Using the last config known by ClashX.", comment: ""))
        }

        if !ConfigManager.shared.isRunning {
            if fallbackConfig == nil {
                configStatusLabel.stringValue = NSLocalizedString("not loaded", comment: "")
                configSourceLabel.stringValue = NSLocalizedString("controller stopped", comment: "")
                configDetailLabel.stringValue = NSLocalizedString("Core is stopped, so /configs is unavailable.", comment: "")
                refreshTunInfo(using: nil, detail: NSLocalizedString("Core is stopped, so TUN status is unavailable.", comment: ""))
            }
            Logger.log("[Core Settings] config refresh unavailable: core not running", level: .warning)
            return
        }

        guard !ApiRequest.useDirectApi() else {
            if fallbackConfig == nil {
                configStatusLabel.stringValue = NSLocalizedString("not loaded", comment: "")
                configSourceLabel.stringValue = NSLocalizedString("app state", comment: "")
                configDetailLabel.stringValue = NSLocalizedString("No decoded config is cached for the embedded core.", comment: "")
                refreshTunInfo(using: nil, detail: NSLocalizedString("No tun section is available because the current config is missing.", comment: ""))
                Logger.log("[Core Settings] config refresh unavailable: no cached config for embedded mode", level: .warning)
            } else {
                Logger.log("[Core Settings] config refresh succeeded from app state", level: .debug)
            }
            return
        }

        requestRemoteConfig { [weak self] result in
            guard let self else { return }
            switch result {
            case let .success(config):
                self.applyConfig(config, source: "/configs", detail: NSLocalizedString("Loaded from the active controller.", comment: ""))
                Logger.log("[Core Settings] config refresh succeeded from /configs", level: .debug)
            case let .failure(error):
                let message = error.localizedDescription
                Logger.log("[Core Settings] config refresh unavailable: \(message)", level: .warning)
                if let fallbackConfig {
                    self.applyConfig(fallbackConfig,
                                     source: NSLocalizedString("app state fallback", comment: ""),
                                     detail: String(format: NSLocalizedString("/configs unavailable: %@", comment: ""), message))
                } else {
                    self.configStatusLabel.stringValue = NSLocalizedString("unavailable", comment: "")
                    self.configSourceLabel.stringValue = "/configs"
                    self.configDetailLabel.stringValue = message
                    self.refreshTunInfo(using: nil, detail: String(format: NSLocalizedString("TUN status is unavailable because /configs failed: %@", comment: ""), message))
                }
            }
        }
    }

    private func requestRemoteConfig(completeHandler: @escaping (Result<ClashConfig, Error>) -> Void) {
        AF.request(ConfigManager.apiUrl + "/configs", headers: ApiRequest.authHeader())
            .validate(statusCode: 200 ..< 300)
            .responseDecodable(of: ClashConfig.self) { response in
                switch response.result {
                case let .success(config):
                    completeHandler(.success(config))
                case let .failure(error):
                    completeHandler(.failure(error))
                }
            }
    }

    private func applyConfig(_ config: ClashConfig, source: String, detail: String) {
        configStatusLabel.stringValue = NSLocalizedString("loaded", comment: "")
        configSourceLabel.stringValue = source
        configDetailLabel.stringValue = "\(detail)  mode=\(config.mode.name)  http=\(config.usedHttpPort)  socks=\(config.usedSocksPort)"
        refreshTunInfo(using: config, detail: nil)
    }

    private func refreshTunInfo(using config: ClashConfig?, detail: String?) {
        let tun = config?.tun
        currentTunEnabled = tun?.enable ?? false
        tunEnabledButton.state = currentTunEnabled ? .on : .off

        if let tun {
            tunStatusLabel.stringValue = tun.enable ? NSLocalizedString("enabled in config", comment: "") : NSLocalizedString("disabled in config", comment: "")
            let dnsHijack = (tun.dnsHijack ?? []).joined(separator: ", ")
            let detailParts = [
                tun.device.map { "device=\($0)" },
                tun.stack.map { "stack=\($0)" },
                tun.autoRoute.map { "auto-route=\($0 ? "true" : "false")" },
                dnsHijack.isEmpty ? nil : "dns-hijack=\(dnsHijack)"
            ].compactMap { $0 }
            tunDetailLabel.stringValue = detailParts.isEmpty
                ? NSLocalizedString("TUN section is present but no extra fields were reported.", comment: "")
                : detailParts.joined(separator: "  ")
        } else {
            tunStatusLabel.stringValue = NSLocalizedString("unavailable", comment: "")
            tunDetailLabel.stringValue = detail ?? NSLocalizedString("No tun section was found in the current mihomo config.", comment: "")
        }

        tunNoteLabel.stringValue = tunSupportNote
        tunEnabledButton.isEnabled = ConfigManager.shared.isRunning && tun != nil
    }

    private func refreshLightGBMInfo() {
        updateModelSettingsUI()

        let path = Paths.smartLightGBMModelPath
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        if let size = attributes?[.size] as? NSNumber {
            modelStatusLabel.stringValue = String(format: NSLocalizedString("present (%@)", comment: ""), ByteCountFormatter.string(fromByteCount: size.int64Value, countStyle: .file))
            let modified = attributes?[.modificationDate] as? Date
            modelModifiedLabel.stringValue = modified.map {
                DateFormatter.localizedString(from: $0, dateStyle: .short, timeStyle: .medium)
            } ?? NSLocalizedString("unknown", comment: "")
        } else {
            modelStatusLabel.stringValue = NSLocalizedString("missing", comment: "")
            modelModifiedLabel.stringValue = NSLocalizedString("not available", comment: "")
            Logger.log("[Core Settings] model file missing at \(path)", level: .warning)
        }
        modelPathLabel.stringValue = path

        let manualUpdateSupported = Settings.isUsingEmbeddedCore || lightGBMEndpointSupported != false
        if !ConfigManager.shared.isRunning {
            modelEndpointLabel.stringValue = NSLocalizedString("unavailable while the core is stopped", comment: "")
        } else if Settings.isUsingEmbeddedCore {
            modelEndpointLabel.stringValue = NSLocalizedString("appears available for the embedded core", comment: "")
        } else if lightGBMEndpointSupported == false {
            modelEndpointLabel.stringValue = NSLocalizedString("unsupported by the current controller", comment: "")
        } else if lightGBMEndpointSupported == true {
            modelEndpointLabel.stringValue = NSLocalizedString("appears available", comment: "")
        } else {
            modelEndpointLabel.stringValue = NSLocalizedString("not checked yet", comment: "")
        }

        let overrideStatus = Settings.smartLightGBMOverrideConfig ? NSLocalizedString("enabled", comment: "") : NSLocalizedString("disabled", comment: "")
        let autoUpdateStatus = Settings.smartLightGBMAutoUpdate ? NSLocalizedString("auto update on", comment: "") : NSLocalizedString("auto update off", comment: "")
        modelOverrideStatusLabel.stringValue = "\(overrideStatus), \(autoUpdateStatus), \(Settings.smartLightGBMUpdateIntervalHours)h"

        updateModelButton.isEnabled = ConfigManager.shared.isRunning && manualUpdateSupported
    }

    private func updateModelSettingsUI() {
        modelOverrideButton.state = Settings.smartLightGBMOverrideConfig ? .on : .off
        modelAutoUpdateButton.state = Settings.smartLightGBMAutoUpdate ? .on : .off
        modelUrlField.stringValue = Settings.effectiveSmartLightGBMModelUrl
        modelIntervalField.stringValue = "\(Settings.smartLightGBMUpdateIntervalHours)"

        let enabled = Settings.smartLightGBMOverrideConfig
        modelAutoUpdateButton.isEnabled = enabled
        modelUrlField.isEnabled = enabled
        modelIntervalField.isEnabled = enabled
        resetModelUrlButton.isEnabled = enabled
    }

    @objc private func actionToggleTun() {
        let targetState = tunEnabledButton.state == .on
        ApiRequest.updateTun(enable: targetState) { [weak self] success, message in
            guard let self else { return }
            if success {
                Logger.log("[Core Settings] TUN updated enable=\(targetState)", level: .debug)
                AppDelegate.shared.syncConfig {
                    self.refreshConfigStatus()
                }
            } else {
                self.tunEnabledButton.state = self.currentTunEnabled ? .on : .off
                let info = message ?? NSLocalizedString("Failed to update TUN settings.", comment: "")
                Logger.log("[Core Settings] TUN update failure: \(info)", level: .error)
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
                self.lightGBMEndpointSupported = true
                Logger.log("[Core Settings] LightGBM model update requested", level: .debug)
            case .unsupported:
                self.lightGBMEndpointSupported = false
                Logger.log("[Core Settings] LightGBM endpoint unsupported", level: .warning)
            case .failed:
                if self.lightGBMEndpointSupported == nil {
                    self.lightGBMEndpointSupported = true
                }
                Logger.log("[Core Settings] LightGBM model update failed", level: .warning)
            }
            self.refreshLightGBMInfo()
        }
    }

    @objc private func actionResetModelURL() {
        Settings.smartLightGBMModelUrl = Settings.defaultSmartLightGBMModelUrl
        modelUrlField.stringValue = Settings.defaultSmartLightGBMModelUrl
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
