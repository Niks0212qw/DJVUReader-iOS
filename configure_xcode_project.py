#!/usr/bin/env python3
"""
Script to configure Xcode project for djvulibre integration
This script modifies the project.pbxproj file to include the djvulibre library and headers
"""

import os
import re
import sys

def configure_xcode_project():
    project_path = "/Users/nikitakrivonosov/Documents/DJVUReader-iOS/DJVUReader-iOS.xcodeproj/project.pbxproj"
    
    if not os.path.exists(project_path):
        print(f"❌ Project file not found: {project_path}")
        return False
    
    print(f"📝 Configuring Xcode project: {project_path}")
    
    # Read the project file
    with open(project_path, 'r') as f:
        content = f.read()
    
    # Backup the original
    backup_path = project_path + ".backup"
    with open(backup_path, 'w') as f:
        f.write(content)
    print(f"💾 Created backup: {backup_path}")
    
    # Find the build settings sections
    modified = False
    
    # Add header search paths
    if 'HEADER_SEARCH_PATHS' not in content:
        # Find build settings section and add header search paths
        settings_pattern = r'(buildSettings = \{[^}]*?);'
        def add_header_search_paths(match):
            return match.group(1) + '\n\t\t\t\tHEADER_SEARCH_PATHS = "$(SRCROOT)/DJVUReader-iOS/LibDJVU/include";'
        
        content = re.sub(settings_pattern, add_header_search_paths, content, flags=re.MULTILINE | re.DOTALL)
        modified = True
        print("✅ Added HEADER_SEARCH_PATHS")
    else:
        # Update existing header search paths
        header_pattern = r'(HEADER_SEARCH_PATHS = [^;]*);'
        if re.search(header_pattern, content):
            content = re.sub(
                header_pattern,
                r'\1,\n\t\t\t\t"$(SRCROOT)/DJVUReader-iOS/LibDJVU/include";',
                content
            )
            modified = True
            print("✅ Updated HEADER_SEARCH_PATHS")
    
    # Add library search paths
    if 'LIBRARY_SEARCH_PATHS' not in content:
        settings_pattern = r'(buildSettings = \{[^}]*?);'
        def add_library_search_paths(match):
            return match.group(1) + '\n\t\t\t\tLIBRARY_SEARCH_PATHS = "$(SRCROOT)/DJVUReader-iOS/LibDJVU/lib";'
        
        content = re.sub(settings_pattern, add_library_search_paths, content, flags=re.MULTILINE | re.DOTALL)
        modified = True
        print("✅ Added LIBRARY_SEARCH_PATHS")
    
    # Add linking flags for djvulibre
    if 'OTHER_LDFLAGS' not in content:
        settings_pattern = r'(buildSettings = \{[^}]*?);'
        def add_ldflags(match):
            return match.group(1) + '\n\t\t\t\tOTHER_LDFLAGS = "-ldjvulibre";'
        
        content = re.sub(settings_pattern, add_ldflags, content, flags=re.MULTILINE | re.DOTALL)
        modified = True
        print("✅ Added OTHER_LDFLAGS for djvulibre")
    else:
        # Update existing ldflags
        ldflags_pattern = r'(OTHER_LDFLAGS = [^;]*);'
        if re.search(ldflags_pattern, content) and '-ldjvulibre' not in content:
            content = re.sub(
                ldflags_pattern,
                r'\1,\n\t\t\t\t"-ldjvulibre";',
                content
            )
            modified = True
            print("✅ Updated OTHER_LDFLAGS for djvulibre")
    
    # Add bridging header path if not present
    bridging_header_path = '"DJVUReader-iOS/LibDJVU/DJVUReader-iOS-Bridging-Header.h"'
    if 'SWIFT_OBJC_BRIDGING_HEADER' not in content:
        settings_pattern = r'(buildSettings = \{[^}]*?);'
        def add_bridging_header(match):
            return match.group(1) + f'\n\t\t\t\tSWIFT_OBJC_BRIDGING_HEADER = {bridging_header_path};'
        
        content = re.sub(settings_pattern, add_bridging_header, content, flags=re.MULTILINE | re.DOTALL)
        modified = True
        print("✅ Added SWIFT_OBJC_BRIDGING_HEADER")
    
    if modified:
        # Write the modified content back
        with open(project_path, 'w') as f:
            f.write(content)
        print("✅ Project configuration updated successfully")
        
        print("\n🎯 Next steps:")
        print("1. Open the project in Xcode")
        print("2. Add libdjvulibre.a to the project manually if needed")
        print("3. Build and test the project")
        
        return True
    else:
        print("ℹ️  No changes needed - project already configured")
        return True

if __name__ == "__main__":
    success = configure_xcode_project()
    sys.exit(0 if success else 1)