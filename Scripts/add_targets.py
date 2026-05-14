#!/usr/bin/env python3
"""Add XavierShared framework, XavierMac app, XavierMacFilterExtension, 
and XavierMacProxyExtension targets to the Xcode project.

This script assumes source files already exist on disk and adds targets 
with proper build phases, configurations, and entitlements.
"""

import sys
import os

sys.path.insert(0, os.path.expanduser("~/.local/lib/python3.13/site-packages"))
try:
    from pbxproj import XcodeProject
except ImportError:
    from pbxproj import XcodeProject

PROJECT_PATH = "/Users/bogdan/DEV/xavier-ios/Xavier.xcodeproj/project.pbxproj"

project = XcodeProject.load(PROJECT_PATH)

# ============================================================
# 1. Add XavierShared Framework target
# ============================================================
# We'll add source files as groups and build file references first,
# then create the target.

# The pbxproj library has limited target creation support,
# so we'll add targets using its add_target method if available.
# Otherwise we'll need to modify the project structure directly.

# Check what methods are available
print("Available XcodeProject methods for target creation:")
methods = [m for m in dir(project) if not m.startswith('_') and 'target' in m.lower() or 'add' in m.lower()]
for m in sorted(methods):
    print(f"  {m}")

# Let's see what the project structure looks like
print("\nCurrent targets:")
for target in project.objects.get_targets():
    print(f"  {target.name} ({target.productType})")

print("\nDone checking. The actual target creation requires careful pbxproj manipulation.")
print("This script will be expanded to add the targets programmatically.")