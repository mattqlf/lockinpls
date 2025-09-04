#!/bin/bash

# Create DMG script for LockinPls
# This script builds the app in Release configuration and creates a DMG for distribution

APP_NAME="lockinpls"
DMG_NAME="LockinPls-1.0"
BUILD_DIR="build/Release"
DMG_STAGING_DIR="dmg_staging"
FINAL_DMG_PATH="${DMG_NAME}.dmg"

echo "🧹 Cleaning previous builds..."
rm -rf "${BUILD_DIR}"
rm -rf "${DMG_STAGING_DIR}"
rm -f "${FINAL_DMG_PATH}"

echo "🔨 Building ${APP_NAME} in Release configuration..."
xcodebuild -project "${APP_NAME}.xcodeproj" -scheme "${APP_NAME}" -configuration Release -derivedDataPath build clean build

if [ $? -ne 0 ]; then
    echo "❌ Build failed!"
    exit 1
fi

echo "📦 Creating DMG staging directory..."
mkdir -p "${DMG_STAGING_DIR}"

# Copy the built app to staging directory  
APP_PATH="build/Build/Products/Release/${APP_NAME}.app"
if [ ! -d "${APP_PATH}" ]; then
    echo "❌ App not found at ${APP_PATH}!"
    exit 1
fi

cp -r "${APP_PATH}" "${DMG_STAGING_DIR}/"

# Create a symlink to Applications
ln -sf /Applications "${DMG_STAGING_DIR}/Applications"

echo "💿 Creating DMG..."
# Create the DMG
hdiutil create -volname "LockinPls" -srcfolder "${DMG_STAGING_DIR}" -ov -format UDZO "${FINAL_DMG_PATH}"

if [ $? -eq 0 ]; then
    echo "✅ DMG created successfully: ${FINAL_DMG_PATH}"
    
    # Get file size
    DMG_SIZE=$(du -h "${FINAL_DMG_PATH}" | cut -f1)
    echo "📊 DMG size: ${DMG_SIZE}"
    
    echo ""
    echo "🚀 Distribution ready!"
    echo "📄 File: ${FINAL_DMG_PATH}"
    echo ""
    echo "📋 User Installation Instructions:"
    echo "1. Double-click the DMG file to mount it"
    echo "2. Drag LockinPls.app to the Applications folder"
    echo "3. First time opening: Right-click the app and select 'Open'"
    echo "   (This bypasses the 'unidentified developer' warning)"
    echo "4. Click 'Open' in the security dialog"
    echo "5. The app will now open normally for future use"
    
else
    echo "❌ Failed to create DMG!"
    exit 1
fi

echo "🧹 Cleaning up staging directory..."
rm -rf "${DMG_STAGING_DIR}"

echo "✨ Done! Your app is ready for distribution."