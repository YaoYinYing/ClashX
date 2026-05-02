//
//  ProxyModeChangeCommand.swift
//  ClashX
//
//  Created by Vince-hz on 2022/1/25.
//  Copyright © 2022 west2online. All rights reserved.
//

import AppKit
import Foundation

@objc class ProxyModeChangeCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard let directParameter = directParameter as? String,
              let mode = ClashProxyMode(rawValue: directParameter)
        else {
            scriptErrorNumber = -1
            scriptErrorString = "please enter a valid parameter. rule, global, direct or script"
            return nil
        }
        guard let delegate = NSApplication.shared.delegate as? AppDelegate else {
            scriptErrorNumber = -2
            scriptErrorString = "can't get application, try again later"
            return nil
        }
        delegate.switchProxyMode(mode: mode)
        return nil
    }
}
