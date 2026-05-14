#!/usr/bin/env ruby
# Adds framework dependencies, shared source files, and embed phases
# to the newly created XavierShared, XavierMac, XavierMacFilterExtension,
# and XavierMacProxyExtension targets.

require 'xcodeproj'

PROJECT_PATH = '/Users/bogdan/DEV/xavier-ios/Xavier.xcodeproj'
project = Xcodeproj::Project.open(PROJECT_PATH)

main_group = project.main_group

# Find targets
shared_target = project.targets.find { |t| t.name == 'XavierShared' }
mac_target = project.targets.find { |t| t.name == 'XavierMac' }
filter_target = project.targets.find { |t| t.name == 'XavierMacFilterExtension' }
proxy_target = project.targets.find { |t| t.name == 'XavierMacProxyExtension' }
xavier_target = project.targets.find { |t| t.name == 'Xavier' }
xavier_data_target = project.targets.find { |t| t.name == 'XavierData' }
xavier_control_target = project.targets.find { |t| t.name == 'XavierControl' }
xavier_proxy_target = project.targets.find { |t| t.name == 'XavierProxy' }

raise "Missing target" unless shared_target && mac_target && filter_target && proxy_target

# ============================================================
# Helper
# ============================================================
def find_or_create_ref(group, path)
  existing = group.files.find { |f| f.display_name == File.basename(path) }
  return existing if existing
  group.new_reference(path)
end

# ============================================================
# 1. Add shared source files to XavierShared target
# ============================================================

# Find or create the shared platform group
shared_group = main_group.find_subpath('XavierShared', true)
shared_platform = shared_group.find_subpath('Platform', true) || shared_group.new_group('Platform', 'Platform')

shared_source_files = [
  # Rule models
  { path: '../Xavier/Core/Rule.swift', group: shared_group },
  { path: '../Xavier/Core/StaticRules.swift', group: shared_group },
  { path: '../Xavier/Core/SHA256.swift', group: shared_group },
  { path: '../Xavier/Core/UniqueID.swift', group: shared_group },
  # Core Data managers
  { path: '../Xavier/RuleManager.swift', group: shared_group },
  { path: '../Xavier/Core/NetworkEventManager.swift', group: shared_group },
  { path: '../Xavier/Core/BrowserEventManager.swift', group: shared_group },
  { path: '../Xavier/Core/InspectionManager.swift', group: shared_group },
  # Core Data property files
  { path: '../Xavier/Core/NetworkEvent+CoreDataClass.swift', group: shared_group },
  { path: '../Xavier/Core/NetworkEvent+CoreDataProperties.swift', group: shared_group },
  { path: '../Xavier/Core/BrowserEvent+CoreDataClass.swift', group: shared_group },
  { path: '../Xavier/Core/BrowserEvent+CoreDataProperties.swift', group: shared_group },
  { path: '../Xavier/Core/InspectedRequest+CoreDataClass.swift', group: shared_group },
  { path: '../Xavier/Core/InspectedRequest+CoreDataProperties.swift', group: shared_group },
  # Payloads
  { path: '../Xavier/Core/BrowserFlowPayload.swift', group: shared_group },
  { path: '../Xavier/Core/InspectionPayload.swift', group: shared_group },
  { path: '../Xavier/Core/UnifiedNetworkEvent.swift', group: shared_group },
  # Proxy
  { path: '../XavierProxy/AppProxyProvider.swift', group: shared_group },
  { path: '../XavierProxy/FlowCopyManager.swift', group: shared_group },
  { path: '../XavierProxy/TLSProxy.swift', group: shared_group },
  { path: '../XavierProxy/HTTPParser.swift', group: shared_group },
  { path: '../XavierProxy/RequestModifier.swift', group: shared_group },
  { path: '../XavierProxy/ResponseModifier.swift', group: shared_group },
  { path: '../XavierProxy/BlocklistMatcher.swift', group: shared_group },
  { path: '../XavierProxy/CertificateManager.swift', group: shared_group },
  # Modification
  { path: '../Xavier/Core/ModificationRule.swift', group: shared_group },
  { path: '../Xavier/Core/ScriptBlocklistManager.swift', group: shared_group },
  # Constants
  { path: '../Xavier/Constants.swift', group: shared_group },
  # Platform abstractions (already in shared_group/Platform)
  { path: 'Platform/BundleResolver.swift', group: shared_platform },
  { path: 'Platform/PlatformConstants.swift', group: shared_platform },
  { path: 'Platform/FlowMetadataProvider.swift', group: shared_platform },
  # iOS platform resolver
  { path: '../Xavier/Platform/IOSBundleResolver.swift', group: shared_platform },
]

shared_source_files.each do |file_info|
  ref = find_or_create_ref(file_info[:group], file_info[:path])
  shared_target.source_build_phase.add_file_reference(ref) unless shared_target.source_build_phase.files.include?(ref)
end

# Add Core Data models as resources
xcdatamodel_ref = main_group.find_subpath('Xavier/XavierDataModel.xcdatamodeld', true)
if xcdatamodel_ref
  shared_target.resources_build_phase.add_file_reference(xcdatamodel_ref) unless shared_target.resources_build_phase.files.include?(xcdatamodel_ref)
end

inspection_model_ref = main_group.find_subpath('Xavier/InspectionModel.xcdatamodeld', true)
if inspection_model_ref
  shared_target.resources_build_phase.add_file_reference(inspection_model_ref) unless shared_target.resources_build_phase.files.include?(inspection_model_ref)
end

# ============================================================
# 2. Add framework dependencies to new targets
# ============================================================

# Add NetworkExtension.framework to filter and proxy extension targets
['NetworkExtension', 'Network'].each do |framework_name|
  framework_ref = main_group.find_subpath("Frameworks/#{framework_name}.framework", true)
  unless framework_ref
    frameworks_group = main_group.find_subpath('Frameworks', true) || main_group.new_group('Frameworks', 'Frameworks')
    framework_ref = frameworks_group.new_system_framework(framework_name)
  end

  [filter_target, proxy_target].each do |target|
    # Add to frameworks build phase
    frameworks_phase = target.frameworks_build_phase
    unless frameworks_phase.files.any? { |f| f.display_name && f.display_name.include?(framework_name) }
      frameworks_phase.add_file_reference(framework_ref)
    end
  end
end

# Add NetworkExtension framework to XavierMac too (for NEFilterManager, NETransparentProxyManager)
ne_framework = main_group.find_subpath('Frameworks/NetworkExtension.framework', true)
unless ne_framework
  frameworks_group = main_group.find_subpath('Frameworks', true) || main_group.new_group('Frameworks', 'Frameworks')
  ne_framework = frameworks_group.new_system_framework('NetworkExtension')
end
mac_frameworks = mac_target.frameworks_build_phase
unless mac_frameworks.files.any? { |f| f.display_name && f.display_name.include?('NetworkExtension') }
  mac_frameworks.add_file_reference(ne_framework)
end

# ============================================================
# 3. Add target dependencies for XavierShared
# ============================================================

# All iOS targets + macOS targets should depend on XavierShared
[xavier_target, xavier_data_target, xavier_control_target, xavier_proxy_target, mac_target, filter_target, proxy_target].each do |target|
  next unless target
  target.add_dependency(shared_target) unless target.dependencies.any? { |d| d.name == 'XavierShared' }
end

# ============================================================
# 4. Add 'Embed System Extensions' copy files phase to XavierMac
# ============================================================

# Create copy files build phase for system extensions
copy_phase = mac_target.new_copy_files_build_phase('Embed System Extensions')
copy_phase.dst_subfolder_spec = '13' # Contents/Library/SystemExtensions

# Add the extension products
filter_product_ref = filter_target.product_reference
proxy_product_ref = proxy_target.product_reference

copy_phase.add_file_reference(filter_product_ref) unless copy_phase.files.include?(filter_product_ref)
copy_phase.add_file_reference(proxy_product_ref) unless copy_phase.files.include?(proxy_product_ref)

# ============================================================
# 5. Add 'Embed Frameworks' phase for XavierShared in XavierMac
# ============================================================

embed_phase = mac_target.new_copy_files_build_phase('Embed Frameworks')
embed_phase.dst_subfolder_spec = '10' # Contents/Frameworks

shared_product_ref = shared_target.product_reference
embed_phase.add_file_reference(shared_product_ref) unless embed_phase.files.include?(shared_product_ref)

# ============================================================
# 6. Add XavierShared as linked framework for extension targets
# ============================================================

[filter_target, proxy_target].each do |target|
  frameworks_phase = target.frameworks_build_phase
  unless frameworks_phase.files.any? { |f| f.display_name && f.display_name.include?('XavierShared') }
    frameworks_phase.add_file_reference(shared_product_ref)
  end
end

project.save

puts "Successfully configured targets:"
puts "  - Added shared source files to XavierShared"
puts "  - Added NetworkExtension.framework to Filter and Proxy extensions"
puts "  - Added Network.framework to Filter and Proxy extensions"
puts "  - Added NetworkExtension.framework to XavierMac"
puts "  - Added XavierShared dependency to all targets"
puts "  - Added 'Embed System Extensions' phase to XavierMac"
puts "  - Added 'Embed Frameworks' phase for XavierShared in XavierMac"
puts ""
puts "REMAINING MANUAL STEPS IN XCODE:"
puts "  1. Open project and verify all targets compile"
puts "  2. Check that file paths resolve correctly (may need to fix paths)"
puts "  3. Add 'import XavierShared' to iOS files that use shared code"
puts "  4. Verify Core Data model bundle loading works with XavierShared"
puts "  5. Configure signing & capabilities for each macOS target"
puts "  6. Add SwiftCertificates local package dependency to XavierShared"