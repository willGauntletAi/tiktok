#!/bin/bash

# Navigate to the project directory
cd tiktok

# Add new files to the project
for file in tiktok/Views/*.swift tiktok/Models/*.swift tiktok/ViewModels/*.swift; do
    if [ -f "$file" ]; then
        echo "Adding $file to project..."
        /usr/libexec/PlistBuddy -c "Add :objects:$(uuidgen):isa string PBXFileReference" tiktok.xcodeproj/project.pbxproj
        /usr/libexec/PlistBuddy -c "Add :objects:$(uuidgen):fileRef string $(basename $file)" tiktok.xcodeproj/project.pbxproj
        /usr/libexec/PlistBuddy -c "Add :objects:$(uuidgen):path string $(basename $file)" tiktok.xcodeproj/project.pbxproj
    fi
done 