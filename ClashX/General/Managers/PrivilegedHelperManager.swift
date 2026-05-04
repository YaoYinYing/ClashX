//
//  PrivilegedHelperManager.swift
//  ClashX
//
//  Created by yicheng on 2020/4/21.
//  Copyright © 2020 west2online. All rights reserved.
//

import AppKit
import RxCocoa
import RxSwift
import ServiceManagement

class PrivilegedHelperManager {
    let isHelperCheckFinished = BehaviorRelay<Bool>(value: false)
    private var cancelInstallCheck = false
    private var useLegacyInstall = false

    private var authRef: AuthorizationRef?
    private var connection: NSXPCConnection?
    private var _helper: ProxyConfigRemoteProcessProtocol?
    private let helperRequirementInfoKey = "AllowedClientCodeSigningRequirement"
    #if PRO_VERSION
        static let machServiceName = "com.west2online.ClashXPro.ProxyConfigHelper"
    #else
        static let machServiceName = "com.west2online.ClashX.ProxyConfigHelper"
    #endif
    static let shared = PrivilegedHelperManager()
    init() {
        initAuthorizationRef()
    }

    // MARK: - Public

    func checkInstall() {
        Logger.log("checkInstall", level: .debug)
        getHelperStatus { [weak self] status in
            Logger.log("check result: \(status)", level: .debug)
            guard let self = self else { return }
            switch status {
            case .noFound:
                if #available(macOS 13, *) {
                    let url = URL(string: "/Library/LaunchDaemons/\(PrivilegedHelperManager.machServiceName).plist")!
                    let status = SMAppService.statusForLegacyPlist(at: url)
                    if status == .requiresApproval {
                        let alert = NSAlert()
                        let notice = NSLocalizedString("SmartX uses a daemon helper to configure the system proxy. Enable SmartX in Login Items under Allow in the Background, then relaunch the app.", comment: "")
                        let addition = NSLocalizedString("If you cannot find SmartX in Settings, try resetting the daemon.", comment: "")
                        alert.messageText = notice + "\n" + addition
                        alert.addButton(withTitle: NSLocalizedString("Open System Login Item Setting", comment: ""))
                        alert.addButton(withTitle: NSLocalizedString("Reset Daemon", comment: ""))
                        if alert.runModal() == .alertFirstButtonReturn {
                            SMAppService.openSystemSettingsLoginItems()
                        } else {
                            self.removeInstallHelper()
                        }
                    }
                }
                fallthrough
            case .needUpdate:
                Logger.log("need to install helper", level: .debug)
                if Thread.isMainThread {
                    self.notifyInstall()
                } else {
                    DispatchQueue.main.async {
                        self.notifyInstall()
                    }
                }
            case .installed:
                self.isHelperCheckFinished.accept(true)
            }
        }
    }

    func resetConnection() {
        connection?.invalidate()
        connection = nil
        _helper = nil
    }

    private func initAuthorizationRef() {
        // Create an empty AuthorizationRef
        let status = AuthorizationCreate(nil, nil, AuthorizationFlags(), &authRef)
        if status != OSStatus(errAuthorizationSuccess) {
            Logger.log("initAuthorizationRef AuthorizationCreate failed", level: .error)
            return
        }
    }

    /// Install new helper daemon
    private func installHelperDaemon() -> DaemonInstallResult {
        Logger.log("installHelperDaemon", level: .info)

        defer {
            resetConnection()
        }

        // Create authorization reference for the user
        var authRef: AuthorizationRef?
        var authStatus = AuthorizationCreate(nil, nil, [], &authRef)

        // Check if the reference is valid
        guard authStatus == errAuthorizationSuccess else {
            Logger.log("Authorization failed: \(authStatus)", level: .error)
            return .authorizationFail
        }

        // Ask user for the admin privileges to install the
        var authItem = AuthorizationItem(name: (kSMRightBlessPrivilegedHelper as NSString).utf8String!, valueLength: 0, value: nil, flags: 0)
        var authRights = withUnsafeMutablePointer(to: &authItem) { pointer in
            AuthorizationRights(count: 1, items: pointer)
        }
        let flags: AuthorizationFlags = [[], .interactionAllowed, .extendRights, .preAuthorize]
        authStatus = AuthorizationCreate(&authRights, nil, flags, &authRef)
        defer {
            if let ref = authRef {
                AuthorizationFree(ref, [])
            }
        }
        // Check if the authorization went succesfully
        guard authStatus == errAuthorizationSuccess else {
            Logger.log("Couldn't obtain admin privileges: \(authStatus)", level: .error)
            return .getAdminFail
        }

        // Launch the privileged helper using SMJobBless tool
        var error: Unmanaged<CFError>?
        if SMJobBless(kSMDomainSystemLaunchd, PrivilegedHelperManager.machServiceName as CFString, authRef, &error) == false {
            let nsError = (error?.takeRetainedValue() as Error?) as NSError?
            Logger.log("SMJobBless failed for \(PrivilegedHelperManager.machServiceName): domain=\(nsError?.domain ?? "unknown") code=\(nsError?.code ?? -1) userInfo=\(nsError?.userInfo ?? [:])", level: .error)
            #if DEBUG
                Logger.log("Debug helper trust override only affects XPC after installation. Unsigned or ad-hoc local Debug builds may still fail SMJobBless because SMAuthorizedClients and SMPrivilegedExecutables still use legacy identity metadata; falling back to the legacy install path is expected until SmartX signing migration is done.", level: .warning)
            #endif
            return .blessError(nsError?.code ?? -1)
        }

        Logger.log("\(PrivilegedHelperManager.machServiceName) installed successfully", level: .info)
        return .success
    }

    func helper(failture: (() -> Void)? = nil) -> ProxyConfigRemoteProcessProtocol? {
        Logger.log("opening privileged XPC connection to \(PrivilegedHelperManager.machServiceName)", level: .debug)
        connection = NSXPCConnection(machServiceName: PrivilegedHelperManager.machServiceName, options: NSXPCConnection.Options.privileged)
        connection?.remoteObjectInterface = NSXPCInterface(with: ProxyConfigRemoteProcessProtocol.self)
        connection?.invalidationHandler = {
            Logger.log("privileged helper XPC connection invalidated", level: .warning)
        }
        connection?.interruptionHandler = {
            Logger.log("privileged helper XPC connection interrupted", level: .warning)
        }
        connection?.resume()
        guard let helper = connection?.remoteObjectProxyWithErrorHandler({ error in
            Logger.log("privileged helper remote proxy error: \(error)", level: .error)
            failture?()
        }) as? ProxyConfigRemoteProcessProtocol else {
            Logger.log("failed to create privileged helper remote proxy", level: .error)
            return nil
        }
        return helper
    }

    var timer: Timer?

    enum HelperStatus {
        case installed
        case noFound
        case needUpdate
    }

    private func getHelperStatus(callback: @escaping ((HelperStatus) -> Void)) {
        var called = false
        let reply: ((HelperStatus) -> Void) = {
            status in
            if called { return }
            called = true
            callback(status)
        }

        let helperURL = Bundle.main.bundleURL.appendingPathComponent("Contents/Library/LaunchServices/" + PrivilegedHelperManager.machServiceName)
        guard
            let helperBundleInfo = CFBundleCopyInfoDictionaryForURL(helperURL as CFURL) as? [String: Any],
            let helperVersion = helperBundleInfo["CFBundleShortVersionString"] as? String else {
            Logger.log("helper metadata missing from bundled helper at \(helperURL.path)", level: .error)
            reply(.noFound)
            return
        }
        if let requirement = helperBundleInfo[helperRequirementInfoKey] as? String {
            let trimmedRequirement = requirement.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedRequirement.isEmpty {
                #if DEBUG
                    Logger.log("bundled helper uses empty \(helperRequirementInfoKey) in Debug; helper trust falls back to the Debug-only bypass", level: .warning)
                #else
                    Logger.log("bundled helper has empty \(helperRequirementInfoKey) outside Debug; Release installation should fail closed", level: .error)
                #endif
            }
        } else {
            Logger.log("bundled helper metadata is missing \(helperRequirementInfoKey)", level: .error)
        }
        let helperFileExists = FileManager.default.fileExists(atPath: "/Library/PrivilegedHelperTools/\(PrivilegedHelperManager.machServiceName)")
        if !helperFileExists {
            Logger.log("installed helper missing at /Library/PrivilegedHelperTools/\(PrivilegedHelperManager.machServiceName)", level: .warning)
            reply(.noFound)
            return
        }
        let timeout: TimeInterval = helperFileExists ? 15 : 5
        let time = Date()

        timer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { _ in
            Logger.log("timed out waiting \(timeout)s for helper version check on \(PrivilegedHelperManager.machServiceName)", level: .warning)
            reply(.noFound)
        }

        helper()?.getVersion { [weak timer] installedHelperVersion in
            timer?.invalidate()
            timer = nil
            Logger.log("helper version \(installedHelperVersion ?? "") require version \(helperVersion)", level: .debug)
            let versionMatch = installedHelperVersion == helperVersion
            if !versionMatch {
                Logger.log("helper version mismatch: installed=\(installedHelperVersion ?? "nil") bundled=\(helperVersion)", level: .warning)
            }
            let interval = Date().timeIntervalSince(time)
            Logger.log("check helper using time: \(interval)")
            reply(versionMatch ? .installed : .needUpdate)
        }
    }
}

extension PrivilegedHelperManager {
    private func notifyInstall() {
        guard showInstallHelperAlert() else { exit(0) }

        if cancelInstallCheck {
            return
        }

        if useLegacyInstall {
            useLegacyInstall = false
            Logger.log("falling back to legacy helper install path for \(PrivilegedHelperManager.machServiceName)", level: .warning)
            legacyInstallHelper()
            if !cancelInstallCheck {
                checkInstall()
            }
            return
        }

        let result = installHelperDaemon()
        if case .success = result {
            return
        }
        result.alertAction()
        useLegacyInstall = result.shouldRetryLegacyWay()
        NSAlert.alert(with: result.alertContent)
        if !cancelInstallCheck {
            checkInstall()
        }
    }

    private func showInstallHelperAlert() -> Bool {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("SmartX needs to install or update a helper tool with administrator privileges, otherwise SmartX cannot configure the system proxy.", comment: "")
        alert.alertStyle = .warning
        if useLegacyInstall {
            alert.addButton(withTitle: NSLocalizedString("Legacy Install", comment: ""))
        } else {
            alert.addButton(withTitle: NSLocalizedString("Install", comment: ""))
        }
        alert.addButton(withTitle: NSLocalizedString("Quit", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return true
        case .alertThirdButtonReturn:
            cancelInstallCheck = true
            isHelperCheckFinished.accept(true)
            Logger.log("cancelInstallCheck = true", level: .error)
            return true
        default:
            return false
        }
    }
}

private enum AppAuthorizationRights {
    static let rightName: NSString = "\(PrivilegedHelperManager.machServiceName).config" as NSString
    static let rightDefaultRule: Dictionary = adminRightsRule
    static let rightDescription: CFString = "ProxyConfigHelper wants to configure your proxy setting'" as CFString
    static var adminRightsRule: [String: Any] = ["class": "user",
                                                 "group": "admin",
                                                 "timeout": 0,
                                                 "version": 1]
}

private enum DaemonInstallResult {
    case success
    case authorizationFail
    case getAdminFail
    case blessError(Int)

    var alertContent: String {
        switch self {
        case .success:
            return ""
        case .authorizationFail: return "Failed to create authorization!"
        case .getAdminFail: return "Failed to get admin authorization!"
        case let .blessError(code):
            switch code {
            case kSMErrorInternalFailure: return "blessError: kSMErrorInternalFailure"
            case kSMErrorInvalidSignature: return "blessError: kSMErrorInvalidSignature"
            case kSMErrorAuthorizationFailure: return "blessError: kSMErrorAuthorizationFailure"
            case kSMErrorToolNotValid: return "blessError: kSMErrorToolNotValid"
            case kSMErrorJobNotFound: return "blessError: kSMErrorJobNotFound"
            case kSMErrorServiceUnavailable: return "blessError: kSMErrorServiceUnavailable"
            case kSMErrorJobMustBeEnabled: return "SmartX Helper is disabled by another process. Run \"sudo launchctl enable system/\(PrivilegedHelperManager.machServiceName)\" in Terminal. The command has been copied to your pasteboard."
            case kSMErrorInvalidPlist: return "blessError: kSMErrorInvalidPlist"
            default:
                return "bless unknown error:\(code)"
            }
        }
    }

    func shouldRetryLegacyWay() -> Bool {
        switch self {
        case .success: return false
        case let .blessError(code):
            switch code {
            case kSMErrorJobMustBeEnabled:
                return false
            default:
                return true
            }
        default:
            return true
        }
    }

    func alertAction() {
        switch self {
        case let .blessError(code):
            switch code {
            case kSMErrorJobMustBeEnabled:
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("sudo launchctl enable system/\(PrivilegedHelperManager.machServiceName)", forType: .string)
            default:
                break
            }
        default:
            break
        }
    }
}
