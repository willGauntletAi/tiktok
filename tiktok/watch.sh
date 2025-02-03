#!/bin/bash

# Check if fswatch is installed
if ! command -v fswatch &> /dev/null; then
    echo "fswatch is not installed. Installing via Homebrew..."
    brew install fswatch
fi

# Check if xcodegen is installed
if ! command -v xcodegen &> /dev/null; then
    echo "xcodegen is not installed. Installing via Homebrew..."
    brew install xcodegen
fi

# Function to run xcodegen
run_xcodegen() {
    echo "📁 File change detected. Regenerating Xcode project..."
    if xcodegen generate --spec project.json; then
        echo "✅ Project regenerated successfully"
    else
        echo "❌ Failed to regenerate project"
        return 1
    fi
}

# Function to handle file changes
handle_file_change() {
    local file_path="$1"
    local event_type="$2"
    
    echo "🔄 File change detected:"
    echo "   Path: $file_path"
    echo "   Event: $event_type"
    
    # Check if it's project.json being modified
    if [[ "$file_path" == *"project.json" ]]; then
        echo "   Type: Project configuration file"
    else
        echo "   Type: Project source file"
    fi
    
    run_xcodegen
}

# Initial generation
echo "🚀 Initial project generation..."
if ! run_xcodegen; then
    echo "❌ Initial project generation failed. Exiting..."
    exit 1
fi

# Watch for changes in the project directory
echo "👀 Watching for file changes..."

# Watch project.json for all relevant changes including modifications
fswatch -o \
    --event Created \
    --event Updated \
    --event Removed \
    --event Renamed \
    --event MovedFrom \
    --event MovedTo \
    ./project.json \
    | while read file_path event_flags event_type
    do
        handle_file_change "$file_path" "$event_type"
    done &

# Watch project files for structural changes
fswatch -o \
    --event Created \
    --event Removed \
    --event Renamed \
    --event MovedFrom \
    --event MovedTo \
    ./tiktok \
    | while read file_path event_flags event_type
    do
        handle_file_change "$file_path" "$event_type"
    done 
