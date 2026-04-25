//
//  SettingTabViewController.swift
//  ClashX Pro
//
//  Created by yicheng on 2022/11/20.
//  Copyright © 2022 west2online. All rights reserved.
//

import Cocoa

class SettingTabViewController: NSTabViewController, NibLoadable {
    override func viewDidLoad() {
        super.viewDidLoad()

        if !tabViewItems.contains(where: { $0.identifier as? String == "Core" }) {
            let item = NSTabViewItem(viewController: CoreSettingViewController())
            item.label = NSLocalizedString("Core", comment: "")
            item.identifier = "Core"
            if #available(macOS 11.0, *) {
                item.image = NSImage(systemSymbolName: "cpu", accessibilityDescription: item.label)
            }
            addTabViewItem(item)
        }

        tabStyle = .toolbar
        if #unavailable(macOS 10.11) {
            tabStyle = .segmentedControlOnTop
            tabViewItems.forEach { item in
                item.image = nil
            }
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}
