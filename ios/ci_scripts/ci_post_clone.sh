#!/bin/sh

# Xcode Cloud post-clone script.
# Xcode Cloud's macOS image does not include Flutter, so we install it here
# before Xcode Cloud runs `pod install` / archives the app.
# Docs: https://docs.flutter.dev/deployment/cd#xcode-cloud

set -e

FLUTTER_CHANNEL="stable"

echo "Cloning Flutter ($FLUTTER_CHANNEL)..."
git clone https://github.com/flutter/flutter.git -b "$FLUTTER_CHANNEL" --depth 1 "$HOME/flutter"
export PATH="$PATH:$HOME/flutter/bin"

flutter --version
flutter precache --ios

echo "Fetching Dart packages..."
cd "$CI_PRIMARY_REPOSITORY_PATH"
flutter pub get

echo "Installing CocoaPods dependencies..."
cd ios
pod install

echo "ci_post_clone.sh done."
