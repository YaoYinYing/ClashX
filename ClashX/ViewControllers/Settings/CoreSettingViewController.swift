//
//  CoreSettingViewController.swift
//  ClashX
//
//  Created by Codex on 2026/4/24.
//

import Alamofire
import Cocoa

class CoreSettingViewController: NSViewController {
    private final class FlippedView: NSView {
        override var isFlipped: Bool { true }
    }

    private enum TunCapability {
        case unsupported(String)
        case guardedUpdateAvailable(String)
    }

    private let pageHorizontalPadding: CGFloat = 24
    private let pageVerticalPadding: CGFloat = 16
    private let rowTitleWidth: CGFloat = 120

    private let scrollView = NSScrollView()
    private let documentView = FlippedView()
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
    private let dnsStatusLabel = CoreSettingViewController.makeWrapLabel()
    private let dnsDetailLabel = CoreSettingViewController.makeWrapLabel()
    private let dnsNoteLabel = CoreSettingViewController.makeSecondaryWrapLabel()

    private let modelStatusLabel = CoreSettingViewController.makeWrapLabel()
    private let modelModifiedLabel = CoreSettingViewController.makeWrapLabel()
    private let modelPathLabel = CoreSettingViewController.makeWrapLabel()
    private let modelEndpointLabel = CoreSettingViewController.makeWrapLabel()
    private let modelOverrideStatusLabel = CoreSettingViewController.makeWrapLabel()
    private let modelOverrideButton = NSButton(checkboxWithTitle: NSLocalizedString("Use SmartX LightGBM Override", comment: ""), target: nil, action: nil)
    private let modelAutoUpdateButton = NSButton(checkboxWithTitle: NSLocalizedString("Auto Update", comment: ""), target: nil, action: nil)
    private let modelUrlField = NSTextField(string: "")
    private let modelIntervalField = NSTextField(string: "")
    private let updateModelButton = NSButton(title: NSLocalizedString("Update LightGBM Model", comment: ""), target: nil, action: nil)
    private let resetModelUrlButton = NSButton(title: NSLocalizedString("Reset URL", comment: ""), target: nil, action: nil)
    private let openConfigFolderButton = NSButton(title: NSLocalizedString("Open Config Folder", comment: ""), target: nil, action: nil)
    private let modelNoteLabel = CoreSettingViewController.makeSecondaryWrapLabel()

    private var currentTunEnabled = false
    private var tunCapability: TunCapability = .unsupported("")
    private var currentConfigSource: String?
    private var currentDisplayedConfig: ClashConfig?
    private let tunLifecycleCoordinator = TunLifecycleCoordinator()

    private var helperCapabilityNote: String {
        NSLocalizedString("ProxyConfigHelper manages macOS system proxy settings only. Installing the helper does not enable TUN support. TUN requires additional privileges beyond system proxy modification.", comment: "")
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
        label.maximumNumberOfLines = 0
        return label
    }

    private func setupView() {
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        scrollView.documentView = documentView

        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(contentStack)

        contentStack.orientation = .vertical
        contentStack.spacing = 14
        contentStack.alignment = .leading
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            documentView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            documentView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            documentView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            documentView.bottomAnchor.constraint(greaterThanOrEqualTo: scrollView.contentView.bottomAnchor),
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            documentView.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.contentView.heightAnchor),

            contentStack.topAnchor.constraint(equalTo: documentView.topAnchor, constant: pageVerticalPadding),
            contentStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: pageHorizontalPadding),
            contentStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -pageHorizontalPadding),
            contentStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -pageVerticalPadding)
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

        addFullWidthArrangedSubview(makeSection(title: NSLocalizedString("DNS Status", comment: ""), rows: [
            labeledRow(title: NSLocalizedString("State", comment: ""), view: dnsStatusLabel),
            labeledRow(title: NSLocalizedString("Details", comment: ""), view: dnsDetailLabel),
            dnsNoteLabel
        ]))

        modelOverrideButton.target = self
        modelOverrideButton.action = #selector(actionModelSettingsChanged)
        modelOverrideButton.toolTip = LightGBMSettingsViewModel.overrideExplanation
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

        modelNoteLabel.stringValue = LightGBMSettingsViewModel.overrideExplanation

        let modelControls = NSStackView(views: [modelOverrideButton, modelAutoUpdateButton, NSTextField(labelWithString: NSLocalizedString("Interval Hours", comment: "")), modelIntervalField])
        modelControls.orientation = .horizontal
        modelControls.spacing = 8

        modelUrlField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let modelButtons = NSStackView(views: [updateModelButton, openConfigFolderButton])
        modelButtons.orientation = .horizontal
        modelButtons.spacing = 8

        let modelURLControls = NSStackView(views: [modelUrlField, resetModelUrlButton])
        modelURLControls.orientation = .horizontal
        modelURLControls.alignment = .centerY
        modelURLControls.spacing = 8
        modelURLControls.setHuggingPriority(.defaultLow, for: .horizontal)

        addFullWidthArrangedSubview(makeSection(title: NSLocalizedString("Smart / LightGBM Status", comment: ""), rows: [
            labeledRow(title: NSLocalizedString("Model.bin", comment: ""), view: modelStatusLabel),
            labeledRow(title: NSLocalizedString("Modified", comment: ""), view: modelModifiedLabel),
            labeledRow(title: NSLocalizedString("Path", comment: ""), view: modelPathLabel),
            labeledRow(title: NSLocalizedString("Manual Update", comment: ""), view: modelEndpointLabel),
            labeledRow(title: NSLocalizedString("App Override", comment: ""), view: modelOverrideStatusLabel),
            labeledRow(title: NSLocalizedString("Model URL", comment: ""), view: modelURLControls),
            modelNoteLabel,
            modelControls,
            modelButtons
        ]))

        controllerURLLabel.lineBreakMode = .byTruncatingMiddle
        controllerURLLabel.maximumNumberOfLines = 1
        buildLabel.lineBreakMode = .byTruncatingMiddle
        buildLabel.maximumNumberOfLines = 1
        configDetailLabel.lineBreakMode = .byTruncatingTail
        tunDetailLabel.lineBreakMode = .byTruncatingTail
        dnsDetailLabel.lineBreakMode = .byTruncatingTail
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
            view.trailingAnchor.constraint(equalTo: row.trailingAnchor),

            row.bottomAnchor.constraint(greaterThanOrEqualTo: titleLabel.bottomAnchor),
            row.bottomAnchor.constraint(greaterThanOrEqualTo: view.bottomAnchor)
        ])
        return row
    }

    private func applyLoadingState() {
        currentConfigSource = nil
        currentDisplayedConfig = nil
        tunCapability = makeTunCapability(config: nil, source: nil)
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
        tunNoteLabel.stringValue = tunCapabilityNoteText(config: nil)
        tunEnabledButton.state = .off
        tunEnabledButton.isEnabled = false
        dnsStatusLabel.stringValue = NSLocalizedString("unavailable", comment: "")
        dnsDetailLabel.stringValue = NSLocalizedString("Current mihomo DNS config has not been loaded yet.", comment: "")
        dnsNoteLabel.stringValue = dnsCapabilityNoteText(config: nil)

        modelStatusLabel.stringValue = NSLocalizedString("missing or not checked", comment: "")
        modelModifiedLabel.stringValue = NSLocalizedString("not checked", comment: "")
        modelPathLabel.stringValue = Paths.smartLightGBMModelPath
        modelEndpointLabel.stringValue = NSLocalizedString("not checked", comment: "")
        modelOverrideStatusLabel.stringValue = NSLocalizedString("disabled", comment: "")
        updateModelSettingsUI()
    }

    private func refreshAll() {
        applyLoadingState()
        CoreCapabilityProbe.shared.probeCurrentController { [weak self] _ in
            self?.refreshLightGBMInfo()
        }
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
            applyConfig(fallbackConfig, source: NSLocalizedString("app state", comment: ""), detail: NSLocalizedString("Using the last config known by SmartX.", comment: ""))
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
                CapabilityCache.shared.set(.configRead, availability: .available, message: NSLocalizedString("Loaded config state from /configs.", comment: ""))
                CapabilityCache.shared.set(.tunConfigRead, availability: config.tun == nil ? .unsupported : .available)
                self.applyConfig(config, source: "/configs", detail: NSLocalizedString("Loaded from the active controller.", comment: ""))
                Logger.log("[Core Settings] config refresh succeeded from /configs", level: .debug)
            case let .failure(error):
                let message = error.localizedDescription
                CapabilityCache.shared.markUnavailable(.configRead, message: message)
                CapabilityCache.shared.markUnavailable(.tunConfigRead, message: message)
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
        ApiRequest.requestControllerConfig { result in
            switch result {
            case let .success(config):
                completeHandler(.success(config))
            case let .unauthorized(message), let .failed(message):
                completeHandler(.failure(NSError(domain: "ControllerEndpoint", code: -1, userInfo: [NSLocalizedDescriptionKey: message])))
            case .unsupported:
                completeHandler(.failure(NSError(domain: "ControllerEndpoint", code: 404, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("/configs is unsupported by the active controller.", comment: "")])))
            }
        }
    }

    private func applyConfig(_ config: ClashConfig, source: String, detail: String) {
        currentConfigSource = source
        currentDisplayedConfig = config
        configStatusLabel.stringValue = NSLocalizedString("loaded", comment: "")
        configSourceLabel.stringValue = source
        configDetailLabel.stringValue = "\(detail)  mode=\(config.mode.name)  http=\(config.usedHttpPort)  socks=\(config.usedSocksPort)"
        refreshTunInfo(using: config, detail: nil)
        refreshDNSInfo(using: config)
    }

    private func refreshTunInfo(using config: ClashConfig?, detail: String?) {
        let tun = config?.tun
        currentDisplayedConfig = config
        tunCapability = makeTunCapability(config: config, source: currentConfigSource)
        currentTunEnabled = tun?.enable ?? false
        tunEnabledButton.state = currentTunEnabled ? .on : .off

        if let tun {
            tunStatusLabel.stringValue = tun.enable ? NSLocalizedString("enabled in config", comment: "") : NSLocalizedString("disabled in config", comment: "")
            let dnsHijack = (tun.dnsHijack ?? []).joined(separator: ", ")
            let detailParts = [
                tun.device.map { "device=\($0)" },
                tun.stack.map { "stack=\($0)" },
                tun.autoRoute.map { "auto-route=\($0 ? "true" : "false")" },
                tun.autoDetectInterface.map { "auto-detect-interface=\($0 ? "true" : "false")" },
                tun.strictRoute.map { "strict-route=\($0 ? "true" : "false")" },
                tun.mtu.map { "mtu=\($0)" },
                tun.udpTimeout.map { "udp-timeout=\($0)" },
                joinedListLabel(title: "include-interface", values: tun.includeInterface),
                joinedListLabel(title: "exclude-interface", values: tun.excludeInterface),
                joinedListLabel(title: "route-address", values: tun.routeAddress),
                joinedListLabel(title: "route-exclude-address", values: tun.routeExcludeAddress),
                dnsHijack.isEmpty ? nil : "dns-hijack=\(dnsHijack)"
            ].compactMap { $0 }
            tunDetailLabel.stringValue = detailParts.isEmpty
                ? NSLocalizedString("TUN section is present but no extra fields were reported.", comment: "")
                : detailParts.joined(separator: "  ")
        } else {
            tunStatusLabel.stringValue = NSLocalizedString("unavailable", comment: "")
            tunDetailLabel.stringValue = detail ?? NSLocalizedString("No tun section was found in the current mihomo config.", comment: "")
        }

        tunNoteLabel.stringValue = tunCapabilityNoteText(config: config)
        if case .guardedUpdateAvailable = tunCapability, ConfigManager.shared.isRunning, tun != nil {
            tunEnabledButton.isEnabled = true
        } else {
            tunEnabledButton.isEnabled = false
        }
    }

    private func refreshDNSInfo(using config: ClashConfig?) {
        guard let dns = config?.dns else {
            dnsStatusLabel.stringValue = NSLocalizedString("unavailable", comment: "")
            dnsDetailLabel.stringValue = NSLocalizedString("No DNS section was found in the current mihomo config.", comment: "")
            dnsNoteLabel.stringValue = dnsCapabilityNoteText(config: config)
            return
        }

        let enabledState = dns.enable ?? true
        let stateParts = [
            enabledState ? NSLocalizedString("enabled in config", comment: "") : NSLocalizedString("disabled in config", comment: ""),
            dns.enhancedMode.map { "mode=\($0)" }
        ].compactMap { $0 }
        dnsStatusLabel.stringValue = stateParts.joined(separator: ", ")

        let detailParts = [
            dns.listen.map { "listen=\($0)" },
            dns.fakeIPRange.map { "fake-ip-range=\($0)" },
            dns.fakeIPFilterMode.map { "fake-ip-filter-mode=\($0)" },
            joinedListLabel(title: "nameserver", values: dns.nameserver),
            joinedListLabel(title: "fallback", values: dns.fallback),
            joinedListLabel(title: "direct-nameserver", values: dns.directNameserver),
            dns.respectRules.map { "respect-rules=\($0 ? "true" : "false")" },
            dns.useHosts.map { "use-hosts=\($0 ? "true" : "false")" },
            dns.useSystemHosts.map { "use-system-hosts=\($0 ? "true" : "false")" },
            dns.preferH3.map { "prefer-h3=\($0 ? "true" : "false")" },
            joinedListLabel(title: "fake-ip-filter", values: dns.fakeIPFilter)
        ].compactMap { $0 }
        dnsDetailLabel.stringValue = detailParts.isEmpty
            ? NSLocalizedString("DNS section is present but no extra fields were reported.", comment: "")
            : detailParts.joined(separator: "  ")
        dnsNoteLabel.stringValue = dnsCapabilityNoteText(config: config)
    }

    private func makeTunCapability(config: ClashConfig?, source: String?) -> TunCapability {
        if Settings.isUsingEmbeddedCore {
            return .unsupported(NSLocalizedString("Embedded core TUN cannot be enabled from SmartX yet. It requires a privileged core startup path or another TUN-capable architecture.", comment: ""))
        }

        guard ConfigManager.shared.isRunning else {
            return .unsupported(NSLocalizedString("The external controller is not connected, so SmartX cannot verify whether TUN updates are supported yet.", comment: ""))
        }

        guard config?.tun != nil else {
            return .unsupported(NSLocalizedString("The current controller config does not expose a tun section, so SmartX keeps TUN disabled.", comment: ""))
        }

        if source == "/configs" {
            return .guardedUpdateAvailable(NSLocalizedString("External controller exposes a tun section through /configs. SmartX can attempt a guarded TUN update, and will restore the previous UI state if the controller rejects it.", comment: ""))
        }

        return .unsupported(NSLocalizedString("External controller TUN support is not verified yet. SmartX keeps it disabled until the controller reports config state reliably.", comment: ""))
    }

    private func tunCapabilityNoteText(config: ClashConfig?) -> String {
        let capabilityReason: String
        switch tunCapability {
        case let .unsupported(reason), let .guardedUpdateAvailable(reason):
            capabilityReason = reason
        }
        let warnings = TunConfigValidator.validate(config?.tun).issues.map(\.message)
        let warningText = warnings.isEmpty ? NSLocalizedString("No additional TUN validation warnings were detected.", comment: "") : warnings.joined(separator: "\n")
        return "\(capabilityReason)\n\(helperCapabilityNote)\n\(warningText)"
    }

    private func dnsCapabilityNoteText(config: ClashConfig?) -> String {
        let base = NSLocalizedString("SmartX currently exposes DNS as structured read-only status plus diagnostics helpers. This page does not yet provide a full DNS editor or embedded-core DNS override path.", comment: "")
        let warnings = DNSConfigValidator.validate(config?.dns).issues.map(\.message)
        let warningText = warnings.isEmpty ? NSLocalizedString("No additional DNS validation warnings were detected.", comment: "") : warnings.joined(separator: "\n")
        return "\(base)\n\(warningText)"
    }

    private func joinedListLabel(title: String, values: [String]?) -> String? {
        guard let values, !values.isEmpty else { return nil }
        return "\(title)=\(values.joined(separator: ", "))"
    }

    private func refreshLightGBMInfo() {
        let state = LightGBMSettingsViewModel.currentState(isCoreRunning: ConfigManager.shared.isRunning,
                                                           capabilityAvailability: CapabilityCache.shared.availability(for: .lightGBMUpgrade))
        applyModelState(state)
        let availability = CapabilityCache.shared.availability(for: .lightGBMUpgrade)
        let manualUpdateSupported = Settings.isUsingEmbeddedCore || (availability != .unsupported && availability != .unauthorized)
        updateModelButton.isEnabled = ConfigManager.shared.isRunning && manualUpdateSupported
    }

    private func updateModelSettingsUI() {
        let state = LightGBMSettingsViewModel.currentState(isCoreRunning: ConfigManager.shared.isRunning,
                                                           capabilityAvailability: CapabilityCache.shared.availability(for: .lightGBMUpgrade))
        applyModelState(state)
    }

    @objc private func actionToggleTun() {
        guard case .guardedUpdateAvailable = tunCapability, tunEnabledButton.isEnabled else {
            tunEnabledButton.state = currentTunEnabled ? .on : .off
            let info = tunCapabilityNoteText(config: currentDisplayedConfig)
            Logger.log("[Core Settings] TUN toggle blocked: \(info)", level: .warning)
            NSUserNotificationCenter.default.post(title: "TUN", info: info)
            return
        }

        let targetState = tunEnabledButton.state == .on
        tunLifecycleCoordinator.setTunEnabled(targetState) { [weak self] result in
            guard let self else { return }
            switch result {
            case let .success(message, _):
                self.currentTunEnabled = targetState
                self.tunEnabledButton.state = targetState ? .on : .off
                Logger.log("[Core Settings] TUN update verified enable=\(targetState)", level: .debug)
                NSUserNotificationCenter.default.post(title: "TUN", info: message)
                AppDelegate.shared.syncConfig {
                    self.refreshConfigStatus()
                }
            case let .unsupported(message, previousState),
                 let .unauthorized(message, previousState),
                 let .failed(message, previousState):
                self.currentTunEnabled = previousState.enabled
                self.tunEnabledButton.state = previousState.enabled ? .on : .off
                let prefix: String
                switch result {
                case .unsupported:
                    prefix = "[Core Settings] TUN update unsupported"
                case .unauthorized:
                    prefix = "[Core Settings] TUN update unauthorized"
                case .failed:
                    prefix = "[Core Settings] TUN update failed after request or verify mismatch"
                default:
                    prefix = "[Core Settings] TUN update failed"
                }
                Logger.log("\(prefix): \(message)", level: .error)
                NSUserNotificationCenter.default.post(title: "TUN", info: message)
                self.refreshConfigStatus()
            case let .blockedByValidation(issues, recoveryText, previousState):
                self.currentTunEnabled = previousState.enabled
                self.tunEnabledButton.state = previousState.enabled ? .on : .off
                let issueLines = issues.map { "\($0.severity.rawValue.capitalized): \($0.message)" }
                let info = ([recoveryText] + issueLines).joined(separator: "\n")
                Logger.log("[Core Settings] TUN update blocked by validation: \(info)", level: .warning)
                NSUserNotificationCenter.default.post(title: "TUN", info: info)
                self.refreshConfigStatus()
            }
        }
    }

    @objc private func actionModelSettingsChanged() {
        let state = LightGBMSettingsViewModel.save(input: LightGBMSettingsViewModel.collectInput(overrideButton: modelOverrideButton,
                                                                                                 modelURLField: modelUrlField,
                                                                                                 autoUpdateButton: modelAutoUpdateButton,
                                                                                                 updateIntervalField: modelIntervalField),
                                                   isCoreRunning: ConfigManager.shared.isRunning,
                                                   capabilityAvailability: CapabilityCache.shared.availability(for: .lightGBMUpgrade))
        applyModelState(state)
    }

    @objc private func actionUpdateLightGBMModel() {
        updateModelButton.isEnabled = false
        LightGBMSettingsViewModel.requestModelUpdate(input: LightGBMSettingsViewModel.collectInput(overrideButton: modelOverrideButton,
                                                                                                    modelURLField: modelUrlField,
                                                                                                    autoUpdateButton: modelAutoUpdateButton,
                                                                                                    updateIntervalField: modelIntervalField),
                                                     isCoreRunning: ConfigManager.shared.isRunning) { [weak self] result, state in
            guard let self else { return }
            switch result {
            case .success:
                Logger.log("[Core Settings] LightGBM model update requested", level: .debug)
            case .unsupported:
                Logger.log("[Core Settings] LightGBM endpoint unsupported", level: .warning)
            case .unauthorized:
                Logger.log("[Core Settings] LightGBM endpoint unauthorized", level: .warning)
            case let .failed(message):
                Logger.log("[Core Settings] LightGBM model update failed: \(message)", level: .warning)
            }
            self.applyModelState(state)
            self.refreshLightGBMInfo()
        }
    }

    @objc private func actionResetModelURL() {
        let state = LightGBMSettingsViewModel.resetModelURL(isCoreRunning: ConfigManager.shared.isRunning,
                                                            capabilityAvailability: CapabilityCache.shared.availability(for: .lightGBMUpgrade))
        applyModelState(state)
    }

    @objc private func actionOpenConfigFolder() {
        NSWorkspace.shared.openFile(kConfigFolderPath)
    }

    private func applyModelState(_ state: LightGBMSettingsState) {
        LightGBMSettingsViewModel.apply(state,
                                        to: LightGBMSettingsControlBindings(overrideButton: modelOverrideButton,
                                                                            autoUpdateButton: modelAutoUpdateButton,
                                                                            modelURLField: modelUrlField,
                                                                            updateIntervalField: modelIntervalField,
                                                                            resetModelURLButton: resetModelUrlButton,
                                                                            modelStatusLabel: modelStatusLabel,
                                                                            modelPathLabel: modelPathLabel,
                                                                            modelModifiedLabel: modelModifiedLabel,
                                                                            manualUpdateLabel: modelEndpointLabel,
                                                                            overrideSummaryLabel: modelOverrideStatusLabel))
    }
}
