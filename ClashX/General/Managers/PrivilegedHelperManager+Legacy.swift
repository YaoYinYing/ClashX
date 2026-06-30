//
//  PrivilegedHelperManager+Legacy.swift
//  ClashX
//
//  Created by yicheng 2020/4/22.
//  Copyright © 2020 west2online. All rights reserved.
//
//  SECURITY: This file contains a legacy AppleScript shell-based helper
//  install/remove path that executes shell scripts with administrator
//  privileges. It is intentionally blocked at compile time outside of
//  DEBUG builds and is also blocked at runtime by the audited install
//  path's guardrail checks.
//
//  This path MUST NOT grow, MUST NOT be used for future TUN/helper work,
//  and MUST be removed entirely once signing identity migration is
//  complete and SMJobBless works reliably for SmartX Debug builds.
//

import Cocoa

extension PrivilegedHelperManager {
    /// Returns true only if the legacy shell-based install path is allowed
    /// in this build configuration. This is a hard compile-time guard:
    /// Release builds can never call this path.
    private static var legacyInstallAllowed: Bool {
        #if DEBUG
            // Even in Debug, this is a last-resort path for local development
            // only. The audited install flow already fails-closed and blocks
            // the legacy fallback. If you are reading this, you should be
            // working toward SMJobBless identity migration, not re-enabling
            // shell-based helper installation.
            return true
        #else
            return false
        #endif
    }

    func getInstallScript() -> String {
        let appPath = Bundle.main.bundlePath
        let bash = """
        #!/bin/bash
        set -e

        plistPath=/Library/LaunchDaemons/\(PrivilegedHelperManager.machServiceName).plist
        rm -rf /Library/PrivilegedHelperTools/\(PrivilegedHelperManager.machServiceName)
        if [ -e ${plistPath} ]; then
        launchctl unload -w ${plistPath}
        rm ${plistPath}
        fi
        launchctl remove \(PrivilegedHelperManager.machServiceName) || true

        mkdir -p /Library/PrivilegedHelperTools/
        rm -f /Library/PrivilegedHelperTools/\(PrivilegedHelperManager.machServiceName)

        cp "\(appPath)/Contents/Library/LaunchServices/\(PrivilegedHelperManager.machServiceName)" "/Library/PrivilegedHelperTools/\(PrivilegedHelperManager.machServiceName)"

        echo '
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        <key>Label</key>
        <string>\(PrivilegedHelperManager.machServiceName)</string>
        <key>MachServices</key>
        <dict>
        <key>\(PrivilegedHelperManager.machServiceName)</key>
        <true/>
        </dict>
        <key>Program</key>
        <string>/Library/PrivilegedHelperTools/\(PrivilegedHelperManager.machServiceName)</string>
        <key>ProgramArguments</key>
        <array>
        <string>/Library/PrivilegedHelperTools/\(PrivilegedHelperManager.machServiceName)</string>
        </array>
        </dict>
        </plist>
        ' > ${plistPath}

        launchctl load -w ${plistPath}
        """
        return bash
    }

    func runScriptWithRootPermission(script: String) {
        guard Self.legacyInstallAllowed else {
            Logger.log("legacy shell-based install blocked at compile time (not DEBUG)", level: .error)
            return
        }
        let tmpPath = FileManager.default.temporaryDirectory.appendingPathComponent(NSUUID().uuidString).appendingPathExtension("sh")
        do {
            try script.write(to: tmpPath, atomically: true, encoding: .utf8)
            let appleScriptStr = "do shell script \"bash \(tmpPath.path) \" with administrator privileges"
            let appleScript = NSAppleScript(source: appleScriptStr)
            var dict: NSDictionary?
            if appleScript?.executeAndReturnError(&dict) == nil {
                Logger.log("apple script failed")
            } else {
                Logger.log("apple script result: \(String(describing: dict))")
            }
        } catch let err {
            Logger.log("legacyInstallHelper create script fail: \(err)")
        }
        try? FileManager.default.removeItem(at: tmpPath)
    }

    func legacyInstallHelper() {
        guard Self.legacyInstallAllowed else {
            Logger.log("legacyInstallHelper blocked at compile time (not DEBUG)", level: .error)
            return
        }
        defer {
            resetConnection()
            Thread.sleep(forTimeInterval: 1)
        }
        let script = getInstallScript()
        runScriptWithRootPermission(script: script)
    }

    func removeInstallHelper() {
        guard Self.legacyInstallAllowed else {
            Logger.log("removeInstallHelper blocked at compile time (not DEBUG)", level: .error)
            return
        }
        defer {
            resetConnection()
            Thread.sleep(forTimeInterval: 5)
        }
        let script = """
        /bin/launchctl remove \(PrivilegedHelperManager.machServiceName) || true
        /usr/bin/killall -u root -9 \(PrivilegedHelperManager.machServiceName)
        /bin/rm -rf /Library/LaunchDaemons/\(PrivilegedHelperManager.machServiceName).plist
        /bin/rm -rf /Library/PrivilegedHelperTools/\(PrivilegedHelperManager.machServiceName)
        """

        runScriptWithRootPermission(script: script)
    }
}
