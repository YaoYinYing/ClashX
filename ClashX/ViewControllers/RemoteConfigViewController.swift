//
//  RemoteConfigViewController.swift
//  ClashX
//
//  Created by yicheng on 2019/7/28.
//  Copyright © 2019 west2online. All rights reserved.
//

import Cocoa
import RxSwift

class RemoteConfigViewController: NSViewController {
    @IBOutlet var tableView: NSTableView!
    @IBOutlet var deleteButton: NSButton!
    @IBOutlet var updateButton: NSButton!

    private var latestAddedConfig: RemoteConfigModel?

    let disposeBag = DisposeBag()

    deinit {
        print("RemoteConfigViewController deinit")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        updateButtonStatus()
        tableView.doubleAction = #selector(tableViewDidDoubleClick(tableView:))

        NotificationCenter.default
            .rx.notification(Notification.Name("didGetUrl")).bind {
                [weak self] note in
                guard let self = self else { return }
                guard let url = note.userInfo?["url"] as? String else { return }

                let name = note.userInfo?["name"] as? String
                self.showAdd(defaultUrl: url, name: name, allowAlt: true)
            }.disposed(by: disposeBag)
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        view.window?.level = .floating
        NSApp.activate(ignoringOtherApps: true)
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        RemoteConfigManager.shared.saveConfigs()
    }

    // MARK: Actions

    @IBAction func actionAdd(_ sender: Any) {
        showAdd()
    }

    @IBAction func actionDelete(_ sender: Any) {
        RemoteConfigManager.shared.configs.safeRemove(at: tableView.selectedRow)
        tableView.reloadData()
        updateButtonStatus()
    }

    @IBAction func actionUpdate(_ sender: Any) {
        guard let model = RemoteConfigManager.shared.configs[safe: tableView.selectedRow] else { return }
        requestUpdate(config: model)
        tableView.reloadDataKeepingSelection()
    }
}

extension RemoteConfigViewController {
    func updateButtonStatus() {
        let selectIdx = tableView.selectedRow
        if selectIdx == -1 {
            deleteButton.isEnabled = false
            updateButton.isEnabled = false
            return
        }

        guard let config = RemoteConfigManager.shared.configs[safe: selectIdx] else { return }
        deleteButton.isEnabled = true
        updateButton.isEnabled = !config.updating
    }

    func showAdd(defaultUrl: String? = nil,
                 defaultName: String? = nil,
                 name: String? = nil,
                 allowAlt: Bool = false) {
        let alertView = NSAlert()
        alertView.addButton(withTitle: NSLocalizedString("OK", comment: ""))
        alertView.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        alertView.messageText = NSLocalizedString("Add a remote config", comment: "")
        let remoteConfigInputView = RemoteConfigAddView.createFromNib()
        if let defaultUrl = defaultUrl {
            remoteConfigInputView.setUrl(string: defaultUrl, name: name, defaultName: defaultName)
        }
        alertView.accessoryView = remoteConfigInputView
        let response = alertView.runModal()

        guard response == .alertFirstButtonReturn else { return }
        guard remoteConfigInputView.isVaild() else {
            let alert = NSAlert()
            alert.messageText = remoteConfigInputView.validationError() ?? NSLocalizedString("Invalid input", comment: "")
            alert.alertStyle = .warning
            alert.runModal()
            return
        }

        let configNameRaw = remoteConfigInputView.getConfigName().0
        let configName: String
        do {
            configName = try SafeConfigName(configNameRaw).value
        } catch {
            NSAlert.alert(with: error.localizedDescription)
            return
        }
        let isPlaceHolderName = remoteConfigInputView.getConfigName().1
        let configUrl = remoteConfigInputView.getUrlString()

        if let existed = RemoteConfigManager.shared.configs.first(where: { $0.name == configName }) {
            guard allowAlt else {
                NSAlert.alert(with: NSLocalizedString("The remote config name is duplicated", comment: ""))
                return
            }
            existed.url = configUrl
            latestAddedConfig = existed
            requestUpdate(config: existed)
        } else {
            let remoteConfig = RemoteConfigModel(url: configUrl,
                                                 name: configName,
                                                 updateTime: nil)
            remoteConfig.isPlaceHolderName = !isPlaceHolderName
            RemoteConfigManager.shared.configs.append(remoteConfig)
            requestUpdate(config: remoteConfig)
            latestAddedConfig = remoteConfig
        }

        tableView.reloadData()
        updateButtonStatus()
    }

    func requestUpdate(config: RemoteConfigModel) {
        guard !config.updating else { return }
        config.updating = true
        RemoteConfigManager.updateConfig(config: config) {
            [weak self, weak config] errorString in
            guard let self = self, let config = config else { return }
            config.updating = false
            if let errorString = errorString {
                RemoteConfigManager.shared.saveConfigs()
                let alert = NSAlert()
                alert.messageText = errorString
                alert.alertStyle = .warning
                alert.runModal()
            } else {
                config.updateTime = Date()
                RemoteConfigManager.shared.saveConfigs()

                if config == self.latestAddedConfig {
                    AppDelegate.shared.updateConfig(configName: config.name)
                } else if config.name == ConfigManager.selectConfigName {
                    AppDelegate.shared.updateConfig()
                }
            }
            self.tableView.reloadDataKeepingSelection()
        }
    }
}

extension RemoteConfigViewController: NSTableViewDelegate {
    func tableViewSelectionDidChange(_ notification: Notification) {
        updateButtonStatus()
    }

    @objc func tableViewDidDoubleClick(tableView: NSTableView) {
        let row = tableView.clickedRow
        guard let config = RemoteConfigManager.shared.configs[safe: row] else { return }
        if config.isPlaceHolderName {
            showAdd(defaultUrl: config.url, defaultName: config.name, name: nil, allowAlt: true)
        } else {
            showAdd(defaultUrl: config.url, defaultName: nil, name: config.name, allowAlt: true)
        }
    }
}

extension RemoteConfigViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return RemoteConfigManager.shared.configs.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let config = RemoteConfigManager.shared.configs[safe: row] else { return nil }
        let safeName = try? SafeConfigName(config.name)
        let cacheURL = safeName.flatMap { try? Paths.localConfigURL(for: $0) }
        let cacheStatus = cacheURL.map {
            FileManager.default.fileExists(atPath: $0.path) ? NSLocalizedString("present", comment: "") : NSLocalizedString("missing", comment: "")
        } ?? NSLocalizedString("unavailable", comment: "")
        let tooltip = [
            "\(NSLocalizedString("Profile Type", comment: "")): Remote",
            "\(NSLocalizedString("Profile Name", comment: "")): \(config.name)",
            "\(NSLocalizedString("Source", comment: "")): \(config.url)",
            "\(NSLocalizedString("Cache File", comment: "")): \(cacheURL?.path ?? NSLocalizedString("Unavailable", comment: ""))",
            "\(NSLocalizedString("Cache Status", comment: "")): \(cacheStatus)",
            "\(NSLocalizedString("Last Update", comment: "")): \(config.displayingTimeString())",
            "\(NSLocalizedString("Validation", comment: "")): \(config.validationSummary())",
            "\(NSLocalizedString("Last Fetch", comment: "")): \(config.updateResultSummary())"
        ].joined(separator: "\n")

        func setupCell(withIdentifier: String, string: String, textFieldtag: Int = 1) -> NSView? {
            let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: withIdentifier), owner: nil)
            if let textField = cell?.viewWithTag(1) as? NSTextField {
                textField.stringValue = string
            } else {
                assertionFailure()
            }
            cell?.toolTip = tooltip

            return cell
        }

        switch tableColumn?.identifier.rawValue ?? "" {
        case "url":
            return setupCell(withIdentifier: "urlCell", string: config.url)
        case "configName":
            return setupCell(withIdentifier: "nameCell", string: config.name)
        case "updateTime":
            return setupCell(withIdentifier: "timeCell", string: config.displayingTimeString())

        default: assertionFailure()
        }
        return nil
    }
}

class RemoteConfigAddView: NSView, NibLoadable {
    @IBOutlet private var urlTextField: NSTextField!
    @IBOutlet private var configNameTextField: NSTextField!

    func getUrlString() -> String {
        return urlTextField.stringValue
    }

    /// Get the config name
    /// - Returns: return (name, isUserInput)
    func getConfigName() -> (String, Bool) {
        if !configNameTextField.stringValue.isEmpty {
            return (configNameTextField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), true)
        }
        return ((configNameTextField.placeholderString ?? "").trimmingCharacters(in: .whitespacesAndNewlines), false)
    }

    func validationError() -> String? {
        guard urlTextField.stringValue.isUrlVaild() else {
            return NSLocalizedString("Invalid input", comment: "")
        }
        do {
            _ = try SafeConfigName(getConfigName().0)
        } catch {
            return error.localizedDescription
        }
        return nil
    }

    func isVaild() -> Bool {
        return validationError() == nil
    }

    func setUrl(string: String, name: String? = nil, defaultName: String?) {
        urlTextField.stringValue = string

        if let name = name, !name.isEmpty {
            configNameTextField.stringValue = name
        }

        if let defaultName = defaultName, !defaultName.isEmpty {
            configNameTextField.placeholderString = defaultName.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if name == nil && defaultName == nil {
            updateConfigName()
        }
    }

    private func updateConfigName() {
        guard urlTextField.stringValue.isUrlVaild() else { return }
        let urlString = urlTextField.stringValue
        let host = URL(string: urlString)?.host ?? "unknown"
        configNameTextField.placeholderString = (try? SafeConfigName(host).value)
            ?? RemoteConfigManager.deterministicFallbackName(sourceURL: urlString)
    }
}

extension RemoteConfigAddView: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        updateConfigName()
    }
}
