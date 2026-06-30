//
//  DNSConfigEditorViewController.swift
//  ClashX
//
//  Created by SmartX on 2026/6/11.
//

import Cocoa

/// Structured editor for all macOS-relevant mihomo DNS configuration fields.
/// Provides live validation and apply/reset functionality.
///
/// ponytail: YAML upsert is string-based (same pattern as TunConfigEditor).
/// Ceiling and upgrade path are identical — switch to YAML parse-emit when
/// the config workspace pipeline lands.
final class DNSConfigEditorViewController: NSViewController {
    private final class FlippedView: NSView {
        override var isFlipped: Bool { true }
    }

    // MARK: - Controls

    private let enableCheckbox = NSButton(checkboxWithTitle: NSLocalizedString("Enable DNS", comment: ""), target: nil, action: nil)
    private let enhancedModePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let listenField = NSTextField(string: "")
    private let nameserverField = NSTextField(string: "")
    private let fallbackField = NSTextField(string: "")
    private let directNameserverField = NSTextField(string: "")
    private let respectRulesCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let useHostsCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let useSystemHostsCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let preferH3Checkbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let fakeIPRangeField = NSTextField(string: "")
    private let fakeIPFilterField = NSTextField(string: "")
    private let fakeIPFilterModePopup = NSPopUpButton(frame: .zero, pullsDown: false)

    private let validationLabel = NSTextField(wrappingLabelWithString: "")
    private let applyButton = NSButton(title: NSLocalizedString("Apply DNS Config", comment: ""), target: nil, action: nil)
    private let resetButton = NSButton(title: NSLocalizedString("Reset to Current", comment: ""), target: nil, action: nil)
    private let statusLabel = NSTextField(wrappingLabelWithString: "")

    private let scrollView = NSScrollView()
    private let documentView = FlippedView()
    private let contentStack = NSStackView()

    private var isApplying = false
    private let pagePadding: CGFloat = 24
    private let rowTitleWidth: CGFloat = 180

    // MARK: - Lifecycle

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 580, height: 520))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = NSLocalizedString("DNS Configuration", comment: "")
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

        enhancedModePopup.addItems(withTitles: ["redir-host", "fake-ip"])
        enhancedModePopup.insertItem(withTitle: NSLocalizedString("(default)", comment: ""), at: 0)
        enhancedModePopup.selectItem(at: 0)

        fakeIPFilterModePopup.addItems(withTitles: ["blacklist", "whitelist"])
        fakeIPFilterModePopup.insertItem(withTitle: NSLocalizedString("(default)", comment: ""), at: 0)
        fakeIPFilterModePopup.selectItem(at: 0)

        listenField.placeholderString = NSLocalizedString(":53 (default)", comment: "")
        nameserverField.placeholderString = NSLocalizedString("223.5.5.5, 119.29.29.29 (comma-separated)", comment: "")
        fallbackField.placeholderString = NSLocalizedString("8.8.8.8, 1.1.1.1 (comma-separated)", comment: "")
        directNameserverField.placeholderString = NSLocalizedString("Comma-separated list", comment: "")
        fakeIPRangeField.placeholderString = NSLocalizedString("198.18.0.1/16 (CIDR)", comment: "")
        fakeIPFilterField.placeholderString = NSLocalizedString("+.example.com, -*.org (comma-separated)", comment: "")

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
            labeledRow(title: NSLocalizedString("Enhanced Mode", comment: ""), view: enhancedModePopup),
            labeledRow(title: NSLocalizedString("Listen", comment: ""), view: listenField),
            labeledRow(title: NSLocalizedString("Nameserver", comment: ""), view: nameserverField),
            labeledRow(title: NSLocalizedString("Fallback", comment: ""), view: fallbackField),
            labeledRow(title: NSLocalizedString("Direct Nameserver", comment: ""), view: directNameserverField)
        ], note: NSLocalizedString("Nameservers and fallbacks are comma-separated. Direct nameserver is used for non-proxy DNS queries. Listen address defaults to :53.", comment: ""))

        addFullWidthSection(title: NSLocalizedString("Behavior", comment: ""), rows: [
            checkboxRow(checkbox: respectRulesCheckbox, label: NSLocalizedString("Respect Rules", comment: "")),
            checkboxRow(checkbox: useHostsCheckbox, label: NSLocalizedString("Use Hosts", comment: "")),
            checkboxRow(checkbox: useSystemHostsCheckbox, label: NSLocalizedString("Use System Hosts", comment: "")),
            checkboxRow(checkbox: preferH3Checkbox, label: NSLocalizedString("Prefer H3 ⚠", comment: ""))
        ], note: NSLocalizedString("Respect-rules with no resolver path is risky. Prefer-h3 with respect-rules may need extra testing. Fake-IP mode breaks software expecting real-IP DNS answers.", comment: ""))

        addFullWidthSection(title: NSLocalizedString("Fake-IP", comment: ""), rows: [
            labeledRow(title: NSLocalizedString("Fake-IP Range", comment: ""), view: fakeIPRangeField),
            labeledRow(title: NSLocalizedString("Fake-IP Filter", comment: ""), view: fakeIPFilterField),
            labeledRow(title: NSLocalizedString("Fake-IP Filter Mode", comment: ""), view: fakeIPFilterModePopup)
        ], note: NSLocalizedString("Fake-IP mode returns synthetic addresses for DNS queries and proxies the real connections. The filter controls which domains get fake-IP treatment (blacklist = filter out, whitelist = only filter in).", comment: ""))

        addFullWidthArrangedSubview(validationLabel)
        let buttonRow = NSStackView(views: [applyButton, resetButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 12
        addFullWidthArrangedSubview(buttonRow)
        addFullWidthArrangedSubview(statusLabel)
    }

    // MARK: - Data flow

    private func refreshFromCurrentConfig() {
        let dns = ConfigManager.shared.currentConfig?.dns

        if let dns {
            enableCheckbox.state = (dns.enable ?? true) ? .on : .off
            if let mode = dns.enhancedMode, let idx = enhancedModePopup.itemTitles.firstIndex(of: mode) {
                enhancedModePopup.selectItem(at: idx)
            } else {
                enhancedModePopup.selectItem(at: 0)
            }
            listenField.stringValue = dns.listen ?? ""
            nameserverField.stringValue = (dns.nameserver ?? []).joined(separator: ", ")
            fallbackField.stringValue = (dns.fallback ?? []).joined(separator: ", ")
            directNameserverField.stringValue = (dns.directNameserver ?? []).joined(separator: ", ")
            respectRulesCheckbox.state = (dns.respectRules ?? false) ? .on : .off
            useHostsCheckbox.state = (dns.useHosts ?? false) ? .on : .off
            useSystemHostsCheckbox.state = (dns.useSystemHosts ?? false) ? .on : .off
            preferH3Checkbox.state = (dns.preferH3 ?? false) ? .on : .off
            fakeIPRangeField.stringValue = dns.fakeIPRange ?? ""
            fakeIPFilterField.stringValue = (dns.fakeIPFilter ?? []).joined(separator: ", ")
            if let filterMode = dns.fakeIPFilterMode, let idx = fakeIPFilterModePopup.itemTitles.firstIndex(of: filterMode) {
                fakeIPFilterModePopup.selectItem(at: idx)
            } else {
                fakeIPFilterModePopup.selectItem(at: 0)
            }
            statusLabel.stringValue = NSLocalizedString("Loaded current DNS config from controller state.", comment: "")
        } else {
            // No existing DNS section: pre-fill sensible defaults.
            enableCheckbox.state = .on
            enhancedModePopup.selectItem(at: 0)
            listenField.stringValue = ""
            nameserverField.stringValue = "223.5.5.5, 119.29.29.29"
            fallbackField.stringValue = "8.8.8.8, 1.1.1.1"
            directNameserverField.stringValue = ""
            respectRulesCheckbox.state = .off
            useHostsCheckbox.state = .on
            useSystemHostsCheckbox.state = .off
            preferH3Checkbox.state = .off
            fakeIPRangeField.stringValue = ""
            fakeIPFilterField.stringValue = ""
            fakeIPFilterModePopup.selectItem(at: 0)
            statusLabel.stringValue = NSLocalizedString("No DNS section exists yet. Defaults are pre-filled — adjust and apply to create one.", comment: "")
        }

        validateLive()
    }

    private func validateLive() {
        let input = collectInput()
        let result = DNSConfigValidator.validate(input)
        if let issue = result.issues.first {
            switch issue.severity {
            case .blocking:
                validationLabel.stringValue = "🚫 \(issue.message)"
                validationLabel.textColor = .systemRed
            case .warning:
                validationLabel.stringValue = "⚠ \(issue.message)"
                validationLabel.textColor = .systemOrange
            case .info:
                validationLabel.stringValue = "ℹ \(issue.message)"
                validationLabel.textColor = .secondaryLabelColor
            }
        } else {
            validationLabel.stringValue = ""
        }
    }

    private func collectInput() -> DNSConfigValidationInput {
        let parseList: (NSTextField) -> [String]? = { field in
            let raw = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { return nil }
            return raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }

        let selectedMode = enhancedModePopup.indexOfSelectedItem > 0 ? enhancedModePopup.titleOfSelectedItem : nil
        let selectedFilterMode = fakeIPFilterModePopup.indexOfSelectedItem > 0 ? fakeIPFilterModePopup.titleOfSelectedItem : nil

        return DNSConfigValidationInput(
            enable: enableCheckbox.state == .on,
            enhancedMode: selectedMode,
            fakeIPRange: fakeIPRangeField.stringValue.trimmingCharacters(in: .whitespaces).nilIfEmpty,
            fakeIPFilter: parseList(fakeIPFilterField),
            fakeIPFilterMode: selectedFilterMode,
            nameserver: parseList(nameserverField),
            fallback: parseList(fallbackField),
            directNameserver: parseList(directNameserverField),
            respectRules: respectRulesCheckbox.state == .on,
            useHosts: useHostsCheckbox.state == .on,
            useSystemHosts: useSystemHostsCheckbox.state == .on,
            preferH3: preferH3Checkbox.state == .on,
            listen: listenField.stringValue.trimmingCharacters(in: .whitespaces).nilIfEmpty
        )
    }

    // MARK: - Actions

    @objc private func actionApply() {
        guard !isApplying else { return }
        let input = collectInput()
        let result = DNSConfigValidator.validate(input)
        guard !result.issues.contains(where: { $0.severity == .blocking }) else {
            let messages = result.issues.map(\.message).joined(separator: "\n")
            statusLabel.stringValue = NSLocalizedString("Cannot apply: ", comment: "") + messages
            statusLabel.textColor = .systemRed
            return
        }

        isApplying = true
        applyButton.isEnabled = false
        statusLabel.stringValue = NSLocalizedString("Applying DNS configuration...", comment: "")
        statusLabel.textColor = .secondaryLabelColor

        let patch = buildDNSPatch(from: input)
        if ApiRequest.useDirectApi() {
            applyDNSConfigViaConfigFile(patch, completion: { [weak self] success, message in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.isApplying = false
                    self.applyButton.isEnabled = true
                    if success {
                        self.statusLabel.stringValue = NSLocalizedString("DNS config applied. Close this window — Core Settings will refresh.", comment: "")
                        self.statusLabel.textColor = .systemGreen
                        AppDelegate.shared.syncConfig {
                            self.refreshFromCurrentConfig()
                        }
                        if let presenter = self.presentingViewController as? CoreSettingViewController {
                            presenter.refreshConfigStatus()
                        }
                    } else {
                        self.statusLabel.stringValue = message ?? NSLocalizedString("Failed to apply DNS config.", comment: "")
                        self.statusLabel.textColor = .systemRed
                    }
                }
            })
            return
        }

        ConfigAPI.patchConfig(parameters: ["dns": patch],
                              defaultMessage: NSLocalizedString("Failed to patch DNS configuration.", comment: "")) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isApplying = false
                self.applyButton.isEnabled = true
                switch result {
                case .success:
                    self.statusLabel.stringValue = NSLocalizedString("DNS config applied. Close this window — Core Settings will refresh.", comment: "")
                    self.statusLabel.textColor = .systemGreen
                    AppDelegate.shared.syncConfig {
                        self.refreshFromCurrentConfig()
                    }
                    if let presenter = self.presentingViewController as? CoreSettingViewController {
                        presenter.refreshConfigStatus()
                    }
                case .unsupported:
                    self.statusLabel.stringValue = NSLocalizedString("The active controller does not support /configs patching.", comment: "")
                    self.statusLabel.textColor = .systemRed
                case let .unauthorized(message), let .failed(message):
                    self.statusLabel.stringValue = message
                    self.statusLabel.textColor = .systemRed
                }
            }
        }
    }

    /// Writes the DNS parameters into the active YAML config file and triggers a
    /// core reload through the Go bridge. Only used in embedded-core mode.
    private func applyDNSConfigViaConfigFile(_ dnsParams: [String: Any], completion: @escaping (Bool, String?) -> Void) {
        let configName = ConfigManager.selectConfigName
        ConfigManager.getConfigPath(configName: configName) { result in
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
                let updatedYaml = self.upsertDNSSection(in: originalYaml, dnsParams: dnsParams)
                try updatedYaml.write(toFile: configPath, atomically: true, encoding: .utf8)

                ApiRequest.requestConfigUpdate(configPath: configPath) { errorMessage in
                    DispatchQueue.main.async {
                        if let errorMessage {
                            try? originalYaml.write(toFile: configPath, atomically: true, encoding: .utf8)
                            completion(false, errorMessage)
                        } else {
                            completion(true, nil)
                        }
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    completion(false, String(format: NSLocalizedString("Failed to write DNS config: %@", comment: ""), error.localizedDescription))
                }
            }
        }
    }

    /// Inserts or updates the `dns:` block in a YAML string. Delegates to ConfigYAMLEditor.
    private func upsertDNSSection(in yaml: String, dnsParams: [String: Any]) -> String {
        ConfigYAMLEditor.upsertSection(named: "dns", in: yaml, params: dnsParams, keyOrder: [
            "enable", "enhanced-mode", "listen", "nameserver", "fallback",
            "direct-nameserver", "respect-rules", "use-hosts",
            "use-system-hosts", "prefer-h3",
            "fake-ip-range", "fake-ip-filter", "fake-ip-filter-mode"
        ])
    }

    @objc private func actionReset() {
        refreshFromCurrentConfig()
        validationLabel.stringValue = ""
        statusLabel.stringValue = NSLocalizedString("Reset to current controller config.", comment: "")
        statusLabel.textColor = .secondaryLabelColor
    }

    // MARK: - Patch builder

    private func buildDNSPatch(from input: DNSConfigValidationInput) -> [String: Any] {
        var dns: [String: Any] = [:]
        dns["enable"] = input.enable
        if let mode = input.enhancedMode { dns["enhanced-mode"] = mode }
        if let listen = input.listen { dns["listen"] = listen }
        if let ns = input.nameserver { dns["nameserver"] = ns }
        if let fb = input.fallback { dns["fallback"] = fb }
        if let dn = input.directNameserver { dns["direct-nameserver"] = dn }
        if let rr = input.respectRules { dns["respect-rules"] = rr }
        if let uh = input.useHosts { dns["use-hosts"] = uh }
        if let ush = input.useSystemHosts { dns["use-system-hosts"] = ush }
        if let ph3 = input.preferH3 { dns["prefer-h3"] = ph3 }
        if let range = input.fakeIPRange { dns["fake-ip-range"] = range }
        if let filter = input.fakeIPFilter { dns["fake-ip-filter"] = filter }
        if let filterMode = input.fakeIPFilterMode { dns["fake-ip-filter-mode"] = filterMode }
        return dns
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
            noteLabel.maximumNumberOfLines = 4
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
        // ponytail: use the original checkbox directly so refreshFromCurrentConfig()
        // and collectInput() stay connected to the same control the user sees.
        if let label {
            checkbox.title = label
        }
        let row = NSView()
        row.addSubview(checkbox)
        checkbox.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            checkbox.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: rowTitleWidth + 8),
            checkbox.topAnchor.constraint(equalTo: row.topAnchor),
            checkbox.bottomAnchor.constraint(equalTo: row.bottomAnchor)
        ])
        return row
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
