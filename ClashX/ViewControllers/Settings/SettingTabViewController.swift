//
//  SettingTabViewController.swift
//  ClashX Pro
//
//  Created by yicheng on 2022/11/20.
//  Copyright © 2022 west2online. All rights reserved.
//

import Cocoa

class SettingTabViewController: NSTabViewController, NibLoadable {
    private let coreViewController: CoreSettingViewController = {
        let viewController = CoreSettingViewController()
        _ = viewController.view
        return viewController
    }()

    private lazy var coreTabViewItem: NSTabViewItem = {
        let item = NSTabViewItem(viewController: coreViewController)
        item.label = NSLocalizedString("Core", comment: "")
        item.identifier = "Core"
        if #available(macOS 11.0, *) {
            item.image = NSImage(systemSymbolName: "cpu", accessibilityDescription: item.label)
        }
        return item
    }()

    override func awakeFromNib() {
        super.awakeFromNib()
        ensureCoreTabInstalled()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        ensureCoreTabInstalled()
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
        addTabViewItem(coreTabViewItem)
    }
}
