#!/usr/bin/env python3
"""
Script to configure Xcode project for XCFramework integration
This script modifies the project.pbxproj file to use XCFramework instead of static library
"""

import os
import re
import sys
import json

def configure_xcode_project():
    project_path = "/Users/nikitakrivonosov/Documents/DJVUReader-iOS/DJVUReader-iOS.xcodeproj/project.pbxproj"
    
    if not os.path.exists(project_path):
        print(f"❌ Project file not found: {project_path}")
        return False
    
    print(f"📝 Configuring Xcode project for XCFramework: {project_path}")
    
    # Read the project file
    with open(project_path, 'r') as f:
        content = f.read()
    
    # Backup the original
    backup_path = project_path + ".xcframework_backup"
    with open(backup_path, 'w') as f:
        f.write(content)
    print(f"💾 Created backup: {backup_path}")
    
    modified = False
    
    # Remove old static library references
    old_lib_patterns = [
        r'[^\n]*libdjvulibre\.a[^\n]*\n',
        r'[^\n]*libdjvulibre_simulator\.a[^\n]*\n',
    ]
    
    for pattern in old_lib_patterns:
        if re.search(pattern, content):
            content = re.sub(pattern, '', content)
            modified = True
            print("✅ Removed old static library references")
    
    # Update header search paths to point to XCFramework
    header_pattern = r'HEADER_SEARCH_PATHS = [^;]*;'
    xcframework_header_path = '"$(SRCROOT)/DJVUReader-iOS/LibDJVU/libdjvulibre.xcframework/ios-arm64/libdjvulibre.framework/Headers"'
    
    if re.search(header_pattern, content):
        content = re.sub(
            header_pattern,
            f'HEADER_SEARCH_PATHS = {xcframework_header_path};',
            content
        )
        modified = True
        print("✅ Updated HEADER_SEARCH_PATHS for XCFramework")
    else:
        # Add header search paths
        settings_pattern = r'(buildSettings = \{[^}]*?);'
        def add_header_search_paths(match):
            return match.group(1) + f'\n\t\t\t\tHEADER_SEARCH_PATHS = {xcframework_header_path};'
        
        content = re.sub(settings_pattern, add_header_search_paths, content, flags=re.MULTILINE | re.DOTALL)
        modified = True
        print("✅ Added HEADER_SEARCH_PATHS for XCFramework")
    
    # Remove LIBRARY_SEARCH_PATHS since XCFramework doesn't need it
    lib_search_pattern = r'LIBRARY_SEARCH_PATHS = [^;]*;\n'
    if re.search(lib_search_pattern, content):
        content = re.sub(lib_search_pattern, '', content)
        modified = True
        print("✅ Removed LIBRARY_SEARCH_PATHS (not needed for XCFramework)")
    
    # Update OTHER_LDFLAGS to use framework linking
    ldflags_pattern = r'OTHER_LDFLAGS = [^;]*;'
    xcframework_ldflags = '"-framework libdjvulibre"'
    
    if re.search(ldflags_pattern, content):
        content = re.sub(
            ldflags_pattern,
            f'OTHER_LDFLAGS = {xcframework_ldflags};',
            content
        )
        modified = True
        print("✅ Updated OTHER_LDFLAGS for XCFramework")
    else:
        # Add ldflags
        settings_pattern = r'(buildSettings = \{[^}]*?);'
        def add_ldflags(match):
            return match.group(1) + f'\n\t\t\t\tOTHER_LDFLAGS = {xcframework_ldflags};'
        
        content = re.sub(settings_pattern, add_ldflags, content, flags=re.MULTILINE | re.DOTALL)
        modified = True
        print("✅ Added OTHER_LDFLAGS for XCFramework")
    
    # Add FRAMEWORK_SEARCH_PATHS
    framework_search_path = '"$(SRCROOT)/DJVUReader-iOS/LibDJVU"'
    if 'FRAMEWORK_SEARCH_PATHS' not in content:
        settings_pattern = r'(buildSettings = \{[^}]*?);'
        def add_framework_search_paths(match):
            return match.group(1) + f'\n\t\t\t\tFRAMEWORK_SEARCH_PATHS = {framework_search_path};'
        
        content = re.sub(settings_pattern, add_framework_search_paths, content, flags=re.MULTILINE | re.DOTALL)
        modified = True
        print("✅ Added FRAMEWORK_SEARCH_PATHS")
    
    if modified:
        # Write the modified content back
        with open(project_path, 'w') as f:
            f.write(content)
        print("✅ Project configuration updated for XCFramework")
        
        print("\n🎯 Next steps:")
        print("1. Open the project in Xcode")
        print("2. Drag libdjvulibre.xcframework into the project if not already added")
        print("3. Make sure to select 'Embed & Sign' for the XCFramework")
        print("4. Build and test on both simulator and device")
        
        return True
    else:
        print("ℹ️  No changes needed - project already configured for XCFramework")
        return True

if __name__ == "__main__":
    success = configure_xcode_project()
    sys.exit(0 if success else 1)