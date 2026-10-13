#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="MenuWish.app"
DIST_APP_NAME="MenuWish.app"
APP_PATH="$BUILD_DIR/Build/Products/Release/$APP_NAME"

echo "Building Release..."
xcodebuild -quiet \
  -project "$ROOT_DIR/MenuWish.xcodeproj" \
  -scheme MenuWish \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGN_STYLE="Manual" \
  build

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist")
ZIP_PATH="$DIST_DIR/MenuWish-${VERSION}.zip"
DMG_PATH="$DIST_DIR/MenuWish-${VERSION}.dmg"
mkdir -p "$DIST_DIR"
STAGING_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGING_DIR"' EXIT

echo "Staging $DIST_APP_NAME..."
cp -R "$APP_PATH" "$STAGING_DIR/$DIST_APP_NAME"
codesign --verify --deep --strict "$STAGING_DIR/$DIST_APP_NAME"

echo "Creating $ZIP_PATH..."
ditto -c -k --sequesterRsrc --keepParent "$STAGING_DIR/$DIST_APP_NAME" "$STAGING_DIR/MenuWish.zip"

# Keep packaging dependencies local to build/; no global Python changes.
PACKAGE_ENV="$BUILD_DIR/package-venv"
if [[ ! -x "$PACKAGE_ENV/bin/python3" ]]; then
  "${PYTHON3:-python3}" -m venv "$PACKAGE_ENV"
fi
"$PACKAGE_ENV/bin/python3" -m pip install --disable-pip-version-check -q -r "$ROOT_DIR/Scripts/requirements-package.txt"
xcrun swift -module-cache-path "$BUILD_DIR/ModuleCache.noindex" \
  "$ROOT_DIR/Scripts/generate-dmg-background.swift" "$STAGING_DIR/background.tiff"
xcrun swiftc -module-cache-path "$BUILD_DIR/ModuleCache.noindex" \
  "$ROOT_DIR/Scripts/dmg-background-bookmark.swift" -o "$STAGING_DIR/background-bookmark"

echo "Creating drag-to-Applications installer..."
"$PACKAGE_ENV/bin/python3" "$ROOT_DIR/Scripts/build-dmg.py" \
  "$STAGING_DIR/$DIST_APP_NAME" "$STAGING_DIR/background.tiff" \
  "$APP_PATH/Contents/Resources/AppIcon2026Corners.icns" \
  "$STAGING_DIR/background-bookmark" "$VERSION" "$STAGING_DIR/MenuWish.dmg"
hdiutil verify "$STAGING_DIR/MenuWish.dmg"
mv -f "$STAGING_DIR/MenuWish.zip" "$ZIP_PATH"
mv -f "$STAGING_DIR/MenuWish.dmg" "$DMG_PATH"

echo "Packages created successfully:"
ls -lh "$DMG_PATH" "$ZIP_PATH"
