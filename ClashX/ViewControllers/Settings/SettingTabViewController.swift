//
//  SettingTabViewController.swift
//  ClashX Pro
//
//  Created by yicheng on 2022/11/20.
//  Copyright © 2022 west2online. All rights reserved.
//

import Cocoa

class SettingTabViewController: NSTabViewController, NibLoadable {
    private lazy var coreViewController = CoreSettingViewController()

    override func viewDidLoad() {
        super.viewDidLoad()
        Logger.log("[Settings Tabs] viewDidLoad", level: .debug)
        ensureCoreTabInstalled()
        Logger.log("[Settings Tabs] tab items: \(tabViewItems.compactMap { $0.identifier as? String })", level: .debug)
        tabStyle = .toolbar
        if #unavailable(macOS 10.11) {
            tabStyle = .segmentedControlOnTop
            tabViewItems.forEach { item in
                item.image = nil
            }
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func ensureCoreTabInstalled() {
        guard !tabViewItems.contains(where: { $0.identifier as? String == "Core" }) else { return }
        Logger.log("[Settings Tabs] ensureCoreTabInstalled", level: .debug)
        if !coreViewController.isViewLoaded {
            _ = coreViewController.view
        }

        let item = NSTabViewItem(viewController: coreViewController)
        item.label = NSLocalizedString("Core", comment: "")
        item.identifier = "Core"
        item.view = coreViewController.view
        if #available(macOS 11.0, *) {
            item.image = NSImage(systemSymbolName: "cpu", accessibilityDescription: item.label)
        }
        addTabViewItem(item)
    }
}
