#!/usr/bin/env python3
"""
Script to configure conditional linking for different iOS platforms
This allows using different libraries for device vs simulator
"""

import os
import sys

def configure_xcode_project():
    project_path = "/Users/nikitakrivonosov/Documents/DJVUReader-iOS/DJVUReader-iOS.xcodeproj/project.pbxproj"
    
    if not os.path.exists(project_path):
        print(f"❌ Project file not found: {project_path}")
        return False
    
    print(f"📝 Configuring conditional linking: {project_path}")
    
    # Read the project file
    with open(project_path, 'r') as f:
        content = f.read()
    
    # Backup the original
    backup_path = project_path + ".conditional_backup"
    with open(backup_path, 'w') as f:
        f.write(content)
    print(f"💾 Created backup: {backup_path}")
    
    # Replace OTHER_LDFLAGS to use conditional linking
    debug_pattern = 'OTHER_LDFLAGS = (\n\t\t\t\t\t"$(inherited)",\n\t\t\t\t\t"-ldjvulibre",\n\t\t\t\t);'
    release_pattern = 'OTHER_LDFLAGS = (\n\t\t\t\t\t"$(inherited)",\n\t\t\t\t\t"-ldjvulibre",\n\t\t\t\t);'
    
    conditional_ldflags = '''OTHER_LDFLAGS = (
					"$(inherited)",
					"$(DJVU_LIBRARY_FLAG)",
				);'''
    
    # Replace for both Debug and Release configurations
    if debug_pattern in content:
        content = content.replace(debug_pattern, conditional_ldflags)
        print("✅ Updated Debug OTHER_LDFLAGS")
    
    if release_pattern in content:
        content = content.replace(release_pattern, conditional_ldflags)
        print("✅ Updated Release OTHER_LDFLAGS")
    
    # Add user-defined build settings section before the existing buildSettings
    debug_build_start = 'E0C520F82DF4C8C7009D84A3 /* Debug */ = {\n\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = {'
    release_build_start = 'E0C520F92DF4C8C7009D84A3 /* Release */ = {\n\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = {'
    
    # Add DJVU_LIBRARY_FLAG setting for Debug
    debug_replacement = '''E0C520F82DF4C8C7009D84A3 /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				"DJVU_LIBRARY_FLAG[sdk=iphoneos*]" = "-ldjvulibre_device";
				"DJVU_LIBRARY_FLAG[sdk=iphonesimulator*]" = "-ldjvulibre_simulator";'''
    
    # Add DJVU_LIBRARY_FLAG setting for Release  
    release_replacement = '''E0C520F92DF4C8C7009D84A3 /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				"DJVU_LIBRARY_FLAG[sdk=iphoneos*]" = "-ldjvulibre_device";
				"DJVU_LIBRARY_FLAG[sdk=iphonesimulator*]" = "-ldjvulibre_simulator";'''
    
    if debug_build_start in content:
        content = content.replace(debug_build_start, debug_replacement)
        print("✅ Added conditional library flags for Debug")
    
    if release_build_start in content:
        content = content.replace(release_build_start, release_replacement)
        print("✅ Added conditional library flags for Release")
    
    # Write the modified content back
    with open(project_path, 'w') as f:
        f.write(content)
    
    print("✅ Project configured for conditional linking")
    print("\n📚 Libraries created:")
    print("- libdjvulibre_device.a: For iOS Device (arm64)")
    print("- libdjvulibre_simulator.a: For iOS Simulator (arm64 + x86_64)")
    print("\n🎯 The project will now automatically select the correct library!")
    
    return True

if __name__ == "__main__":
    success = configure_xcode_project()
    sys.exit(0 if success else 1)