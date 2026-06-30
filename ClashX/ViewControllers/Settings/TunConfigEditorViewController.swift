//
//  TunConfigEditorViewController.swift
//  ClashX
//
//  Created by SmartX on 2026/6/11.
//

import Cocoa

/// Structured editor for all macOS-relevant mihomo TUN configuration fields.
/// Provides live validation, macOS-specific field filtering, and apply/reset.
///
/// ponytail: YAML upsert is string-based rather than parse-modify-emit. Ceiling:
/// comments in the tun block are lost on rewrite, and non-standard indent styles
/// are normalized. Upgrade path: switch to a YAML parse-emit round-trip when
/// SmartX grows a real config workspace pipeline (Phase 9).
final class TunConfigEditorViewController: NSViewController {
    private final class FlippedView: NSView {
        override var isFlipped: Bool { true }
    }

    // MARK: - Controls

    private let enableCheckbox = NSButton(checkboxWithTitle: NSLocalizedString("Enable TUN", comment: ""), target: nil, action: nil)
    private let deviceField = NSTextField(string: "")
    private let stackPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let dnsHijackField = NSTextField(string: "")
    private let autoRouteCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let autoDetectInterfaceCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let strictRouteCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let mtuField = NSTextField(string: "")
    private let udpTimeoutField = NSTextField(string: "")
    private let routeAddressField = NSTextField(string: "")
    private let routeExcludeAddressField = NSTextField(string: "")
    private let includeInterfaceField = NSTextField(string: "")
    private let excludeInterfaceField = NSTextField(string: "")

    private let validationLabel = NSTextField(wrappingLabelWithString: "")
    private let applyButton = NSButton(title: NSLocalizedString("Apply TUN Config", comment: ""), target: nil, action: nil)
    private let resetButton = NSButton(title: NSLocalizedString("Reset to Current", comment: ""), target: nil, action: nil)
    private let statusLabel = NSTextField(wrappingLabelWithString: "")

    private let scrollView = NSScrollView()
    private let documentView = FlippedView()
    private let contentStack = NSStackView()

    private var currentConfig: ClashConfig.Tun?
    private var isApplying = false

    private let pagePadding: CGFloat = 24
    private let rowTitleWidth: CGFloat = 180

    // MARK: - Lifecycle

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 580, height: 600))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = NSLocalizedString("TUN Configuration", comment: "")
        setupView()
        refreshFromCurrentConfig()
    }

    // MARK: - Setup

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
        contentStack.spacing = 12
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

            contentStack.topAnchor.constraint(equalTo: documentView.topAnchor, constant: pagePadding),
            contentStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: pagePadding),
            contentStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -pagePadding),
            contentStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -pagePadding)
        ])

        // Stack popup options
        stackPopup.addItems(withTitles: ["gvisor", "system", "lwip"])
        stackPopup.selectItem(at: 0)

        // Number field styling
        mtuField.placeholderString = "9000"
        mtuField.formatter = numberFormatter(min: 576, max: 9000)
        udpTimeoutField.placeholderString = "300"
        udpTimeoutField.formatter = numberFormatter(min: 1, max: 86400)

        // Multi-value field placeholders
        deviceField.placeholderString = NSLocalizedString("utun (auto if empty)", comment: "")
        dnsHijackField.placeholderString = NSLocalizedString("any:53, tcp://any:53 (comma-separated)", comment: "")
        routeAddressField.placeholderString = NSLocalizedString("0.0.0.0/0, ::/0 (CIDR, comma-separated)", comment: "")
        routeExcludeAddressField.placeholderString = NSLocalizedString("10.0.0.0/8 (CIDR, comma-separated)", comment: "")
        includeInterfaceField.placeholderString = NSLocalizedString("en0 (comma-separated)", comment: "")
        excludeInterfaceField.placeholderString = NSLocalizedString("utun1 (comma-separated)", comment: "")

        // Button setup
        applyButton.target = self
        applyButton.action = #selector(actionApply)
        applyButton.bezelStyle = .rounded
        applyButton.keyEquivalent = "\r"
        resetButton.target = self
        resetButton.action = #selector(actionReset)
        resetButton.bezelStyle = .rounded

        validationLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        validationLabel.textColor = .systemRed
        validationLabel.maximumNumberOfLines = 0

        statusLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.maximumNumberOfLines = 0

        // Build sections
        addFullWidthSection(title: NSLocalizedString("Basic", comment: ""), rows: [
            checkboxRow(checkbox: enableCheckbox),
            labeledRow(title: NSLocalizedString("Device", comment: ""), view: deviceField),
            labeledRow(title: NSLocalizedString("Stack", comment: ""), view: stackPopup),
            labeledRow(title: NSLocalizedString("DNS Hijack", comment: ""), view: dnsHijackField),
            checkboxRow(checkbox: autoRouteCheckbox, label: NSLocalizedString("Auto Route", comment: "")),
            checkboxRow(checkbox: autoDetectInterfaceCheckbox, label: NSLocalizedString("Auto Detect Interface", comment: ""))
        ], note: NSLocalizedString("Basic TUN settings control the core TUN device behavior. Device name should follow utun conventions on macOS.", comment: ""))

        addFullWidthSection(title: NSLocalizedString("Network", comment: ""), rows: [
            labeledRow(title: NSLocalizedString("MTU", comment: ""), view: mtuField),
            labeledRow(title: NSLocalizedString("UDP Timeout", comment: ""), view: udpTimeoutField),
            labeledRow(title: NSLocalizedString("Route Address", comment: ""), view: routeAddressField),
            labeledRow(title: NSLocalizedString("Route Exclude", comment: ""), view: routeExcludeAddressField)
        ], note: NSLocalizedString("MTU range: 576–9000. UDP timeout must be positive. Route addresses use CIDR notation (e.g. 0.0.0.0/0, ::/0).", comment: ""))

        addFullWidthSection(title: NSLocalizedString("Advanced", comment: ""), rows: [
            checkboxRow(checkbox: strictRouteCheckbox, label: NSLocalizedString("Strict Route ⚠", comment: "")),
            labeledRow(title: NSLocalizedString("Include Interface", comment: ""), view: includeInterfaceField),
            labeledRow(title: NSLocalizedString("Exclude Interface", comment: ""), view: excludeInterfaceField)
        ], note: NSLocalizedString("Strict-route can break local macOS workflows. Setting both include-interface and exclude-interface requires expert review. These are advanced settings — test carefully.", comment: ""))

        // Validation + buttons
        addFullWidthArrangedSubview(validationLabel)
        let buttonRow = NSStackView(views: [applyButton, resetButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 12
        addFullWidthArrangedSubview(buttonRow)
        addFullWidthArrangedSubview(statusLabel)
    }

    // MARK: - Data flow

    private func refreshFromCurrentConfig() {
        let tun = ConfigManager.shared.currentConfig?.tun
        currentConfig = tun

        if let tun {
            // Load existing config.
            enableCheckbox.state = tun.enable ? .on : .off
            deviceField.stringValue = tun.device ?? ""
            if let stack = tun.stack, let idx = stackPopup.itemTitles.firstIndex(of: stack) {
                stackPopup.selectItem(at: idx)
            } else {
                stackPopup.selectItem(at: 0)
            }
            dnsHijackField.stringValue = (tun.dnsHijack ?? []).joined(separator: ", ")
            autoRouteCheckbox.state = (tun.autoRoute ?? false) ? .on : .off
            autoDetectInterfaceCheckbox.state = (tun.autoDetectInterface ?? false) ? .on : .off
            strictRouteCheckbox.state = (tun.strictRoute ?? false) ? .on : .off
            mtuField.integerValue = tun.mtu ?? 0
            udpTimeoutField.integerValue = tun.udpTimeout ?? 0
            routeAddressField.stringValue = (tun.routeAddress ?? []).joined(separator: ", ")
            routeExcludeAddressField.stringValue = (tun.routeExcludeAddress ?? []).joined(separator: ", ")
            includeInterfaceField.stringValue = (tun.includeInterface ?? []).joined(separator: ", ")
            excludeInterfaceField.stringValue = (tun.excludeInterface ?? []).joined(separator: ", ")

            statusLabel.stringValue = NSLocalizedString("Loaded current TUN config from controller state.", comment: "")
        } else {
            // No existing tun section: pre-fill sensible macOS defaults to help the user get started.
            enableCheckbox.state = .on
            deviceField.stringValue = ""
            stackPopup.selectItem(withTitle: "gvisor")
            dnsHijackField.stringValue = "any:53"
            autoRouteCheckbox.state = .on
            autoDetectInterfaceCheckbox.state = .on
            strictRouteCheckbox.state = .off
            mtuField.integerValue = 9000
            udpTimeoutField.integerValue = 300
            routeAddressField.stringValue = "0.0.0.0/0, ::/0"
            routeExcludeAddressField.stringValue = ""
            includeInterfaceField.stringValue = ""
            excludeInterfaceField.stringValue = ""

            statusLabel.stringValue = NSLocalizedString("No TUN section exists yet. Defaults are pre-filled — adjust and apply to create one.", comment: "")
        }

        validateLive()
    }

    private func validateLive() {
        let input = collectInput()
        let result = TunConfigValidator.validate(input)
        if let blocker = result.blockingErrors.first {
            validationLabel.stringValue = "🚫 \(blocker.message)"
            validationLabel.textColor = .systemRed
        } else if let warning = result.warnings.first {
            validationLabel.stringValue = "⚠ \(warning.message)"
            validationLabel.textColor = .systemOrange
        } else if let info = result.informational.first {
            validationLabel.stringValue = "ℹ \(info.message)"
            validationLabel.textColor = .secondaryLabelColor
        } else {
            validationLabel.stringValue = ""
        }
    }

    private func collectInput() -> TunConfigValidationInput {
        let parseList: (NSTextField) -> [String]? = { field in
            let raw = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { return nil }
            return raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }

        return TunConfigValidationInput(
            enable: enableCheckbox.state == .on,
            device: deviceField.stringValue.trimmingCharacters(in: .whitespaces).nilIfEmpty,
            stack: stackPopup.titleOfSelectedItem,
            dnsHijack: parseList(dnsHijackField),
            autoRoute: autoRouteCheckbox.state == .on,
            autoDetectInterface: autoDetectInterfaceCheckbox.state == .on,
            strictRoute: strictRouteCheckbox.state == .on,
            mtu: mtuField.integerValue > 0 ? mtuField.integerValue : nil,
            udpTimeout: udpTimeoutField.integerValue > 0 ? udpTimeoutField.integerValue : nil,
            routeAddress: parseList(routeAddressField),
            routeExcludeAddress: parseList(routeExcludeAddressField),
            includeInterface: parseList(includeInterfaceField),
            excludeInterface: parseList(excludeInterfaceField)
        )
    }

    // MARK: - Actions

    @objc private func actionApply() {
        guard !isApplying else { return }
        let input = collectInput()
        let result = TunConfigValidator.validate(input)
        guard result.blockingErrors.isEmpty else {
            let messages = result.blockingErrors.map(\.message).joined(separator: "\n")
            statusLabel.stringValue = NSLocalizedString("Cannot apply: ", comment: "") + messages
            statusLabel.textColor = .systemRed
            return
        }

        isApplying = true
        applyButton.isEnabled = false
        statusLabel.stringValue = NSLocalizedString("Applying TUN configuration...", comment: "")
        statusLabel.textColor = .secondaryLabelColor

        let patch = buildTunPatch(from: input)
        patchControllerConfig(patch) { [weak self] success, message in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isApplying = false
                self.applyButton.isEnabled = true
                if success {
                    self.statusLabel.stringValue = NSLocalizedString("TUN config applied. Close this window — Core Settings will refresh.", comment: "")
                    self.statusLabel.textColor = .systemGreen
                    // Refresh in-memory config so the editor reflects applied state.
                    AppDelegate.shared.syncConfig {
                        self.refreshFromCurrentConfig()
                    }
                    // Tell the presenting Core Settings to refresh too.
                    if let presenter = self.presentingViewController as? CoreSettingViewController {
                        presenter.refreshConfigStatus()
                    }
                } else {
                    self.statusLabel.stringValue = message ?? NSLocalizedString("Failed to apply TUN config.", comment: "")
                    self.statusLabel.textColor = .systemRed
                }
            }
        }
    }

    @objc private func actionReset() {
        refreshFromCurrentConfig()
        validationLabel.stringValue = ""
        statusLabel.stringValue = NSLocalizedString("Reset to current controller config.", comment: "")
        statusLabel.textColor = .secondaryLabelColor
    }

    // MARK: - Controller integration

    private func buildTunPatch(from input: TunConfigValidationInput) -> [String: Any] {
        var tun: [String: Any] = ["enable": input.enable]
        if let device = input.device { tun["device"] = device }
        if let stack = input.stack { tun["stack"] = stack }
        if let dnsHijack = input.dnsHijack { tun["dns-hijack"] = dnsHijack }
        if let autoRoute = input.autoRoute { tun["auto-route"] = autoRoute }
        if let autoDetectInterface = input.autoDetectInterface { tun["auto-detect-interface"] = autoDetectInterface }
        if let strictRoute = input.strictRoute { tun["strict-route"] = strictRoute }
        if let mtu = input.mtu { tun["mtu"] = mtu }
        if let udpTimeout = input.udpTimeout { tun["udp-timeout"] = udpTimeout }
        if let routeAddress = input.routeAddress { tun["route-address"] = routeAddress }
        if let routeExcludeAddress = input.routeExcludeAddress { tun["route-exclude-address"] = routeExcludeAddress }
        if let includeInterface = input.includeInterface { tun["include-interface"] = includeInterface }
        if let excludeInterface = input.excludeInterface { tun["exclude-interface"] = excludeInterface }
        return ["tun": tun]
    }

    private func patchControllerConfig(_ patch: [String: Any], completion: @escaping (Bool, String?) -> Void) {
        if ApiRequest.useDirectApi() {
            // Embedded-core mode: write TUN YAML into the active config file
            // and reload via the Go bridge (clashUpdateConfig).
            applyTunConfigViaConfigFile(patch, completion: completion)
            return
        }

        // External-controller mode: PATCH /configs via HTTP.
        ConfigAPI.patchTunConfig(patch) { result in
            switch result {
            case .success:
                completion(true, nil)
            case let .unauthorized(message), let .failed(message):
                completion(false, message)
            case .unsupported:
                completion(false, NSLocalizedString("The active controller does not support /configs patching.", comment: ""))
            }
        }
    }

    /// Writes the TUN parameters into the active YAML config file and triggers a
    /// core reload through the Go bridge (clashUpdateConfig). Only used in
    /// embedded-core mode where there is no HTTP controller to PATCH.
    private func applyTunConfigViaConfigFile(_ patch: [String: Any], completion: @escaping (Bool, String?) -> Void) {
        let configName = ConfigManager.selectConfigName
        ConfigManager.getConfigPath(configName: configName) { [weak self] result in
            guard let self else { return }
            let configPath: String
            switch result {
            case let .success(path):
                configPath = path
            case let .failure(error):
                DispatchQueue.main.async {
                    completion(false, error.localizedDescription)
                }
                return
            }

            do {
                let originalYaml = try String(contentsOfFile: configPath, encoding: .utf8)
                let updatedYaml = self.upsertTunSection(in: originalYaml, tunParams: patch["tun"] as? [String: Any] ?? [:])
                try updatedYaml.write(toFile: configPath, atomically: true, encoding: .utf8)

                ApiRequest.requestConfigUpdate(configPath: configPath) { errorMessage in
                    DispatchQueue.main.async {
                        if let errorMessage {
                            // Restore the original YAML on failure.
                            try? originalYaml.write(toFile: configPath, atomically: true, encoding: .utf8)
                            completion(false, errorMessage)
                        } else {
                            completion(true, nil)
                        }
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    completion(false, String(format: NSLocalizedString("Failed to write TUN config: %@", comment: ""), error.localizedDescription))
                }
            }
        }
    }

    /// Inserts or updates the `tun:` block in a YAML string while preserving
    /// all other sections and comments.
    private func upsertTunSection(in yaml: String, tunParams: [String: Any]) -> String {
        let tunYaml = renderTunYAML(tunParams)
        var lines = yaml.components(separatedBy: "\n")
        var tunStart: Int?
        var tunEnd: Int?

        for (idx, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "tun:" || trimmed.hasPrefix("tun:") {
                tunStart = idx
                continue
            }
            if tunStart != nil, tunEnd == nil {
                // A top-level key (no leading whitespace, not a comment) ends the tun block.
                if !trimmed.isEmpty, !trimmed.hasPrefix("#"),
                   line.first?.isWhitespace == false {
                    tunEnd = idx
                    break
                }
            }
        }

        if let start = tunStart {
            let end = tunEnd ?? lines.count
            lines.replaceSubrange(start ..< end, with: [tunYaml])
        } else {
            // No tun section: append before the first blank-line block or at the end.
            if let lastNonBlank = lines.lastIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                let insertAt = min(lastNonBlank + 1, lines.count)
                if insertAt < lines.count, lines[insertAt].trimmingCharacters(in: .whitespaces).isEmpty {
                    lines.insert(tunYaml, at: insertAt)
                } else {
                    lines.append("")
                    lines.append(tunYaml)
                }
            } else {
                lines.append(tunYaml)
            }
        }

        return lines.joined(separator: "\n")
    }

    /// Renders a tun parameters dictionary to a YAML block string.
    private func renderTunYAML(_ params: [String: Any]) -> String {
        var result = "tun:"
        let keyOrder = ["enable", "device", "stack", "dns-hijack", "auto-route",
                        "auto-detect-interface", "strict-route", "mtu", "udp-timeout",
                        "route-address", "route-exclude-address",
                        "include-interface", "exclude-interface"]
        for key in keyOrder {
            guard let value = params[key] else { continue }
            switch value {
            case let b as Bool:
                result += "\n  \(key): \(b ? "true" : "false")"
            case let s as String:
                result += "\n  \(key): \"\(s)\""
            case let arr as [String]:
                if arr.isEmpty { continue }
                result += "\n  \(key):"
                for item in arr {
                    result += "\n    - \"\(item)\""
                }
            case let n as Int:
                result += "\n  \(key): \(n)"
            default:
                break
            }
        }
        return result
    }

    // MARK: - Layout helpers

    private func addFullWidthArrangedSubview(_ subview: NSView) {
        contentStack.addArrangedSubview(subview)
        subview.translatesAutoresizingMaskIntoConstraints = false
        subview.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
    }

    private func addFullWidthSection(title: String, rows: [NSView], note: String?) {
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

        if let note {
            let noteLabel = NSTextField(wrappingLabelWithString: note)
            noteLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
            noteLabel.textColor = .secondaryLabelColor
            noteLabel.maximumNumberOfLines = 3
            stack.addArrangedSubview(noteLabel)
            noteLabel.translatesAutoresizingMaskIntoConstraints = false
            noteLabel.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        addFullWidthArrangedSubview(stack)
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

    private func checkboxRow(checkbox: NSButton, label: String? = nil) -> NSView {
        if let label {
            let titled = NSButton(checkboxWithTitle: label, target: nil, action: nil)
            titled.state = checkbox.state
            titled.target = checkbox.target
            titled.action = checkbox.action
            // Use a wrapper row for consistent layout
            let row = NSView()
            row.addSubview(titled)
            titled.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                titled.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: rowTitleWidth + 8),
                titled.topAnchor.constraint(equalTo: row.topAnchor),
                titled.bottomAnchor.constraint(equalTo: row.bottomAnchor)
            ])
            return row
        }
        return checkbox
    }

    private func numberFormatter(min: Int, max: Int) -> NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle = .none
        f.minimum = NSNumber(value: min)
        f.maximum = NSNumber(value: max)
        return f
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
