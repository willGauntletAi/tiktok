#!/bin/bash

# Kill any existing watch processes
pkill -f "fswatch.*project.json"

# Start the watch script in the background
./watch.sh &

echo "🎯 XcodeGen watcher started in background (PID: $!)"
echo "To stop watching, run: pkill -f \"fswatch.*project.json\"" 