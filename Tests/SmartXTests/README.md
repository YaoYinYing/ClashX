# SmartXTests

38 XCTest cases across 11 test classes. Compiles pure-logic production sources directly.

## Coverage

| Test class | What it covers |
|---|---|
| ControllerEndpointBuilderTests | URL construction, scheme conversion, encoding |
| ConfigValidatorTests | TUN/DNS validation rules (warnings, blocking errors) |
| HelperCommandContractTests | classifyReplyError error prefix mapping |
| HelperStatusTests | Trust states, diagnostic messages, Codable |
| RedactorTests | URL/path sanitization, proxy URI redaction |
| RemoteConfigModelTests | JSON decode, validation state defaults |
| LightGBMOverrideTests | Codable roundtrip, managed override model |
| TunLifecycleDiagnosticsTests | PreflightReport/VerificationReport Codable |
| ConfigWorkspaceTests | Pipeline validation, layer ordering |
| ConfigYAMLEditorTests | YAML render/upsert with escaping |
| ConfigPipelineExecutionTests | fieldOverride application |

## Architecture

Production source files are compiled directly into the test target (same module).
Stubs in `TestStubs.swift` provide `ConfigManager` and `ClashConfig` types for
files that reference CocoaPods-dependent production types.

**Limitation:** cannot test AppKit/CocoaPods/Go bridge integration.
Smoke harnesses (`Tests/SecurityHarness/`) and manual testing cover those paths.

## Run

```bash
xcodebuild test -workspace ClashX.xcworkspace -scheme ClashX \
  -destination 'platform=macOS' -only-testing:SmartXTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""
```
