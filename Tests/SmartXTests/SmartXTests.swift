//
//  SmartXTests.swift
//  SmartXTests
//
//  XCTest cases for pure-logic production code. Migrated from smoke harnesses.
//
//  ponytail: covers files that compile without CocoaPods. TestStubs.swift
//  provides stubs for ConfigManager and ClashConfig (needed by production
//  files that reference Alamofire/SwiftyJSON-dependent types).
//  Ceiling: no AppKit or network-dependent code. Upgrade path: add SPM
//  modularization to remove stub dependency.

import XCTest

// MARK: - ControllerEndpointBuilder

final class ControllerEndpointBuilderTests: XCTestCase {
    func test_httpPath_returnsURL() throws {
        ConfigManager.shared.isRunning = true
        ConfigManager.shared.overrideApiURL = nil
        ConfigManager.shared.apiPort = "9090"
        let url = try ControllerEndpointBuilder.httpURL(path: "/configs")
        XCTAssertEqual(url.absoluteString, "http://127.0.0.1:9090/configs")
    }

    func test_websocketPath_convertsScheme() throws {
        ConfigManager.shared.overrideApiURL = URL(string: "https://example.com:9443")
        let url = try ControllerEndpointBuilder.websocketURL(path: "/logs")
        XCTAssertEqual(url.absoluteString, "wss://example.com:9443/logs")
    }

    func test_pathComponents_singleEncode() throws {
        ConfigManager.shared.overrideApiURL = URL(string: "https://example.com:9443/base")
        let url = try ControllerEndpointBuilder.httpURL(pathComponents: ["proxies", "Proxy A"])
        XCTAssertEqual(url.absoluteString, "https://example.com:9443/base/proxies/Proxy%20A")
        XCTAssertFalse(url.absoluteString.contains("%2520"),
                       "Dynamic path components must not be double-encoded")
    }

    func test_pathComponents_slashStaysEncoded() throws {
        ConfigManager.shared.overrideApiURL = URL(string: "https://example.com:9443/base")
        let url = try ControllerEndpointBuilder.httpURL(pathComponents: ["providers", "proxies", "Group/A"])
        XCTAssertEqual(url.absoluteString, "https://example.com:9443/base/providers/proxies/Group%2FA",
                       "Slash inside a raw component must stay in one path segment")
    }
}

// MARK: - Config validators

final class ConfigValidatorTests: XCTestCase {
    func test_tunValidator_validInput_passes() {
        let input = TunConfigValidationInput(
            enable: true, device: nil, stack: "gvisor", dnsHijack: nil,
            autoRoute: true, autoDetectInterface: true, strictRoute: false,
            mtu: nil, udpTimeout: nil, routeAddress: nil,
            routeExcludeAddress: nil, includeInterface: nil, excludeInterface: nil
        )
        let result = TunConfigValidator.validate(input)
        XCTAssertTrue(result.blockingErrors.isEmpty,
                      "Valid input should have no blocking errors: \(result.blockingErrors.map(\.message))")
    }

    func test_tunValidator_strictRoute_warns() {
        let input = TunConfigValidationInput(
            enable: true, device: nil, stack: "gvisor", dnsHijack: nil,
            autoRoute: true, autoDetectInterface: true, strictRoute: true,
            mtu: nil, udpTimeout: nil, routeAddress: nil,
            routeExcludeAddress: nil, includeInterface: nil, excludeInterface: nil
        )
        let result = TunConfigValidator.validate(input)
        XCTAssertTrue(result.warnings.contains { $0.message.localizedCaseInsensitiveContains("strict-route") },
                      "strict-route should produce a warning about macOS workflows")
    }

    func test_tunValidator_bothInterfaces_warns() {
        let input = TunConfigValidationInput(
            enable: true, device: nil, stack: "gvisor", dnsHijack: nil,
            autoRoute: true, autoDetectInterface: false, strictRoute: false,
            mtu: nil, udpTimeout: nil, routeAddress: nil,
            routeExcludeAddress: nil,
            includeInterface: ["en0"], excludeInterface: ["utun1"]
        )
        let result = TunConfigValidator.validate(input)
        // ponytail: both include+exclude interface produces a warning, not a
        // blocking error — the validator treats it as expert-only, not invalid.
        XCTAssertTrue(result.warnings.contains {
            $0.message.localizedCaseInsensitiveContains("include-interface") &&
                $0.message.localizedCaseInsensitiveContains("exclude-interface")
        }, "Both include and exclude interface should produce a warning")
    }

    func test_dnsValidator_validInput_passes() {
        let input = DNSConfigValidationInput(
            enable: true, enhancedMode: nil, fakeIPRange: nil, fakeIPFilter: nil,
            fakeIPFilterMode: nil, nameserver: nil, fallback: nil,
            directNameserver: nil, respectRules: true, useHosts: true,
            useSystemHosts: false, preferH3: false, listen: nil
        )
        let result = DNSConfigValidator.validate(input)
        let blocking = result.issues.filter { $0.severity == .blocking }
        XCTAssertTrue(blocking.isEmpty,
                      "Valid DNS input should have no blocking issues: \(blocking.map(\.message))")
    }

    func test_dnsValidator_respectRulesWithoutResolver_warns() {
        let input = DNSConfigValidationInput(
            enable: true, enhancedMode: nil, fakeIPRange: nil, fakeIPFilter: nil,
            fakeIPFilterMode: nil, nameserver: nil, fallback: nil,
            directNameserver: nil, respectRules: true, useHosts: false,
            useSystemHosts: false, preferH3: false, listen: nil
        )
        let result = DNSConfigValidator.validate(input)
        XCTAssertTrue(result.issues.contains { $0.message.contains("respect-rules") },
                      "Respect-rules without resolver should produce a validation issue")
    }
}

// MARK: - Helper command contract

final class HelperCommandContractTests: XCTestCase {
    func test_classifyReplyError_nil_returnsUnknown() {
        XCTAssertEqual(HelperCommandContract.classifyReplyError(nil), .unknown)
    }

    func test_classifyReplyError_empty_returnsUnknown() {
        XCTAssertEqual(HelperCommandContract.classifyReplyError(""), .unknown)
    }

    func test_classifyReplyError_allPrefixes() {
        let cases: [(String, HelperCommandErrorCode)] = [
            ("EINVAL: bad input", .invalidInput),
            ("EAUTH: no access", .unauthorized),
            ("EUNSUPPORTED: nope", .unsupported),
            ("ETIMEOUT: too slow", .timeout),
            ("EFORBIDDEN: denied", .forbidden),
            ("ENOTINSTALLED: missing", .notInstalled),
        ]
        for (input, expected) in cases {
            XCTAssertEqual(HelperCommandContract.classifyReplyError(input), expected,
                           "\(input) should classify as \(expected)")
        }
    }
}

// MARK: - Helper status

final class HelperStatusTests: XCTestCase {
    func test_allTrustStates_exist() {
        let states: [HelperTrustState] = [.unknown, .unavailable, .unsignedDebugBuild,
                                          .requirementMismatch, .notInstalled,
                                          .installedButUnverified, .verified]
        XCTAssertEqual(states.count, 7)
    }

    func test_status_producesDiagnosticMessages() {
        let status = HelperStatus(trustState: .notInstalled,
                                  isPrivilegedHelperAvailable: false,
                                  bundleIdentifier: "com.test.helper")
        XCTAssertFalse(status.diagnosticMessage.isEmpty)
        XCTAssertFalse(status.recoverySuggestion.isEmpty)
    }

    func test_codableRoundtrip() throws {
        let original = HelperStatus(trustState: .verified,
                                    isPrivilegedHelperAvailable: true,
                                    bundleIdentifier: "com.test.helper")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HelperStatus.self, from: data)
        XCTAssertEqual(decoded.trustState, .verified)
        XCTAssertEqual(decoded.bundleIdentifier, "com.test.helper")
    }
}

// MARK: - Redactor

final class RedactorTests: XCTestCase {
    func test_redactURLString_stripsSecrets() {
        let redacted = SmartXRedactor.redactURLString("http://127.0.0.1:9090?token=abc123secret")
        XCTAssertNotNil(redacted)
        XCTAssertFalse(redacted?.contains("abc123secret") ?? true)
    }

    func test_sanitizeText_redactsProxyURIs() {
        let sanitized = SmartXRedactor.sanitizeText("ss://aes-256-gcm:password@example.com:8388")
        XCTAssertFalse(sanitized.contains("password"))
    }

    func test_sanitizeText_preservesSafeContent() {
        let sanitized = SmartXRedactor.sanitizeText("Core version: 1.18.0, mode: rule")
        XCTAssertTrue(sanitized.contains("Core version"))
    }
}

// MARK: - Remote config model

final class RemoteConfigModelTests: XCTestCase {
    func test_decode_validJSON() throws {
        let json = #"{"name":"test","url":"https://example.com/config.yaml"}"#
        let model = try JSONDecoder().decode(RemoteConfigModel.self, from: Data(json.utf8))
        XCTAssertEqual(model.name, "test")
        XCTAssertEqual(model.url, "https://example.com/config.yaml")
    }

    func test_validationState_defaultsToUnknown() throws {
        let json = #"{"name":"test","url":"https://example.com/config.yaml"}"#
        let model = try JSONDecoder().decode(RemoteConfigModel.self, from: Data(json.utf8))
        XCTAssertEqual(model.validationState, .unknown)
    }
}

// MARK: - LightGBM override model

final class LightGBMOverrideTests: XCTestCase {
    func test_codableRoundtrip() throws {
        let json = """
        {"enabled":true,"modelURL":"https://example.com/model.bin","autoUpdate":true,"updateIntervalHours":72}
        """
        let override = try JSONDecoder().decode(LightGBMOverride.self, from: Data(json.utf8))
        XCTAssertTrue(override.enabled)
        XCTAssertEqual(override.modelURL, "https://example.com/model.bin")
        XCTAssertTrue(override.autoUpdate)
        XCTAssertEqual(override.updateIntervalHours, 72)
    }

    func test_managedOverride_roundtrip() throws {
        let json = """
        {"schemaVersion":1,"lightGBM":{"enabled":true,"modelURL":"https://example.com/model.bin","autoUpdate":false,"updateIntervalHours":48}}
        """
        let model = try JSONDecoder().decode(SmartXManagedOverride.self, from: Data(json.utf8))
        XCTAssertEqual(model.schemaVersion, 1)
        XCTAssertEqual(model.lightGBM?.modelURL, "https://example.com/model.bin")
    }
}

// MARK: - Tun lifecycle diagnostics

final class TunLifecycleDiagnosticsTests: XCTestCase {
    func test_preflightReport_codableRoundtrip() throws {
        let report = TunPreflightReport(
            operation: .enable,
            runtimeMode: .externalController,
            canAttemptRequestedOperation: true,
            blockers: [],
            warnings: ["test warning"],
            helperTrustState: .verified,
            helperTunCommandsReserved: true,
            verificationScope: .controllerConfigOnly,
            userMessage: "TUN is ready",
            recoverySuggestion: "Proceed"
        )
        let data = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(TunPreflightReport.self, from: data)
        XCTAssertEqual(decoded.operation, .enable)
        XCTAssertEqual(decoded.warnings, ["test warning"])
    }

    func test_verificationReport_codableRoundtrip() throws {
        let report = TunLifecycleVerificationReport(
            expectedEnabled: true,
            outcome: .controllerStateMatches,
            verificationScope: .controllerConfigOnly,
            controllerReportedEnabled: true,
            runtimeVerification: nil,
            message: "OK",
            recoverySuggestion: ""
        )
        let data = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(TunLifecycleVerificationReport.self, from: data)
        XCTAssertEqual(decoded.outcome, .controllerStateMatches)
    }
}

// MARK: - Config workspace (Phase 9)

final class ConfigWorkspaceTests: XCTestCase {
    func test_pipeline_ordersActiveLayers() {
        let base = ConfigLayer(name: "base", type: .base,
                               source: ConfigSource(type: .local, location: "/tmp/base.yaml",
                                                    remoteURL: nil, displayName: "Base",
                                                    validationState: .valid, lastUpdatedAt: nil),
                               enabled: true, order: 0,
                               mergeOperations: nil, scriptIdentifier: nil)
        let merge = ConfigLayer(name: "merge", type: .merge,
                                source: ConfigSource(type: .local, location: "/tmp/merge.yaml",
                                                     remoteURL: nil, displayName: "Merge",
                                                     validationState: .valid, lastUpdatedAt: nil),
                                enabled: true, order: 1,
                                mergeOperations: [
                                    ConfigMergeOperation(type: .appendRules, target: nil,
                                                         value: "DOMAIN-SUFFIX,example.com", description: "extra rule")
                                ], scriptIdentifier: nil)
        let pipeline = ConfigPipeline(layers: [base, merge],
                                      activeLayerNames: ["base", "merge"],
                                      generatedAt: Date())
        XCTAssertEqual(pipeline.orderedActiveLayers.count, 2)
        XCTAssertEqual(pipeline.orderedActiveLayers.first?.name, "base")
        XCTAssertTrue(pipeline.hasOverrides)
    }

    func test_pipeline_noOverrides_whenNoMergeOrScript() {
        let base = ConfigLayer(name: "base", type: .base,
                               source: ConfigSource(type: .remote, location: "https://example.com/config.yaml",
                                                    remoteURL: "https://example.com/config.yaml",
                                                    displayName: "Remote", validationState: .valid,
                                                    lastUpdatedAt: nil),
                               enabled: true, order: 0,
                               mergeOperations: nil, scriptIdentifier: nil)
        let pipeline = ConfigPipeline(layers: [base], activeLayerNames: ["base"], generatedAt: Date())
        XCTAssertFalse(pipeline.hasOverrides)
    }

    func test_workspace_validate_detectsDuplicateOrders() {
        let layer1 = ConfigLayer(name: "a", type: .base,
                                 source: ConfigSource(type: .local, location: "/tmp/a.yaml",
                                                      remoteURL: nil, displayName: "A",
                                                      validationState: .valid, lastUpdatedAt: nil),
                                 enabled: true, order: 0,
                                 mergeOperations: nil, scriptIdentifier: nil)
        let layer2 = ConfigLayer(name: "b", type: .merge,
                                 source: ConfigSource(type: .local, location: "/tmp/b.yaml",
                                                      remoteURL: nil, displayName: "B",
                                                      validationState: .valid, lastUpdatedAt: nil),
                                 enabled: true, order: 0,
                                 mergeOperations: nil, scriptIdentifier: nil)
        let pipeline = ConfigPipeline(layers: [layer1, layer2],
                                      activeLayerNames: ["a", "b"],
                                      generatedAt: Date())
        let ws = ConfigWorkspace(layers: [layer1, layer2],
                                 artifacts: [],
                                 activePipeline: pipeline,
                                 lastKnownGoodPipeline: nil,
                                 workspaceRoot: URL(fileURLWithPath: "/tmp/.smartx/workspace"))
        let issues = ws.validate()
        XCTAssertTrue(issues.contains { $0.contains("duplicate order") },
                      "Should detect duplicate order values")
    }

    func test_workspace_validate_passesCleanPipeline() {
        let base = ConfigLayer(name: "base", type: .base,
                               source: ConfigSource(type: .local, location: "/tmp/base.yaml",
                                                    remoteURL: nil, displayName: "Base",
                                                    validationState: .valid, lastUpdatedAt: nil),
                               enabled: true, order: 0,
                               mergeOperations: nil, scriptIdentifier: nil)
        let pipeline = ConfigPipeline(layers: [base], activeLayerNames: ["base"], generatedAt: Date())
        let ws = ConfigWorkspace(layers: [base],
                                 artifacts: [],
                                 activePipeline: pipeline,
                                 lastKnownGoodPipeline: nil,
                                 workspaceRoot: URL(fileURLWithPath: "/tmp/.smartx/workspace"))
        XCTAssertTrue(ws.validate().isEmpty, "Clean pipeline should have no validation issues")
    }

    func test_mergeOperation_codableRoundtrip() throws {
        let op = ConfigMergeOperation(type: .prependRules, target: "rules",
                                      value: "DOMAIN-SUFFIX,example.com",
                                      description: "Add rule for example.com")
        let data = try JSONEncoder().encode(op)
        let decoded = try JSONDecoder().decode(ConfigMergeOperation.self, from: data)
        XCTAssertEqual(decoded.type, .prependRules)
        XCTAssertEqual(decoded.value, "DOMAIN-SUFFIX,example.com")
    }

    func test_artifact_allTypes() {
        let types: [ConfigArtifactType] = [.sourceCopy, .generatedEffective, .lastKnownGood, .mergePreview]
        let artifacts = types.map {
            ConfigArtifact(type: $0, localURL: URL(fileURLWithPath: "/tmp/\($0.rawValue).yaml"),
                           metadataURL: URL(fileURLWithPath: "/tmp/\($0.rawValue).json"),
                           pipeline: nil, provenance: "test", createdAt: Date(), isValid: true)
        }
        XCTAssertEqual(artifacts.count, 4)
        let effective = artifacts.filter { $0.type == .generatedEffective }
        XCTAssertEqual(effective.count, 1)
    }

    func test_codableRoundtrip() throws {
        let ws = ConfigWorkspace(
            layers: [],
            artifacts: [
                ConfigArtifact(type: .lastKnownGood,
                               localURL: URL(fileURLWithPath: "/tmp/lkg.yaml"),
                               metadataURL: URL(fileURLWithPath: "/tmp/lkg.json"),
                               pipeline: nil, provenance: "source-copy",
                               createdAt: Date(), isValid: true)
            ],
            activePipeline: nil,
            lastKnownGoodPipeline: nil,
            workspaceRoot: URL(fileURLWithPath: "/tmp/.smartx/workspace")
        )
        let data = try JSONEncoder().encode(ws)
        let decoded = try JSONDecoder().decode(ConfigWorkspace.self, from: data)
        XCTAssertEqual(decoded.artifacts.count, 1)
        XCTAssertEqual(decoded.artifacts.first?.type, .lastKnownGood)
    }
}

// MARK: - Config YAML editor (Phase 9)

final class ConfigYAMLEditorTests: XCTestCase {
    func test_renderSection_boolValues() {
        let result = ConfigYAMLEditor.renderSection(named: "test",
                                                    params: ["enabled": true, "verbose": false],
                                                    keyOrder: ["enabled", "verbose"])
        XCTAssertTrue(result.contains("enabled: true"))
        XCTAssertTrue(result.contains("verbose: false"))
    }

    func test_renderSection_stringValues() {
        let result = ConfigYAMLEditor.renderSection(named: "dns",
                                                    params: ["listen": ":53"],
                                                    keyOrder: ["listen"])
        XCTAssertTrue(result.contains("dns:"))
        XCTAssertTrue(result.contains("listen: \":53\""))
    }

    func test_renderSection_arrayValues() {
        let result = ConfigYAMLEditor.renderSection(named: "tun",
                                                    params: ["route-address": ["0.0.0.0/0", "::/0"]],
                                                    keyOrder: ["route-address"])
        XCTAssertTrue(result.contains("route-address:"))
        XCTAssertTrue(result.contains("- \"0.0.0.0/0\""))
        XCTAssertTrue(result.contains("- \"::/0\""))
    }

    func test_renderSection_skipsEmptyArrays() {
        let result = ConfigYAMLEditor.renderSection(named: "dns",
                                                    params: ["nameserver": [String]()],
                                                    keyOrder: ["nameserver"])
        XCTAssertFalse(result.contains("nameserver:"),
                       "Empty arrays should not produce YAML entries")
    }

    func test_upsertSection_replacesExisting() {
        let original = "dns:\n  enable: false\n\nproxies:\n  - name: Proxy1\n"
        let result = ConfigYAMLEditor.upsertSection(named: "dns", in: original,
                                                    params: ["enable": true],
                                                    keyOrder: ["enable"])
        XCTAssertTrue(result.contains("enable: true"))
        XCTAssertFalse(result.contains("enable: false"))
        XCTAssertTrue(result.contains("proxies:"),
                      "Sections after the replaced section should be preserved")
    }

    func test_upsertSection_appendsWhenMissing() {
        let original = "proxies:\n  - name: Proxy1\n"
        let result = ConfigYAMLEditor.upsertSection(named: "dns", in: original,
                                                    params: ["enable": true],
                                                    keyOrder: ["enable"])
        XCTAssertTrue(result.contains("dns:"))
        XCTAssertTrue(result.contains("proxies:"))
    }
}

// MARK: - Config pipeline execution (Phase 9)

final class ConfigPipelineExecutionTests: XCTestCase {
    func test_generate_fieldOverride_appliesChange() {
        let baseYAML = "tun:\n  enable: false\n"
        let merge = ConfigLayer(name: "override", type: .merge,
                                source: ConfigSource(type: .local, location: "/tmp/override.yaml",
                                                     remoteURL: nil, displayName: "Override",
                                                     validationState: .valid, lastUpdatedAt: nil),
                                enabled: true, order: 1,
                                mergeOperations: [
                                    ConfigMergeOperation(type: .fieldOverride, target: "tun",
                                                         value: "enable=true", description: "Enable TUN")
                                ], scriptIdentifier: nil)
        let pipeline = ConfigPipeline(layers: [merge], activeLayerNames: ["override"], generatedAt: Date())
        let (result, applied) = pipeline.generateEffectiveConfig(baseYAML: baseYAML)
        XCTAssertEqual(applied, 1)
        XCTAssertTrue(result.contains("enable: true"))
        XCTAssertFalse(result.contains("enable: false"))
    }

    func test_generate_skipsInapplicableOperations() {
        let baseYAML = "proxies:\n  - name: P1\n"
        let merge = ConfigLayer(name: "merge", type: .merge,
                                source: ConfigSource(type: .local, location: "/tmp/merge.yaml",
                                                     remoteURL: nil, displayName: "Merge",
                                                     validationState: .valid, lastUpdatedAt: nil),
                                enabled: true, order: 1,
                                mergeOperations: [
                                    ConfigMergeOperation(type: .prependProxyGroups, target: nil,
                                                         value: "Group1", description: "skip")
                                ], scriptIdentifier: nil)
        let pipeline = ConfigPipeline(layers: [merge], activeLayerNames: ["merge"], generatedAt: Date())
        let (result, applied) = pipeline.generateEffectiveConfig(baseYAML: baseYAML)
        XCTAssertEqual(applied, 0, "Unsupported operations should be skipped, not fail")
        XCTAssertTrue(result.contains("P1"), "Base YAML should be preserved")
    }

    func test_generate_prependRule_addsToEmptyYAML() {
        let merge = ConfigLayer(name: "rules", type: .merge,
                                source: ConfigSource(type: .local, location: "/tmp/rules.yaml",
                                                     remoteURL: nil, displayName: "Rules",
                                                     validationState: .valid, lastUpdatedAt: nil),
                                enabled: true, order: 1,
                                mergeOperations: [
                                    ConfigMergeOperation(type: .prependRules, target: nil,
                                                         value: "DOMAIN-SUFFIX,example.com", description: "rule")
                                ], scriptIdentifier: nil)
        let pipeline = ConfigPipeline(layers: [merge], activeLayerNames: ["rules"], generatedAt: Date())
        let (result, applied) = pipeline.generateEffectiveConfig(baseYAML: "")
        XCTAssertEqual(applied, 1)
        XCTAssertTrue(result.contains("rules:"))
        XCTAssertTrue(result.contains("DOMAIN-SUFFIX,example.com"))
    }
}
