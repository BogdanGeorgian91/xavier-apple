#!/usr/bin/env ruby
# Fixes XavierShared framework configuration for cross-platform support
# - Changes SDKROOT to support both iOS and macOS  
# - Removes iOS-only files from XavierShared (IOSBundleResolver)
# - Removes duplicate file references in XavierShared sources
# - Adds XavierShared.framework link to XavierMac target
# - Adds swift-certificates X509 package dependency to XavierShared
# - Configures macOS deployment target for XavierShared
# - Adds Core Data models as resources

require 'xcodeproj'

PROJECT_PATH = '/Users/bogdan/DEV/xavier-ios/Xavier.xcodeproj'
project = Xcodeproj::Project.open(PROJECT_PATH)

main_group = project.main_group

shared_target = project.targets.find { |t| t.name == 'XavierShared' }
mac_target = project.targets.find { |t| t.name == 'XavierMac' }
filter_target = project.targets.find { |t| t.name == 'XavierMacFilterExtension' }
proxy_target = project.targets.find { |t| t.name == 'XavierMacProxyExtension' }

raise "Missing target" unless shared_target && mac_target && filter_target && proxy_target

# ============================================================
# 1. Fix XavierShared build settings for cross-platform
# ============================================================

shared_target.build_configurations.each do |config|
  # Support both iOS and macOS
  config.build_settings['SDKROOT'] = 'macosx'  
  # Remove iphoneos-specific setting, let SUPPORTED_PLATFORMS handle it
  # Actually, for a framework shared between iOS app and macOS sysextension,
  # we need to build it for both. Let Xcode handle this via SUPPORTS_MACCATALYST
  # or we set it as a macOS framework since the iOS targets don't use it as a framework.
  # 
  # Actually the iOS targets DON'T link XavierShared.framework - they have the source
  # files directly. So XavierShared only needs to be macOS.
  config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '13.0'
  config.build_settings['PRODUCT_NAME'] = '$(TARGET_NAME)'
  
  # Ensure it builds as a framework
  config.build_settings['MACH_O_TYPE'] = 'mh_execute_from_framework' if config.build_settings['MACH_O_TYPE'].nil?
  
  # Define module name for import
  config.build_settings['PRODUCT_MODULE_NAME'] = 'XavierShared' if config.build_settings['PRODUCT_MODULE_NAME'].nil?
  
  # Set the correct INSTALL_PATH for a macOS framework
  config.build_settings['INSTALL_PATH'] = '@executable_path/../Frameworks' if config.build_settings['INSTALL_PATH'].nil?
  
  # Skip installation for development
  config.build_settings['SKIP_INSTALL'] = 'YES'
  
  # Code signing
  config.build_settings['CODE_SIGN_IDENTITY'] = '' if config.build_settings['CODE_SIGN_IDENTITY'].nil?
end

puts "1. Fixed XavierShared build settings (SDKROOT=macosx, MACOSX_DEPLOYMENT_TARGET=13.0)"

# ============================================================
# 2. Remove iOS-only files from XavierShared sources
# ============================================================

files_to_remove = ['IOSBundleResolver.swift']

shared_source_phase = shared_target.source_build_phase
files_before = shared_source_phase.files.length

shared_source_phase.files.each do |build_file|
  display_name = build_file.display_name
  if files_to_remove.any? { |f| display_name && display_name.include?(f) }
    puts "  Removing iOS-only file from XavierShared: #{display_name}"
    build_file.remove_from_project
  end
end

# Also remove duplicate entries - files that appear twice
file_names = {}
shared_source_phase.files.each do |build_file|
  next unless build_file.display_name
  name = build_file.display_name
  if file_names[name]
    puts "  Removing duplicate file from XavierShared: #{name}"
    build_file.remove_from_project
  else
    file_names[name] = build_file
  end
end

files_after = shared_source_phase.files.length
puts "2. Removed iOS-only and duplicate files (#{files_before} -> #{files_after} files)"

# ============================================================
# 3. Verify source files in XavierShared
# ============================================================

puts "\n XavierShared source files after cleanup:"
shared_source_phase.files.each do |f|
  puts "  #{f.display_name}"
end

# ============================================================
# 4. Add XavierShared.framework to XavierMac's frameworks build phase
# ============================================================

shared_product_ref = shared_target.product_reference
mac_frameworks = mac_target.frameworks_build_phase

unless mac_frameworks.files.any? { |f| f.display_name && f.display_name.include?('XavierShared') }
  mac_frameworks.add_file_reference(shared_product_ref)
  puts "3. Added XavierShared.framework to XavierMac"
else
  puts "3. XavierShared.framework already in XavierMac"
end

# Also update the embed phase - find or create
embed_phase = mac_target.copy_files_build_phases.find { |p| p.name == 'Embed Frameworks' }
if embed_phase && !embed_phase.files.any? { |f| f.display_name && f.display_name.include?('XavierShared') }
  embed_phase.add_file_reference(shared_product_ref)
  puts "   Added XavierShared.framework to Embed Frameworks phase"
end

# ============================================================
# 5. Add swift-certificates X509 package dependency to XavierShared
# ============================================================

# Check if there's already a local package reference
existing_packages = project.root_object.package_references rescue []
x509_ref = nil

# Find existing X509 product reference  
x509_product = nil
project.products.each do |product|
  if product.display_name == 'X509' || product.name == 'X509'
    x509_product = product
    break
  end
end

if x509_product
  # Add X509 to XavierShared's package product dependencies
  existing_deps = shared_target.package_product_dependencies || []
  unless existing_deps.any? { |d| d.product_name == 'X509' }
    dep = shared_target.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
    dep.product_name = 'X509'
    dep.package = x509_product.package if x509_product.respond_to?(:package)
    shared_target.package_product_dependencies << dep
    puts "5. Added X509 package dependency to XavierShared"
  else
    puts "5. X509 already in XavierShared dependencies"
  end
else
  puts "5. X509 product not found - may need manual addition in Xcode"
  puts "   Add swift-certificates local package dependency to XavierShared target in Xcode"
end

# ============================================================
# 6. Add MACOSX_DEPLOYMENT_TARGET to all macOS targets
# ============================================================

[mac_target, filter_target, proxy_target].each do |target|
  target.build_configurations.each do |config|
    config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '13.0' unless config.build_settings['MACOSX_DEPLOYMENT_TARGET']
    # Enable hardened runtime for system extensions
    config.build_settings['ENABLE_HARDENED_RUNTIME'] = 'YES'
  end
end

puts "6. Configured macOS deployment target 13.0 and hardened runtime for all macOS targets"

# ============================================================
# 7. Ensure Core Data models are resources in XavierShared
# ============================================================

xavier_data_model = main_group.find_subpath('Xavier/XavierDataModel.xcdatamodeld', false)
if xavier_data_model
  unless shared_target.resources_build_phase.files.any? { |f| f.display_name && f.display_name.include?('XavierDataModel') }
    shared_target.resources_build_phase.add_file_reference(xavier_data_model.real_path ? xavier_data_model : xavier_data_model)
    puts "7. Added XavierDataModel.xcdatamodeld to XavierShared resources"
  else
    puts "7. XavierDataModel.xcdatamodeld already in XavierShared resources"
  end
end

inspection_model = main_group.find_subpath('Xavier/InspectionModel.xcdatamodeld', false)
if inspection_model
  unless shared_target.resources_build_phase.files.any? { |f| f.display_name && f.display_name.include?('InspectionModel') }
    # Find the proxy group's inspection model instead
    proxy_model = main_group.find_subpath('XavierProxy/InspectionModel.xcdatamodeld', false)
    if proxy_model
      shared_target.resources_build_phase.add_file_reference(proxy_model)
      puts "7. Added InspectionModel.xcdatamodeld to XavierShared resources"
    end
  else
    puts "7. InspectionModel.xcdatamodeld already in XavierShared resources"
  end
end

project.save

puts "\n✅ XavierShared framework configuration fixed!"
puts "\nRemaining manual steps in Xcode:"
puts "  1. Verify XavierShared target's Supported Platforms includes macOS"
puts "  2. Add swift-certificates local package to XavierShared (if not auto-detected)"
puts "  3. Sign all macOS targets with your developer ID"
puts "  4. Add System Extension + Network Extension capabilities to macOS targets"
puts "  5. Verify Core Data model bundle resolution works at runtime"