#!/usr/bin/env ruby
# Adds XavierMac, XavierMacFilterExtension, XavierMacProxyExtension, and XavierShared
# targets to the Xavier iOS project using the xcodeproj Ruby gem.

require 'xcodeproj'

PROJECT_PATH = '/Users/bogdan/DEV/xavier-ios/Xavier.xcodeproj'
project = Xcodeproj::Project.open(PROJECT_PATH)

xavier_target = project.targets.find { |t| t.name == 'Xavier' }
raise "Could not find Xavier target" unless xavier_target

# Get the existing Debug/Release configurations from the project
project_build_configs = project.root_object.build_configuration_list.build_configurations
debug_settings = project_build_configs.find { |bc| bc.name == 'Debug' }
release_settings = project_build_configs.find { |bc| bc.name == 'Release' }

main_group = project.main_group

def find_or_create_ref(group, path)
  existing = group.files.find { |f| f.display_name == File.basename(path) }
  return existing if existing
  group.new_reference(path)
end

def configure_build_settings(target, settings, configurations = ['Debug', 'Release'])
  target.build_configuration_list.build_configurations.each do |bc|
    configurations.each do |config_name|
      if bc.name == config_name
        settings.each do |key, value|
          bc.build_settings[key] = value
        end
      end
    end
  end
end

# ============================================================
# 1. Create XavierMac App target
# ============================================================

mac_group = main_group.new_group('XavierMac', 'XavierMac')
mac_views = mac_group.new_group('Views', 'Views')
mac_services = mac_group.new_group('Services', 'Services')

mac_target = project.new_target(:application, 'XavierMac', :macos, '13.0')

%w[XavierMacApp.swift XavierMacAppDelegate.swift].each do |f|
  ref = find_or_create_ref(mac_group, f)
  mac_target.source_build_phase.add_file_reference(ref)
end

%w[SidebarContentView.swift MenuBarView.swift].each do |f|
  ref = find_or_create_ref(mac_views, f)
  mac_target.source_build_phase.add_file_reference(ref)
end

%w[MacOSBundleResolver.swift].each do |f|
  ref = find_or_create_ref(mac_services, f)
  mac_target.source_build_phase.add_file_reference(ref)
end

mac_target.build_configuration_list.build_configurations.each do |bc|
  bc.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = '$(XAVIER_BUNDLE_ID)mac'
  bc.build_settings['SWIFT_VERSION'] = '5.0'
  bc.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '13.0'
  bc.build_settings['INFOPLIST_FILE'] = 'XavierMac/Info.plist'
  bc.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'XavierMac/XavierMac.entitlements'
  bc.build_settings['SDKROOT'] = 'macosx'
  bc.build_settings['GENERATE_INFOPLIST_FILE'] = 'NO'
end

# ============================================================
# 2. Create XavierMacFilterExtension target
# ============================================================

filter_group = main_group.new_group('XavierMacFilterExtension', 'XavierMacFilterExtension')

filter_target = project.new_target(:app_extension, 'XavierMacFilterExtension', :macos, '13.0')

%w[main.swift FilterDataProvider.swift].each do |f|
  ref = find_or_create_ref(filter_group, f)
  filter_target.source_build_phase.add_file_reference(ref)
end

filter_target.build_configuration_list.build_configurations.each do |bc|
  bc.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = '$(XAVIER_BUNDLE_ID)mac.filter'
  bc.build_settings['SWIFT_VERSION'] = '5.0'
  bc.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '13.0'
  bc.build_settings['INFOPLIST_FILE'] = 'XavierMacFilterExtension/Info.plist'
  bc.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'XavierMacFilterExtension/XavierMacFilterExtension.entitlements'
  bc.build_settings['APPLICATION_EXTENSION_API_ONLY'] = 'YES'
  bc.build_settings['SDKROOT'] = 'macosx'
  bc.build_settings['GENERATE_INFOPLIST_FILE'] = 'NO'
end

# ============================================================
# 3. Create XavierMacProxyExtension target
# ============================================================

proxy_group = main_group.new_group('XavierMacProxyExtension', 'XavierMacProxyExtension')

proxy_target = project.new_target(:app_extension, 'XavierMacProxyExtension', :macos, '13.0')

%w[main.swift TransparentProxyProvider.swift].each do |f|
  ref = find_or_create_ref(proxy_group, f)
  proxy_target.source_build_phase.add_file_reference(ref)
end

proxy_target.build_configuration_list.build_configurations.each do |bc|
  bc.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = '$(XAVIER_BUNDLE_ID)mac.proxy'
  bc.build_settings['SWIFT_VERSION'] = '5.0'
  bc.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '13.0'
  bc.build_settings['INFOPLIST_FILE'] = 'XavierMacProxyExtension/Info.plist'
  bc.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'XavierMacProxyExtension/XavierMacProxyExtension.entitlements'
  bc.build_settings['APPLICATION_EXTENSION_API_ONLY'] = 'YES'
  bc.build_settings['SDKROOT'] = 'macosx'
  bc.build_settings['GENERATE_INFOPLIST_FILE'] = 'NO'
end

# ============================================================
# 4. Create XavierShared Framework target
# ============================================================

shared_group = main_group.new_group('XavierShared', 'XavierShared')
shared_platform = shared_group.new_group('Platform', 'Platform')

shared_target = project.new_target(:framework, 'XavierShared', :ios, '16.0')

# Platform abstraction files  
%w[BundleResolver.swift PlatformConstants.swift FlowMetadataProvider.swift].each do |f|
  ref = find_or_create_ref(shared_platform, f)
  shared_target.source_build_phase.add_file_reference(ref)
end

shared_target.build_configuration_list.build_configurations.each do |bc|
  bc.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = '$(XAVIER_BUNDLE_ID).shared'
  bc.build_settings['SWIFT_VERSION'] = '5.0'
  bc.build_settings['DEFINES_MODULE'] = 'YES'
  bc.build_settings['APPLICATION_EXTENSION_API_ONLY'] = 'YES'
  bc.build_settings['SDKROOT'] = 'iphoneos'
  bc.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '16.0'
end

# ============================================================
# Add target dependencies
# ============================================================

mac_target.add_dependency(filter_target)
mac_target.add_dependency(proxy_target)

project.save

puts "Successfully added targets:"
puts "  - XavierMac (macOS App)"
puts "  - XavierMacFilterExtension (macOS System Extension)"
puts "  - XavierMacProxyExtension (macOS System Extension)"
puts "  - XavierShared (iOS Framework)"
puts ""
puts "REMAINING STEPS IN XCODE:"
puts "  1. Add NetworkExtension.framework to Filter and Proxy extension targets"
puts "  2. Add Network.framework to Proxy extension target"
puts "  3. Add XavierShared framework dependency to all targets that need it"
puts "  4. Add 'Embed System Extensions' copy files phase to XavierMac"
puts "  5. Add 'Embed Frameworks' copy files phase for XavierShared"
puts "  6. Add Core Data model files to XavierShared target membership"
puts "  7. Add shared source files to XavierShared target membership"
puts "  8. Add 'import XavierShared' to files that need it"
puts "  9. Configure signing & capabilities for each target"