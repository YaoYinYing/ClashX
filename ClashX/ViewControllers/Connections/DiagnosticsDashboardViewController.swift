//
//  DiagnosticsDashboardViewController.swift
//  ClashX
//
//  Created by Codex on 2026/5/2.
//

import AppKit
import SwiftyJSON

@available(macOS 10.15, *)
class DiagnosticsDashboardViewController: NSViewController {
    // ponytail: LogLevelFilter extracted to LogViewerViewModel.swift (Phase 4)

    private let refreshMemoryButton = NSButton(title: NSLocalizedString("Refresh Memory", comment: ""), target: nil, action: nil)
    private let refreshProvidersButton = NSButton(title: NSLocalizedString("Refresh Providers", comment: ""), target: nil, action: nil)
    private let healthCheckProvidersButton = NSButton(title: NSLocalizedString("Health Check Providers", comment: ""), target: nil, action: nil)
    private let flushDNSButton = NSButton(title: NSLocalizedString("Flush DNS Cache", comment: ""), target: nil, action: nil)
    private let flushFakeIPButton = NSButton(title: NSLocalizedString("Flush Fake-IP Cache", comment: ""), target: nil, action: nil)
    private let restartCoreButton = NSButton(title: NSLocalizedString("Restart Core", comment: ""), target: nil, action: nil)
    private let runGCButton = NSButton(title: NSLocalizedString("Run Debug GC", comment: ""), target: nil, action: nil)
    private let copyPprofButton = NSButton(title: NSLocalizedString("Copy pprof URLs", comment: ""), target: nil, action: nil)
    private let reloadGeoButton = NSButton(title: NSLocalizedString("Reload GEO Config", comment: ""), target: nil, action: nil)
    private let updateGeoButton = NSButton(title: NSLocalizedString("Update GEO Assets", comment: ""), target: nil, action: nil)
    private let updateDashboardButton = NSButton(title: NSLocalizedString("Update Dashboard", comment: ""), target: nil, action: nil)
    private let copyReportButton = NSButton(title: NSLocalizedString("Copy Report", comment: ""), target: nil, action: nil)
    private let exportBundleButton = NSButton(title: NSLocalizedString("Export Bundle", comment: ""), target: nil, action: nil)
    private let refreshArtifactsButton = NSButton(title: NSLocalizedString("Refresh Artifacts", comment: ""), target: nil, action: nil)
    private let openArtifactsButton = NSButton(title: NSLocalizedString("Open Artifacts", comment: ""), target: nil, action: nil)
    private let restoreLastKnownGoodButton = NSButton(title: NSLocalizedString("Restore Last Good", comment: ""), target: nil, action: nil)
    private let refreshLogsButton = NSButton(title: NSLocalizedString("Refresh Logs", comment: ""), target: nil, action: nil)
    private let exportLogsButton = NSButton(title: NSLocalizedString("Export Logs", comment: ""), target: nil, action: nil)
    private let dnsNameField = NSTextField(string: "")
    private let dnsTypeField = NSTextField(string: "A")
    private let dnsQueryButton = NSButton(title: NSLocalizedString("Query DNS", comment: ""), target: nil, action: nil)
    private let logSearchField = NSSearchField(string: "")
    private let logLevelPopup = NSPopUpButton()
    private let pauseLogsButton = NSButton(checkboxWithTitle: NSLocalizedString("Pause Logs", comment: ""), target: nil, action: nil)
    private let statusLabel = DiagnosticsDashboardViewController.makeWrapLabel()
    private let outputTextView = NSTextView()
    private let outputScrollView = NSScrollView()
    private let maintenanceCoordinator = DiagnosticsMaintenanceCoordinator()

    private var memoryOutput = NSLocalizedString("Memory diagnostics have not been loaded yet.", comment: "")
    private var dnsOutput = NSLocalizedString("DNS diagnostics have not been queried yet.", comment: "")
    private var providerOutput = NSLocalizedString("Provider diagnostics have not been loaded yet.", comment: "")
    private var artifactOutput = NSLocalizedString("Profile artifacts have not been inspected yet.", comment: "")
    private var helperOutput = NSLocalizedString("Helper diagnostics have not been loaded yet.", comment: "")
    private var httpProxyProviderNames = [String]()
    private var latestProxyProviderResult: ControllerJSONResult?
    private var latestRuleProviderResult: ControllerJSONResult?
    private let logViewModel = LogViewerViewModel()

    override func loadView() {
        view = NSView(frame: NSRect(origin: .zero, size: CGSize(width: 900, height: 600)))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setup()
        renderOutput()
        updateCapabilityDrivenState()
        CoreCapabilityProbe.shared.probeCurrentController { _ in }
        refreshMemory()
        refreshProviders()
        refreshArtifacts(announce: false)
        refreshHelperStatus(announce: false)
        logViewModel.onOutputChanged = { [weak self] in
            self?.renderOutput()
            self?.updateCapabilityDrivenState()
        }
        logViewModel.refresh(announce: true)
        logViewModel.startAutoRefresh()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        logViewModel.stopAutoRefresh()
    }

    private static func makeWrapLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        label.textColor = .secondaryLabelColor
        return label
    }

    private func setup() {
        let toolbar = NSStackView(views: [
            refreshMemoryButton,
            refreshProvidersButton,
            healthCheckProvidersButton,
            flushDNSButton,
            flushFakeIPButton,
            restartCoreButton,
            runGCButton,
            copyPprofButton,
            reloadGeoButton,
            updateGeoButton,
            updateDashboardButton,
            copyReportButton,
            exportBundleButton,
            refreshArtifactsButton,
            openArtifactsButton,
            restoreLastKnownGoodButton,
            refreshLogsButton,
            exportLogsButton
        ])
        toolbar.orientation = .horizontal
        toolbar.spacing = 8
        toolbar.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 8, right: 12)
        toolbar.detachesHiddenViews = true
        view.addSubview(toolbar)
        toolbar.makeConstraints {
            [
                $0.topAnchor.constraint(equalTo: view.topAnchor),
                $0.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                $0.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor)
            ]
        }

        refreshMemoryButton.target = self
        refreshMemoryButton.action = #selector(actionRefreshMemory)
        refreshProvidersButton.target = self
        refreshProvidersButton.action = #selector(actionRefreshProviders)
        healthCheckProvidersButton.target = self
        healthCheckProvidersButton.action = #selector(actionHealthCheckProviders)
        flushDNSButton.target = self
        flushDNSButton.action = #selector(actionFlushDNSCache)
        flushFakeIPButton.target = self
        flushFakeIPButton.action = #selector(actionFlushFakeIPCache)
        restartCoreButton.target = self
        restartCoreButton.action = #selector(actionRestartCore)
        runGCButton.target = self
        runGCButton.action = #selector(actionRunGC)
        copyPprofButton.target = self
        copyPprofButton.action = #selector(actionCopyPprofURLs)
        reloadGeoButton.target = self
        reloadGeoButton.action = #selector(actionReloadGeoConfig)
        updateGeoButton.target = self
        updateGeoButton.action = #selector(actionUpdateGeoAssets)
        updateDashboardButton.target = self
        updateDashboardButton.action = #selector(actionUpdateDashboardAssets)
        copyReportButton.target = self
        copyReportButton.action = #selector(actionCopyDiagnosticsReport)
        exportBundleButton.target = self
        exportBundleButton.action = #selector(actionExportDiagnosticsBundle)
        refreshArtifactsButton.target = self
        refreshArtifactsButton.action = #selector(actionRefreshArtifacts)
        openArtifactsButton.target = self
        openArtifactsButton.action = #selector(actionOpenArtifactsFolder)
        restoreLastKnownGoodButton.target = self
        restoreLastKnownGoodButton.action = #selector(actionRestoreLastKnownGood)
        refreshLogsButton.target = self
        refreshLogsButton.action = #selector(actionRefreshLogs)
        exportLogsButton.target = self
        exportLogsButton.action = #selector(actionExportLogs)

        let dnsTypeLabel = NSTextField(labelWithString: NSLocalizedString("Type", comment: ""))
        let dnsNameLabel = NSTextField(labelWithString: NSLocalizedString("Name", comment: ""))
        dnsNameField.placeholderString = NSLocalizedString("example.com", comment: "")
        dnsTypeField.placeholderString = "A"
        dnsTypeField.alignment = .center
        dnsTypeField.widthAnchor.constraint(equalToConstant: 60).isActive = true
        dnsQueryButton.target = self
        dnsQueryButton.action = #selector(actionQueryDNS)

        let dnsRow = NSStackView(views: [dnsNameLabel, dnsNameField, dnsTypeLabel, dnsTypeField, dnsQueryButton])
        dnsRow.orientation = .horizontal
        dnsRow.spacing = 8
        dnsRow.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 8, right: 12)
        dnsNameField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.addSubview(dnsRow)
        dnsRow.makeConstraints {
            [
                $0.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
                $0.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                $0.trailingAnchor.constraint(equalTo: view.trailingAnchor)
            ]
        }

        LogLevelFilter.allCases.forEach { logLevelPopup.addItem(withTitle: $0.title) }
        logLevelPopup.selectItem(at: LogLevelFilter.all.rawValue)
        logLevelPopup.target = self
        logLevelPopup.action = #selector(actionLogFilterChanged)
        logSearchField.placeholderString = NSLocalizedString("Search logs", comment: "")
        logSearchField.target = self
        logSearchField.action = #selector(actionLogFilterChanged)
        pauseLogsButton.target = self
        pauseLogsButton.action = #selector(actionTogglePauseLogs)

        let logRow = NSStackView(views: [NSTextField(labelWithString: NSLocalizedString("Logs", comment: "")), logLevelPopup, logSearchField, pauseLogsButton])
        logRow.orientation = .horizontal
        logRow.spacing = 8
        logRow.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 8, right: 12)
        logSearchField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.addSubview(logRow)
        logRow.makeConstraints {
            [
                $0.topAnchor.constraint(equalTo: dnsRow.bottomAnchor),
                $0.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                $0.trailingAnchor.constraint(equalTo: view.trailingAnchor)
            ]
        }

        statusLabel.stringValue = NSLocalizedString("Diagnostics actions will probe the active controller and degrade cleanly when an endpoint is unavailable.", comment: "")
        view.addSubview(statusLabel)
        statusLabel.makeConstraints {
            [
                $0.topAnchor.constraint(equalTo: logRow.bottomAnchor),
                $0.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
                $0.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12)
            ]
        }

        outputTextView.isEditable = false
        outputTextView.isSelectable = true
        outputTextView.isRichText = false
        outputTextView.usesFindBar = true
        outputTextView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        outputScrollView.hasVerticalScroller = true
        outputScrollView.drawsBackground = false
        outputScrollView.documentView = outputTextView
        view.addSubview(outputScrollView)
        outputScrollView.makeConstraints {
            [
                $0.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8),
                $0.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
                $0.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
                $0.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12)
            ]
        }
    }

    private func renderOutput() {
        outputTextView.string = [
            "Memory\n------\n\(memoryOutput)",
            "DNS Query\n---------\n\(dnsOutput)",
            "Providers\n---------\n\(providerOutput)",
            "Profile Artifacts\n-----------------\n\(artifactOutput)",
            "Privileged Helper\n-----------------\n\(helperOutput)",
            "Logs\n----\n\(logViewModel.output)"
        ].joined(separator: "\n\n")
    }

    private func setStatus(_ text: String) {
        statusLabel.stringValue = text
    }

    private func updateCapabilityDrivenState() {
        let cache = CapabilityCache.shared
        let disableIfBlocked: (CoreCapability) -> Bool = {
            switch cache.availability(for: $0) {
            case .unsupported, .unauthorized:
                return true
            default:
                return false
            }
        }

        flushDNSButton.isEnabled = !disableIfBlocked(.dnsCacheFlush) && ConfigManager.shared.isRunning
        restartCoreButton.isEnabled = !disableIfBlocked(.restart) && ConfigManager.shared.isRunning
        runGCButton.isEnabled = !disableIfBlocked(.debugGC) && ConfigManager.shared.isRunning
        copyPprofButton.isEnabled = ConfigManager.shared.isRunning
        reloadGeoButton.isEnabled = !disableIfBlocked(.geoUpdate) && ConfigManager.shared.isRunning
        updateGeoButton.isEnabled = !disableIfBlocked(.geoUpdate) && ConfigManager.shared.isRunning
        updateDashboardButton.isEnabled = !disableIfBlocked(.uiUpgrade) && ConfigManager.shared.isRunning
        dnsQueryButton.isEnabled = !disableIfBlocked(.dnsQuery) && ConfigManager.shared.isRunning
        refreshProvidersButton.isEnabled = !disableIfBlocked(.proxyProviders) && ConfigManager.shared.isRunning
        healthCheckProvidersButton.isEnabled = !disableIfBlocked(.proxyProviders) && ConfigManager.shared.isRunning && !httpProxyProviderNames.isEmpty
        restoreLastKnownGoodButton.isEnabled = ConfigManager.shared.isRunning && FileManager.default.fileExists(atPath: Paths.lastKnownGoodConfigURL.path)
        refreshArtifactsButton.isEnabled = true
        openArtifactsButton.isEnabled = FileManager.default.fileExists(atPath: Paths.smartXArtifactsDirectoryURL.path)
        refreshLogsButton.isEnabled = true
        exportBundleButton.isEnabled = true
        exportLogsButton.isEnabled = !logViewModel.output.isEmpty
    }

    private func refreshLogs(announce: Bool = true) {
        let levelIndex = logLevelPopup.indexOfSelectedItem
        let searchQuery = logSearchField.stringValue
        if let status = logViewModel.refresh(levelIndex: levelIndex, searchQuery: searchQuery, announce: announce) {
            setStatus(status)
        }
    }

    private func refreshArtifacts(announce: Bool = true) {
        artifactOutput = [
            DiagnosticsArtifactFormatter.formatArtifactPreview(title: "Successful Reload Artifact",
                                                               configURL: Paths.successfulReloadArtifactURL,
                                                               metadataURL: Paths.successfulReloadMetadataURL),
            DiagnosticsArtifactFormatter.formatArtifactPreview(title: "Last Known Good Config",
                                                               configURL: Paths.lastKnownGoodConfigURL,
                                                               metadataURL: Paths.lastKnownGoodMetadataURL),
            DiagnosticsArtifactFormatter.formatManagedOverrideStatus()
        ].joined(separator: "\n\n")
        if announce {
            setStatus(NSLocalizedString("Profile artifact inspection refreshed.", comment: ""))
        }
        refreshHelperStatus(announce: false)
        renderOutput()
        updateCapabilityDrivenState()
    }

    private func refreshHelperStatus(announce: Bool = true) {
        helperOutput = HelperDiagnosticsProbe.currentStatus().renderedSection(title: "Helper Status")
        if announce {
            setStatus(NSLocalizedString("Privileged helper diagnostics refreshed.", comment: ""))
        }
    }

    private func prettyPrinted(_ json: JSON) -> String {
        let object = json.object
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted]),
              let string = String(data: data, encoding: .utf8)
        else {
            return json.rawString() ?? "\(json)"
        }
        return string
    }

    private func refreshMemory() {
        guard ConfigManager.shared.isRunning else {
            memoryOutput = NSLocalizedString("Core is stopped or controller is unavailable.", comment: "")
            CapabilityCache.shared.markUnavailable(.memorySnapshot, message: memoryOutput)
            setStatus(memoryOutput)
            updateCapabilityDrivenState()
            renderOutput()
            return
        }
        setStatus(NSLocalizedString("Refreshing /memory from the active controller.", comment: ""))
        ApiRequest.requestMemorySnapshot { [weak self] result in
            guard let self else { return }
            CapabilityCache.shared.mark(.memorySnapshot, jsonResult: result)
            switch result {
            case let .success(json):
                self.memoryOutput = self.prettyPrinted(json)
                self.setStatus(NSLocalizedString("Memory diagnostics refreshed successfully.", comment: ""))
            case .unsupported:
                self.memoryOutput = NSLocalizedString("/memory is not supported by the active controller.", comment: "")
                self.setStatus(NSLocalizedString("Memory diagnostics are unsupported by the active controller.", comment: ""))
            case let .unauthorized(message):
                self.memoryOutput = message
                self.setStatus(NSLocalizedString("Memory diagnostics were rejected by the active controller credentials.", comment: ""))
            case let .failed(message):
                self.memoryOutput = message
                self.setStatus(String(format: NSLocalizedString("Memory diagnostics failed: %@", comment: ""), message))
            }
            self.updateCapabilityDrivenState()
            self.renderOutput()
        }
    }

    private func refreshProviders() {
        guard ConfigManager.shared.isRunning else {
            let message = NSLocalizedString("Core is stopped or controller is unavailable.", comment: "")
            latestProxyProviderResult = .failed(message)
            latestRuleProviderResult = .failed(message)
            let formatted = DiagnosticsProviderFormatter.format(proxyResult: latestProxyProviderResult,
                                                                ruleResult: latestRuleProviderResult,
                                                                existingHTTPProxyProviderNames: httpProxyProviderNames)
            providerOutput = formatted.text
            httpProxyProviderNames = formatted.httpProxyProviderNames
            CapabilityCache.shared.markUnavailable(.proxyProviders, message: message)
            CapabilityCache.shared.markUnavailable(.ruleProviders, message: message)
            setStatus(message)
            updateCapabilityDrivenState()
            renderOutput()
            return
        }
        setStatus(NSLocalizedString("Refreshing provider diagnostics from the active controller.", comment: ""))
        let group = DispatchGroup()
        var proxyResult: ControllerJSONResult?
        var ruleResult: ControllerJSONResult?

        group.enter()
        ApiRequest.requestProxyProvidersDiagnostics { result in
            proxyResult = result
            group.leave()
        }

        group.enter()
        ApiRequest.requestRuleProvidersDiagnostics { result in
            ruleResult = result
            group.leave()
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            CapabilityCache.shared.mark(.proxyProviders, jsonResult: proxyResult ?? .failed(NSLocalizedString("Proxy provider diagnostics returned no result.", comment: "")))
            CapabilityCache.shared.mark(.ruleProviders, jsonResult: ruleResult ?? .failed(NSLocalizedString("Rule provider diagnostics returned no result.", comment: "")))

            self.latestProxyProviderResult = proxyResult
            self.latestRuleProviderResult = ruleResult
            let formatted = DiagnosticsProviderFormatter.format(proxyResult: proxyResult,
                                                                ruleResult: ruleResult,
                                                                existingHTTPProxyProviderNames: self.httpProxyProviderNames)
            self.providerOutput = formatted.text
            self.httpProxyProviderNames = formatted.httpProxyProviderNames

            switch (proxyResult, ruleResult) {
            case (.success(_), _), (_, .success(_)):
                self.setStatus(NSLocalizedString("Provider diagnostics refreshed successfully.", comment: ""))
            case let (.unauthorized(message), _):
                self.setStatus(message)
            case let (_, .unauthorized(message)):
                self.setStatus(message)
            case (.unsupported, .unsupported):
                self.setStatus(NSLocalizedString("Provider diagnostics are unsupported by the active controller.", comment: ""))
            default:
                self.setStatus(NSLocalizedString("Provider diagnostics refreshed with partial or degraded results.", comment: ""))
            }

            self.updateCapabilityDrivenState()
            self.renderOutput()
        }
    }

    private func performAction(_ capability: CoreCapability, startText: String, successText: String, unsupportedText: String, unauthorizedText: String, action: (@escaping (ControllerEndpointResult) -> Void) -> Void) {
        setStatus(startText)
        action { [weak self] result in
            guard let self else { return }
            CapabilityCache.shared.mark(capability, endpointResult: result)
            switch result {
            case .success:
                self.setStatus(successText)
            case .unsupported:
                self.setStatus(unsupportedText)
            case .unauthorized:
                self.setStatus(unauthorizedText)
            case let .failed(message):
                self.setStatus(message)
            }
            self.updateCapabilityDrivenState()
        }
    }

    private func performMaintenanceAction(_ action: DiagnosticsMaintenanceAction) {
        maintenanceCoordinator.perform(action,
                                       confirm: { [weak self] title, message, confirmTitle in
                                           self?.confirmMaintenanceAction(title: title, message: message, confirmTitle: confirmTitle) ?? false
                                       },
                                       setStatus: { [weak self] text in
                                           self?.setStatus(text)
                                       }) { [weak self] in
            guard let self else { return }
            self.updateCapabilityDrivenState()
        }
    }

    @objc private func actionRefreshMemory() {
        refreshMemory()
    }

    @objc private func actionRefreshProviders() {
        refreshProviders()
    }

    @objc private func actionFlushDNSCache() {
        performAction(
            .dnsCacheFlush,
            startText: NSLocalizedString("Flushing DNS cache.", comment: ""),
            successText: NSLocalizedString("DNS cache flushed successfully.", comment: ""),
            unsupportedText: NSLocalizedString("DNS cache flush is unsupported by the active controller.", comment: ""),
            unauthorizedText: NSLocalizedString("DNS cache flush was rejected by the active controller credentials.", comment: "")
        ) { completion in
            ApiRequest.resetDNSCache(completeHandler: completion)
        }
    }

    @objc private func actionFlushFakeIPCache() {
        ApiRequest.resetFakeIpCache { [weak self] result in
            guard let self else { return }
            CapabilityCache.shared.mark(.dnsCacheFlush, endpointResult: result)
            switch result {
            case .success:
                self.setStatus(NSLocalizedString("Fake-IP cache flush requested.", comment: ""))
            case .unsupported:
                self.setStatus(NSLocalizedString("Fake-IP cache flush is unsupported by the active controller.", comment: ""))
            case .unauthorized:
                self.setStatus(NSLocalizedString("Fake-IP cache flush was rejected by the active controller credentials.", comment: ""))
            case let .failed(message):
                self.setStatus(message)
            }
            self.updateCapabilityDrivenState()
        }
    }

    @objc private func actionRestartCore() {
        performMaintenanceAction(.restartCore)
    }

    @objc private func actionRunGC() {
        performMaintenanceAction(.runDebugGC)
    }

    @objc private func actionCopyPprofURLs() {
        guard let urls = DiagnosticsAPI.pprofURLs() else {
            setStatus(NSLocalizedString("The active controller URL is invalid, so pprof URLs could not be prepared.", comment: ""))
            return
        }

        let text = [
            "SmartX pprof helpers",
            "Add the controller Authorization header manually if needed.",
            urls.map(\.absoluteString).joined(separator: "\n")
        ].joined(separator: "\n\n")

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        CapabilityCache.shared.set(.debugPprof, availability: .available, message: NSLocalizedString("Copied pprof helper URLs to the pasteboard.", comment: ""))
        setStatus(NSLocalizedString("pprof helper URLs were copied to the pasteboard.", comment: ""))
    }

    @objc private func actionReloadGeoConfig() {
        performAction(
            .geoUpdate,
            startText: NSLocalizedString("Reloading GEO configuration.", comment: ""),
            successText: NSLocalizedString("GEO configuration reloaded successfully.", comment: ""),
            unsupportedText: NSLocalizedString("GEO configuration reload is unsupported by the active controller.", comment: ""),
            unauthorizedText: NSLocalizedString("GEO configuration reload was rejected by the active controller credentials.", comment: "")
        ) { completion in
            ApiRequest.reloadGeoDatabase(completeHandler: completion)
        }
    }

    @objc private func actionUpdateGeoAssets() {
        performMaintenanceAction(.updateGeoAssets)
    }

    @objc private func actionUpdateDashboardAssets() {
        performMaintenanceAction(.updateDashboardAssets)
    }

    @objc private func actionCopyDiagnosticsReport() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(DiagnosticsReportBuilder.build(), forType: .string)
        setStatus(NSLocalizedString("A sanitized diagnostics report was copied to the pasteboard.", comment: ""))
    }

    @objc private func actionRefreshArtifacts() {
        refreshArtifacts()
    }

    @objc private func actionOpenArtifactsFolder() {
        let directoryURL = Paths.smartXArtifactsDirectoryURL
        guard FileManager.default.fileExists(atPath: directoryURL.path) else {
            setStatus(NSLocalizedString("The SmartX profile artifacts directory does not exist yet.", comment: ""))
            updateCapabilityDrivenState()
            return
        }

        NSWorkspace.shared.open(directoryURL)
        setStatus(NSLocalizedString("Opened the SmartX profile artifacts directory.", comment: ""))
    }

    @objc private func actionExportDiagnosticsBundle() {
        let savePanel = NSSavePanel()
        let timestamp = DateFormatter.exportStamp.string(from: Date())
        savePanel.nameFieldStringValue = "smartx-diagnostics-\(timestamp).smartxdiag"
        savePanel.canCreateDirectories = true

        let handleSave: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self, response == .OK, let url = savePanel.url else { return }
            do {
                try DiagnosticsBundleExporter.export(to: url)
                self.setStatus(NSLocalizedString("A sanitized diagnostics bundle was exported successfully.", comment: ""))
            } catch {
                self.setStatus(String(format: NSLocalizedString("Failed to export diagnostics bundle: %@", comment: ""), error.localizedDescription))
            }
        }

        if let window = view.window ?? NSApp.mainWindow {
            savePanel.beginSheetModal(for: window, completionHandler: handleSave)
        } else {
            handleSave(savePanel.runModal())
        }
    }

    @objc private func actionRestoreLastKnownGood() {
        guard FileManager.default.fileExists(atPath: Paths.lastKnownGoodConfigURL.path) else {
            setStatus(NSLocalizedString("No last-known-good profile artifact is available yet.", comment: ""))
            updateCapabilityDrivenState()
            return
        }

        let metadata = ProfileArtifactManager.loadMetadata(at: Paths.lastKnownGoodMetadataURL)
        let profileName = metadata?.selectedProfileName ?? ConfigManager.selectConfigName
        let sourcePath = metadata?.sourceConfigPath ?? Paths.lastKnownGoodConfigURL.path
        let message = String(format: NSLocalizedString("This will reload the saved last-known-good config for profile %@.\nSource: %@", comment: ""),
                             profileName,
                             SmartXRedactor.redactPath(sourcePath) ?? sourcePath)
        guard confirmMaintenanceAction(title: NSLocalizedString("Restore last-known-good profile artifact?", comment: ""),
                                       message: message,
                                       confirmTitle: NSLocalizedString("Restore", comment: ""))
        else { return }

        setStatus(NSLocalizedString("Restoring the last-known-good profile artifact.", comment: ""))
        AppDelegate.shared.restoreLastKnownGoodConfig(showNotification: false) { [weak self] error in
            guard let self else { return }
            if let error {
                self.setStatus(String(format: NSLocalizedString("Last-known-good restore failed: %@", comment: ""), error))
            } else {
                self.setStatus(NSLocalizedString("Last-known-good profile artifact restored successfully.", comment: ""))
                self.refreshMemory()
                self.refreshProviders()
                self.refreshArtifacts(announce: false)
            }
            self.updateCapabilityDrivenState()
        }
    }

    @objc private func actionHealthCheckProviders() {
        guard !httpProxyProviderNames.isEmpty else {
            setStatus(NSLocalizedString("Refresh providers before requesting provider health checks.", comment: ""))
            return
        }

        setStatus(String(format: NSLocalizedString("Running health checks for %d proxy providers.", comment: ""), httpProxyProviderNames.count))
        let group = DispatchGroup()
        var succeeded = [String]()
        var failed = [String]()
        let timestamp = DateFormatter.simple.string(from: Date())
        // ponytail: serial queue protects concurrent appends from Alamofire callbacks
        let healthQueue = DispatchQueue(label: "com.smartx.provider.health")

        for provider in httpProxyProviderNames {
            group.enter()
            ApiRequest.healthCheckProvider(proxy: provider) { success in
                healthQueue.async {
                    if success {
                        succeeded.append(provider)
                    } else {
                        failed.append(provider)
                    }
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            ProviderHealthHistoryManager.append(succeeded: succeeded, failed: failed)
            let summary = self.providerHealthCheckSummary(timestamp: timestamp, succeeded: succeeded.sorted(), failed: failed.sorted())
            let formatted = DiagnosticsProviderFormatter.format(proxyResult: self.latestProxyProviderResult,
                                                                ruleResult: self.latestRuleProviderResult,
                                                                existingHTTPProxyProviderNames: self.httpProxyProviderNames)
            self.providerOutput = "\(formatted.text)\n\n\(summary)"
            self.httpProxyProviderNames = formatted.httpProxyProviderNames
            self.setStatus(String(format: NSLocalizedString("Finished provider health checks. Success: %d, Failed: %d.", comment: ""), succeeded.count, failed.count))
            self.renderOutput()
        }
    }

    @objc private func actionQueryDNS() {
        let name = dnsNameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let type = dnsTypeField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            setStatus(NSLocalizedString("Enter a DNS name before querying diagnostics.", comment: ""))
            return
        }
        guard ConfigManager.shared.isRunning else {
            let message = NSLocalizedString("Core is stopped or controller is unavailable.", comment: "")
            CapabilityCache.shared.markUnavailable(.dnsQuery, message: message)
            dnsOutput = message
            setStatus(message)
            updateCapabilityDrivenState()
            renderOutput()
            return
        }

        setStatus(String(format: NSLocalizedString("Querying DNS diagnostics for %@.", comment: ""), name))
        ApiRequest.requestDNSQuery(name: name, type: type.isEmpty ? nil : type) { [weak self] result in
            guard let self else { return }
            CapabilityCache.shared.mark(.dnsQuery, jsonResult: result)
            switch result {
            case let .success(json):
                self.dnsOutput = self.prettyPrinted(json)
                self.setStatus(String(format: NSLocalizedString("DNS diagnostics query for %@ succeeded.", comment: ""), name))
            case .unsupported:
                self.dnsOutput = NSLocalizedString("/dns/query is not supported by the active controller.", comment: "")
                self.setStatus(NSLocalizedString("DNS diagnostics are unsupported by the active controller.", comment: ""))
            case let .unauthorized(message):
                self.dnsOutput = message
                self.setStatus(NSLocalizedString("DNS diagnostics were rejected by the active controller credentials.", comment: ""))
            case let .failed(message):
                self.dnsOutput = message
                self.setStatus(String(format: NSLocalizedString("DNS diagnostics query failed: %@", comment: ""), message))
            }
            self.updateCapabilityDrivenState()
            self.renderOutput()
        }
    }

    @objc private func actionRefreshLogs() {
        refreshLogs()
    }

    @objc private func actionExportLogs() {
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = "smartx-diagnostics-logs.txt"
        savePanel.canCreateDirectories = true
        let handleSave: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self, response == .OK, let url = savePanel.url else { return }
            do {
                let rawText = self.logViewModel.snapshot?.renderedOutput(redactFilePath: true) ?? self.logViewModel.output
                let exportText = SmartXRedactor.sanitizeText(rawText)
                try exportText.write(to: url, atomically: true, encoding: .utf8)
                self.setStatus(NSLocalizedString("Sanitized log output was exported successfully.", comment: ""))
            } catch {
                self.setStatus(String(format: NSLocalizedString("Failed to export filtered log output: %@", comment: ""), error.localizedDescription))
            }
        }

        if let window = view.window ?? NSApp.mainWindow {
            savePanel.beginSheetModal(for: window, completionHandler: handleSave)
        } else {
            handleSave(savePanel.runModal())
        }
    }

    @objc private func actionLogFilterChanged() {
        refreshLogs()
    }

    @objc private func actionTogglePauseLogs() {
        logViewModel.togglePause()
        let paused = logViewModel.paused
        pauseLogsButton.state = paused ? .on : .off
        setStatus(paused
            ? NSLocalizedString("Automatic log refresh is paused.", comment: "")
            : NSLocalizedString("Automatic log refresh resumed.", comment: ""))
        if !paused {
            refreshLogs(announce: false)
        } else {
            renderOutput()
        }
    }

    private func providerHealthCheckSummary(timestamp: String, succeeded: [String], failed: [String]) -> String {
        var lines = ["Provider Health Check @ \(timestamp)"]
        if succeeded.isEmpty {
            lines.append("Succeeded: none")
        } else {
            lines.append("Succeeded: \(succeeded.joined(separator: ", "))")
        }

        if failed.isEmpty {
            lines.append("Failed: none")
        } else {
            lines.append("Failed: \(failed.joined(separator: ", "))")
        }
        return lines.joined(separator: "\n")
    }

    private func confirmMaintenanceAction(title: String, message: String, confirmTitle: String) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: confirmTitle)
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }
}

private extension DateFormatter {
    static let exportStamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}

@available(macOS 10.15, *)
extension DiagnosticsDashboardViewController: DashboardSubViewControllerProtocol {
    func actionSearch(string: String) {
        logSearchField.stringValue = string
        refreshLogs(announce: false)
    }
}
