#!/usr/bin/env ruby
# ponytail: use the xcodeproj gem (already installed) instead of manual pbxproj
# surgery. Creates a SmartXTests XCTest bundle target with pure-logic production
# source files compiled directly into the test target.

require 'xcodeproj'

PROJ_PATH = 'ClashX.xcodeproj'
TEST_TARGET_NAME = 'SmartXTests'
TEST_GROUP_NAME = 'Tests'
TEST_FILE = 'Tests/SmartXTests/SmartXTests.swift'
TEST_INFO_PLIST = 'Tests/SmartXTests/Info.plist'

# Production source files that have NO CocoaPods dependencies (Alamofire,
# CocoaLumberjack, RxSwift, etc.) and can compile standalone.
PURE_PRODUCTION_SOURCES = [
  'ClashX/General/Utils/ControllerEndpointBuilder.swift',
  'ClashX/General/Utils/ConfigValidationIssue.swift',
  'ClashX/General/Utils/TunConfigValidator.swift',
  'ClashX/General/Utils/DNSConfigValidator.swift',
  'ClashX/General/Utils/SmartXRedactor.swift',
  'ClashX/General/Utils/DiagnosticsLogReader.swift',
  'ClashX/General/Utils/DiagnosticsArtifactFormatter.swift',
  'ClashX/General/Utils/HelperCommandRegistry.swift',
  'ClashX/General/Utils/TunRuntimeInterfaceProbe.swift',
  'ClashX/General/Utils/TunRuntimeRouteProbe.swift',
  'ClashX/General/Utils/TunRuntimeDNSProbe.swift',
  'ClashX/General/Managers/CoreCapability.swift',
  'ClashX/General/Managers/ProfileArtifactManager.swift',
  'ClashX/General/Managers/SmartXManagedOverrideManager.swift',
  'ClashX/General/Managers/EffectiveConfigGenerator.swift',
  'ClashX/General/Managers/TunPreflightPlanner.swift',
  'ClashX/Models/HelperStatus.swift',
  'ClashX/Models/HelperCommandContract.swift',
  'ClashX/Models/TunLifecycleDiagnostics.swift',
  'ClashX/Models/SmartXManagedOverrideModel.swift',
  'ClashX/Models/RemoteConfigModel.swift',
]

puts "Opening project..."
project = Xcodeproj::Project.open(PROJ_PATH)

# Find or create Tests group
main_group = project.main_group
tests_group = main_group.groups.find { |g| g.name == TEST_GROUP_NAME || g.path == TEST_GROUP_NAME }
unless tests_group
  tests_group = main_group.new_group(TEST_GROUP_NAME, TEST_GROUP_NAME)
  puts "Created Tests group"
else
  puts "Found existing Tests group"
end

# Create SmartXTests subgroup for the test files
smartx_tests_group = tests_group.groups.find { |g| g.name == 'SmartXTests' }
unless smartx_tests_group
  smartx_tests_group = tests_group.new_group('SmartXTests', 'SmartXTests')
  puts "Created Tests/SmartXTests subgroup"
end

# Check if test target already exists
if project.targets.any? { |t| t.name == TEST_TARGET_NAME }
  puts "Target #{TEST_TARGET_NAME} already exists — updating sources only"
  test_target = project.targets.find { |t| t.name == TEST_TARGET_NAME }
else
  # Create the XCTest bundle target
  test_target = project.new_target(
    :unit_test_bundle,
    TEST_TARGET_NAME,
    :macos,
    '11.0'
  )
  puts "Created #{TEST_TARGET_NAME} target"

  # Configure build settings
  test_target.build_configurations.each do |config|
    config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.doodlenet.ClashX.SmartXTests'
    config.build_settings['INFOPLIST_FILE'] = TEST_INFO_PLIST
    config.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
    config.build_settings['CODE_SIGNING_REQUIRED'] = 'NO'
    config.build_settings['CODE_SIGN_IDENTITY'] = ''
    config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '11.0'
    config.build_settings['SWIFT_VERSION'] = '5.0'
    # ponytail: no bridging header needed — pure Swift
    config.build_settings['SWIFT_OBJC_BRIDGING_HEADER'] = nil
    # Link against the main app's frameworks at test time
    config.build_settings['LD_RUNPATH_SEARCH_PATHS'] = '$(inherited) @executable_path/../Frameworks @loader_path/../Frameworks'
  end
  puts "Configured build settings"
end

# Add production source files to the test target
PURE_PRODUCTION_SOURCES.each do |src_path|
  # Find or create file reference
  file_ref = project.files.find { |f| f.path == src_path }
  unless file_ref
    # Add to the ClashX group
    path_parts = src_path.split('/')
    # Navigate to the right group
    parent = main_group
    path_parts[0..-2].each do |part|
      existing = parent.groups.find { |g| g.path == part || g.name == part }
      parent = existing || parent.new_group(part, part)
    end
    file_ref = parent.new_file(path_parts.last)
    file_ref.path = src_path
    file_ref.source_tree = 'SOURCE_ROOT'
  end

  # Add to test target sources build phase unless already there
  sources_phase = test_target.build_phases.find { |bp| bp.is_a?(Xcodeproj::Project::Object::PBXSourcesBuildPhase) }
  unless sources_phase.files.any? { |f| f.file_ref == file_ref }
    sources_phase.add_file_reference(file_ref)
  end
end

# Add test file references
[TEST_FILE].each do |test_path|
  path_parts = test_path.split('/')
  file_name = path_parts.last

  # Check if already in project
  existing_ref = project.files.find { |f| f.path == test_path }
  unless existing_ref
    file_ref = smartx_tests_group.new_file(file_name)
    file_ref.path = test_path
    file_ref.source_tree = 'SOURCE_ROOT'
    file_ref.last_known_file_type = 'sourcecode.swift'
  else
    # Move to SmartXTests group if elsewhere
    file_ref = existing_ref
    unless file_ref.parent == smartx_tests_group
      file_ref.remove_from_project
      smartx_tests_group << file_ref
    end
  end

  # Add to test target sources
  sources_phase = test_target.build_phases.find { |bp| bp.is_a?(Xcodeproj::Project::Object::PBXSourcesBuildPhase) }
  file_ref = project.files.find { |f| f.path == test_path }
  unless sources_phase.files.any? { |f| f.file_ref == file_ref }
    sources_phase.add_file_reference(file_ref)
  end
end

# Create Info.plist for test bundle if it doesn't exist
unless File.exist?(TEST_INFO_PLIST)
  FileUtils.mkdir_p(File.dirname(TEST_INFO_PLIST))
  File.write(TEST_INFO_PLIST, <<~PLIST)
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>CFBundleDevelopmentRegion</key>
        <string>en</string>
        <key>CFBundleExecutable</key>
        <string>$(EXECUTABLE_NAME)</string>
        <key>CFBundleIdentifier</key>
        <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
        <key>CFBundleInfoDictionaryVersion</key>
        <string>6.0</string>
        <key>CFBundleName</key>
        <string>$(PRODUCT_NAME)</string>
        <key>CFBundlePackageType</key>
        <string>BNDL</string>
        <key>CFBundleShortVersionString</key>
        <string>1.0</string>
        <key>CFBundleVersion</key>
        <string>1</string>
    </dict>
    </plist>
  PLIST
  puts "Created #{TEST_INFO_PLIST}"
end

project.save
puts "Project saved successfully"
puts "Target '#{TEST_TARGET_NAME}' is ready"
puts "Run: xcodebuild test -workspace ClashX.xcworkspace -scheme ClashX -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO"
