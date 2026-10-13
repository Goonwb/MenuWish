#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
BUILD_APP_NAME="MenuWish.app"
INSTALL_APP_NAME="MenuWish.app"
APP_PATH="$BUILD_DIR/Build/Products/Release/$BUILD_APP_NAME"
INSTALL_PATH="/Applications/$INSTALL_APP_NAME"
LEGACY_INSTALL_PATH="/Applications/RightMenuMini.app"
EXTENSION_ID="com.codex.RightMenuMini.FinderExtension"
EXTENSION_PATH="$INSTALL_PATH/Contents/PlugIns/MenuWishFinderExtension.appex"

xcodebuild -quiet \
  -project "$ROOT_DIR/MenuWish.xcodeproj" \
  -scheme MenuWish \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGN_STYLE="Manual" \
  build

/usr/bin/killall RightMenuMini || true
/usr/bin/killall RightMenuMiniFinderExtension || true
/usr/bin/killall MenuWish || true
/usr/bin/killall MenuWishFinderExtension || true
rm -rf "$INSTALL_PATH"
rm -rf "$LEGACY_INSTALL_PATH"
cp -R "$APP_PATH" "$INSTALL_PATH"

/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -f -R -trusted "$INSTALL_PATH"

/usr/bin/pluginkit -m -A -v -p com.apple.FinderSync -i "$EXTENSION_ID" 2>/dev/null | while IFS=$'\t' read -r _ _ _ REGISTERED_EXTENSION_PATH; do
  if [[ -n "$REGISTERED_EXTENSION_PATH" && "$REGISTERED_EXTENSION_PATH" != "$EXTENSION_PATH" ]]; then
    /usr/bin/pluginkit -r "$REGISTERED_EXTENSION_PATH" || true
  fi
done

/usr/bin/pluginkit -a "$EXTENSION_PATH"
/usr/bin/pluginkit -r "$APP_PATH/Contents/PlugIns/MenuWishFinderExtension.appex" || true
/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -u "$APP_PATH" || true
open "$INSTALL_PATH"
/usr/bin/killall Finder || true

echo "Installed: $INSTALL_PATH"
echo "Finder extension: $EXTENSION_ID"
echo "If the menu is not visible yet, click the app's 初次授予权限 button and enable MenuWish in the 文件提供程序 sheet."
