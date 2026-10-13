#!/bin/zsh
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT_DIR/build"
xcrun swiftc -swift-version 6 -module-cache-path "$ROOT_DIR/build/ModuleCache.noindex" \
  "$ROOT_DIR/Shared/NewFileKind.swift" \
  "$ROOT_DIR/Shared/MenuLayout.swift" \
  "$ROOT_DIR/MenuWish/NewFileCreator.swift" \
  "$ROOT_DIR/MenuWish/UpdateChecker.swift" \
  "$ROOT_DIR/MenuWish/AppDisplayLocation.swift" \
  "$ROOT_DIR/Tests/FeatureChecks.swift" -o "$ROOT_DIR/build/feature-checks"
"$ROOT_DIR/build/feature-checks" "$ROOT_DIR"
xcrun swiftc -swift-version 6 -module-cache-path "$ROOT_DIR/build/ModuleCache.noindex" \
  "$ROOT_DIR/MenuWish/UpdateChecker.swift" \
  "$ROOT_DIR/MenuWish/ReleaseNotesView.swift" \
  "$ROOT_DIR/Tests/AppKitChecks.swift" -o "$ROOT_DIR/build/appkit-checks"
"$ROOT_DIR/build/appkit-checks"
