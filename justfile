# Available recipes

# List all recipes
default:
    @just --list

# Install dependencies for cloud functions
functions-install:
    cd functions && npm install

# Build cloud functions
functions-build: functions-install
    cd functions && npx tsc

# Deploy cloud functions
functions-deploy: functions-build
    firebase deploy --only functions

# Build the iOS app for distribution (Release configuration)
app-build:
    mkdir -p build
    cd tiktok && \
    xcodebuild -scheme tiktok -configuration Release \
        -sdk iphoneos \
        -destination 'generic/platform=iOS' \
        -archivePath ../build/TikTok.xcarchive archive
    cd tiktok && \
    xcodebuild -exportArchive -archivePath ../build/TikTok.xcarchive \
        -exportPath ../build/IPA -exportOptionsPlist exportOptions.plist

# Distribute the built app using Firebase App Distribution
app-distribute:
    firebase appdistribution:distribute "build/IPA/TikTok.ipa" \
        --app "1:6721320910:ios:0a0da698536697f95d9d9f" \
        --groups "testers" \
        --release-notes "New app version"

# Build and distribute the app
app-release: app-build app-distribute
    @echo "App release complete!"

# Deploy both functions and app
deploy-all: functions-deploy app-release
    @echo "Deployment complete!" 
