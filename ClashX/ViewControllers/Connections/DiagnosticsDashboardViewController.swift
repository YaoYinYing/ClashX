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
    private enum LogLevelFilter: Int, CaseIterable {
        case all
        case error
        case warning
        case info
        case debug

        var title: String {
            switch self {
            case .all:
                return NSLocalizedString("All", comment: "")
            case .error:
                return NSLocalizedString("Error", comment: "")
            case .warning:
                return NSLocalizedString("Warning", comment: "")
            case .info:
                return NSLocalizedString("Info", comment: "")
            case .debug:
                return NSLocalizedString("Debug", comment: "")
            }
        }

        var token: String? {
            switch self {
            case .all:
                return nil
            case .error:
                return "[error]"
            case .warning:
                return "[warning]"
            case .info:
                return "[info]"
            case .debug:
                return "[debug]"
            }
        }
    }

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

    private var memoryOutput = NSLocalizedString("Memory diagnostics have not been loaded yet.", comment: "")
    private var dnsOutput = NSLocalizedString("DNS diagnostics have not been queried yet.", comment: "")
    private var providerOutput = NSLocalizedString("Provider diagnostics have not been loaded yet.", comment: "")
    private var artifactOutput = NSLocalizedString("Profile artifacts have not been inspected yet.", comment: "")
    private var logOutput = NSLocalizedString("Log viewer has not loaded any log lines yet.", comment: "")
    private var httpProxyProviderNames = [String]()
    private var latestProxyProviderResult: ControllerJSONResult?
    private var latestRuleProviderResult: ControllerJSONResult?
    private var logRefreshTimer: Timer?
    private var isLogRefreshPaused = false

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
        refreshLogs()
        startLogRefreshTimer()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        logRefreshTimer?.invalidate()
        logRefreshTimer = nil
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
            "Logs\n----\n\(logOutput)"
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
        exportLogsButton.isEnabled = !logOutput.isEmpty
    }

    private func startLogRefreshTimer() {
        logRefreshTimer?.invalidate()
        logRefreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self, !self.isLogRefreshPaused else { return }
            self.refreshLogs(announce: false)
        }
    }

    private func refreshLogs(announce: Bool = true) {
        let path = Logger.shared.logFilePath()
        guard !path.isEmpty else {
            logOutput = NSLocalizedString("No active log file is available yet.", comment: "")
            if announce {
                setStatus(NSLocalizedString("No active log file is available yet.", comment: ""))
            }
            renderOutput()
            updateCapabilityDrivenState()
            return
        }

        do {
            let filter = LogLevelFilter(rawValue: logLevelPopup.indexOfSelectedItem) ?? .all
            let snapshot = try DiagnosticsLogReader.load(path: path,
                                                         filterTitle: filter.title,
                                                         filterToken: filter.token,
                                                         searchQuery: logSearchField.stringValue,
                                                         paused: isLogRefreshPaused)
            logOutput = snapshot.renderedOutput()
            if announce {
                setStatus(NSLocalizedString("Log viewer refreshed from the current rolling log file.", comment: ""))
            }
        } catch {
            logOutput = String(format: NSLocalizedString("The current log file could not be read: %@", comment: ""), path)
            if announce {
                setStatus(NSLocalizedString("Failed to read the current log file.", comment: ""))
            }
        }
        renderOutput()
        updateCapabilityDrivenState()
    }

    private func refreshArtifacts(announce: Bool = true) {
        artifactOutput = [
            formatArtifactPreview(title: "Successful Reload Artifact",
                                  configURL: Paths.successfulReloadArtifactURL,
                                  metadataURL: Paths.successfulReloadMetadataURL),
            formatArtifactPreview(title: "Last Known Good Config",
                                  configURL: Paths.lastKnownGoodConfigURL,
                                  metadataURL: Paths.lastKnownGoodMetadataURL)
        ].joined(separator: "\n\n")
        if announce {
            setStatus(NSLocalizedString("Profile artifact inspection refreshed.", comment: ""))
        }
        renderOutput()
        updateCapabilityDrivenState()
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
            providerOutput = formatProviderDiagnostics(proxyResult: latestProxyProviderResult, ruleResult: latestRuleProviderResult)
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
            self.providerOutput = self.formatProviderDiagnostics(proxyResult: proxyResult, ruleResult: ruleResult)

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
        guard confirmMaintenanceAction(title: NSLocalizedString("Restart core?", comment: ""),
                                       message: NSLocalizedString("This will ask the active controller to restart immediately. Existing controller activity may be interrupted.", comment: ""),
                                       confirmTitle: NSLocalizedString("Restart", comment: ""))
        else { return }
        performAction(
            .restart,
            startText: NSLocalizedString("Requesting controller restart.", comment: ""),
            successText: NSLocalizedString("Controller restart requested successfully.", comment: ""),
            unsupportedText: NSLocalizedString("Controller restart is unsupported by the active controller.", comment: ""),
            unauthorizedText: NSLocalizedString("Controller restart was rejected by the active controller credentials.", comment: "")
        ) { completion in
            ApiRequest.restartCore(completeHandler: completion)
        }
    }

    @objc private func actionRunGC() {
        guard confirmMaintenanceAction(title: NSLocalizedString("Run debug GC?", comment: ""),
                                       message: NSLocalizedString("This sends a debug garbage-collection request to the active controller. Use it only for diagnostics.", comment: ""),
                                       confirmTitle: NSLocalizedString("Run GC", comment: ""))
        else { return }
        performAction(
            .debugGC,
            startText: NSLocalizedString("Requesting controller garbage collection.", comment: ""),
            successText: NSLocalizedString("Controller garbage collection requested successfully.", comment: ""),
            unsupportedText: NSLocalizedString("Debug GC is unsupported by the active controller.", comment: ""),
            unauthorizedText: NSLocalizedString("Debug GC was rejected by the active controller credentials.", comment: "")
        ) { completion in
            ApiRequest.runDebugGC(completeHandler: completion)
        }
    }

    @objc private func actionCopyPprofURLs() {
        guard let baseURL = try? ControllerEndpointBuilder.baseHTTPURL() else {
            setStatus(NSLocalizedString("The active controller URL is invalid, so pprof URLs could not be prepared.", comment: ""))
            return
        }

        let urls = [
            try? ControllerEndpointBuilder.composeURL(baseURL: baseURL, path: "/debug/pprof"),
            try? ControllerEndpointBuilder.composeURL(baseURL: baseURL, path: "/debug/pprof/goroutine"),
            try? ControllerEndpointBuilder.composeURL(baseURL: baseURL, path: "/debug/pprof/heap"),
            try? ControllerEndpointBuilder.composeURL(baseURL: baseURL, path: "/debug/pprof/profile")
        ].compactMap { $0 }

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
        guard confirmMaintenanceAction(title: NSLocalizedString("Update GEO assets?", comment: ""),
                                       message: NSLocalizedString("This asks the active controller to refresh GEO databases and related assets. It is a maintenance action, not a read-only diagnostic.", comment: ""),
                                       confirmTitle: NSLocalizedString("Update GEO", comment: ""))
        else { return }
        performAction(
            .geoUpdate,
            startText: NSLocalizedString("Updating GEO assets.", comment: ""),
            successText: NSLocalizedString("GEO asset update requested successfully.", comment: ""),
            unsupportedText: NSLocalizedString("GEO asset update is unsupported by the active controller.", comment: ""),
            unauthorizedText: NSLocalizedString("GEO asset update was rejected by the active controller credentials.", comment: "")
        ) { completion in
            ApiRequest.updateGeoAssets(completeHandler: completion)
        }
    }

    @objc private func actionUpdateDashboardAssets() {
        guard confirmMaintenanceAction(title: NSLocalizedString("Update dashboard assets?", comment: ""),
                                       message: NSLocalizedString("This requests a dashboard asset update from the active controller. Use it only when you intend to modify installed assets.", comment: ""),
                                       confirmTitle: NSLocalizedString("Update Dashboard", comment: ""))
        else { return }
        performAction(
            .uiUpgrade,
            startText: NSLocalizedString("Updating dashboard assets.", comment: ""),
            successText: NSLocalizedString("Dashboard asset update requested successfully.", comment: ""),
            unsupportedText: NSLocalizedString("Dashboard asset update is unsupported by the active controller.", comment: ""),
            unauthorizedText: NSLocalizedString("Dashboard asset update was rejected by the active controller credentials.", comment: "")
        ) { completion in
            ApiRequest.updateDashboardAssets(completeHandler: completion)
        }
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

        for provider in httpProxyProviderNames {
            group.enter()
            ApiRequest.healthCheckProvider(proxy: provider) { success in
                if success {
                    succeeded.append(provider)
                } else {
                    failed.append(provider)
                }
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            ProviderHealthHistoryManager.append(succeeded: succeeded, failed: failed)
            let summary = self.providerHealthCheckSummary(timestamp: timestamp, succeeded: succeeded.sorted(), failed: failed.sorted())
            self.providerOutput = "\(self.formatProviderDiagnostics(proxyResult: self.latestProxyProviderResult, ruleResult: self.latestRuleProviderResult))\n\n\(summary)"
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
                try self.logOutput.write(to: url, atomically: true, encoding: .utf8)
                self.setStatus(NSLocalizedString("Filtered log output was exported successfully.", comment: ""))
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
        isLogRefreshPaused = pauseLogsButton.state == .on
        setStatus(isLogRefreshPaused
            ? NSLocalizedString("Automatic log refresh is paused.", comment: "")
            : NSLocalizedString("Automatic log refresh resumed.", comment: ""))
        if !isLogRefreshPaused {
            refreshLogs(announce: false)
        } else {
            renderOutput()
        }
    }

    private func formatProviderDiagnostics(proxyResult: ControllerJSONResult?, ruleResult: ControllerJSONResult?) -> String {
        let proxySection = providerSection(title: "Proxy Providers", result: proxyResult, capability: .proxyProviders)
        let ruleSection = providerSection(title: "Rule Providers", result: ruleResult, capability: .ruleProviders)
        let historySection = ProviderHealthHistoryManager.summary(limit: 5)
        return [proxySection, ruleSection, historySection].joined(separator: "\n\n")
    }

    private func providerSection(title: String, result: ControllerJSONResult?, capability: CoreCapability) -> String {
        var lines = [title]
        let result = result ?? .failed(NSLocalizedString("No response.", comment: ""))

        switch result {
        case let .success(json):
            let providers = json["providers"].dictionaryValue
            let providerNames = providers.keys.sorted()
            if capability == .proxyProviders {
                httpProxyProviderNames = providerNames.filter {
                    providers[$0]?["vehicleType"].stringValue.caseInsensitiveCompare("http") == .orderedSame
                }
            }

            lines.append("Count: \(providerNames.count)")
            if providerNames.isEmpty {
                lines.append("None reported.")
            } else {
                for name in providerNames {
                    let provider = providers[name]
                    let vehicleType = provider?["vehicleType"].stringValue ?? "unknown"
                    let providerType = provider?["type"].stringValue ?? "unknown"
                    let proxyCount = provider?["proxies"].arrayValue.count ?? 0
                    lines.append("- \(name) [\(providerType)/\(vehicleType)] proxies=\(proxyCount)")
                }
            }
        case .unsupported:
            if capability == .proxyProviders {
                httpProxyProviderNames = []
            }
            lines.append("Unsupported by the active controller.")
        case let .unauthorized(message):
            if capability == .proxyProviders {
                httpProxyProviderNames = []
            }
            lines.append("Unauthorized: \(message)")
        case let .failed(message):
            if capability == .proxyProviders {
                httpProxyProviderNames = []
            }
            lines.append("Failed: \(message)")
        }

        return lines.joined(separator: "\n")
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

    private func formatArtifactPreview(title: String, configURL: URL, metadataURL: URL) -> String {
        var lines = [title]
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: configURL.path) else {
            lines.append("Status: missing")
            return lines.joined(separator: "\n")
        }

        lines.append("Path: \(SmartXRedactor.redactPath(configURL.path) ?? configURL.path)")
        if let metadata = ProfileArtifactManager.loadMetadata(at: metadataURL) {
            lines.append("Profile: \(metadata.selectedProfileName) [\(metadata.selectedProfileKind)]")
            lines.append("Source: \(SmartXRedactor.redactPath(metadata.sourceConfigPath) ?? metadata.sourceConfigPath)")
            if let remoteURL = metadata.sourceRemoteURL, !remoteURL.isEmpty {
                lines.append("Remote Source: \(SmartXRedactor.redactURLString(remoteURL) ?? "<redacted-url>")")
            }
            lines.append("Generated: \(DateFormatter.localizedString(from: metadata.generatedAt, dateStyle: .short, timeStyle: .medium))")
            lines.append("Controller Mode: \(metadata.controllerMode)")
            lines.append("Generation Mode: \(metadata.generationMode == "source-copy" ? "Loaded Source Copy" : metadata.generationMode)")
            lines.append("Includes SmartX Overrides: \(metadata.includesSmartXOverrides ? "yes" : "no")")
            lines.append("Includes Profile Merge: \(metadata.includesProfileMerge ? "yes" : "no")")
            lines.append("Includes Runtime Overrides: \(metadata.includesRuntimeOverrides ? "yes" : "no")")
        } else {
            lines.append("Metadata: unavailable")
        }

        let preview = (try? String(contentsOf: configURL, encoding: .utf8))
            .map { previewText(from: $0, maxLines: 20) }
            ?? NSLocalizedString("Config preview could not be read.", comment: "")
        lines.append("Preview:")
        lines.append(preview)
        return lines.joined(separator: "\n")
    }

    private func previewText(from raw: String, maxLines: Int) -> String {
        let lines = raw.components(separatedBy: .newlines)
        let head = Array(lines.prefix(maxLines))
        var preview = head.joined(separator: "\n")
        if lines.count > maxLines {
            preview.append("\n...")
        }
        return preview.isEmpty ? NSLocalizedString("(empty file)", comment: "") : preview
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
