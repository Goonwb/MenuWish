<p align="center">
  <img src="docs/images/menuwish-icon.png" width="112" alt="MenuWish icon">
</p>

<h1 align="center">MenuWish</h1>

<p align="center">
  <strong>Make your Finder right-click as you wish.</strong>
</p>

<p align="center">
  A lightweight macOS extension for New Text, Terminal &amp; Copy Path.
</p>

<p align="center">
  <strong>中文：</strong>轻量开源的 Mac Finder 菜单增强：新建文本、进入终端、拷贝路径。
</p>

<p align="center">
  <a href="README.md">English</a>
  |
  <a href="README.zh-CN.md">中文</a>
</p>

<p align="center">
  <a href="LICENSE">MIT License</a>
  ·
  <a href="https://github.com/Goonwb">Author</a>
</p>

## Why MenuWish?

Finder does not include a direct **New Text File** action in its context menu, while opening the current folder in Terminal or copying a full path often takes extra steps. MenuWish adds these focused shortcuts directly to the macOS Finder right-click menu through a native Finder Sync extension.

## Features

MenuWish keeps the Finder context menu focused on these everyday actions:

- **New Text**: create an empty `Untitled.txt` in the current Finder folder. Duplicate names are numbered automatically.
- **New Markdown**: create an empty `Untitled.md`.
- **New Numbers Spreadsheet / Pages Document / Keynote Presentation**: create native `.numbers`, `.pages`, and `.key` files from bundled blank templates, with automatic numbering for duplicate names.
- **Open Terminal**: open Terminal at the current Finder location.
- **Copy Path**: copy selected item paths, or copy the current folder path when nothing is selected.

The app supports:

- A master switch for the Finder context menu.
- Individual switches for each action.
- Menu display: Flat, Combined in one MenuWish submenu, or Categories with separate New Files and Tools submenus. Empty categories are hidden.
- Action grouping and order: one card for New Files and Tools. Category mode supports dragging category headers and using arrows to reorder actions within each category; Flat and Combined keep the global action order. Click a category in the preview to inspect its submenu.
- Manual update checking from GitHub Releases with native macOS result dialogs and scrollable release notes.
- Language support: follows the system, with Simplified Chinese, Traditional Chinese, and English localization.
- Appearance selection: System, Light, or Dark.
- Display location: Menu Bar Only (default), Dock Only, or Menu Bar & Dock. Changes take effect immediately and do not disable Finder actions.

## Screenshots

<p align="center">
  <img src="docs/images/general-en.webp" alt="MenuWish general settings" width="820">
</p>

<p align="center">
  <img src="docs/images/actions-en.webp" alt="MenuWish actions settings" width="820">
</p>

## Requirements

- macOS 13.0 or later
- Xcode 15 or later for building from source

## Installer

Open the MenuWish `.dmg`, drag **MenuWish** into **Applications**, then launch it from Applications.

Run `./Scripts/package.sh` to create `dist/MenuWish-<version>.dmg` and a ZIP fallback. Packaging requires Python 3.9 or later; the first run downloads pinned build dependencies into `build/package-venv`.

## Install From Source

```zsh
chmod +x Scripts/install-local.sh
./Scripts/install-local.sh
```

The script builds the Release app, copies it to `/Applications`, registers the Finder extension, and restarts Finder.

## Build Manually

```zsh
xcodebuild \
  -project RightMenuMini.xcodeproj \
  -scheme RightMenuMini \
  -configuration Release \
  -derivedDataPath build \
  build

open build/Build/Products/Release/RightMenuMini.app
```

## First-Time Permission

MenuWish uses Apple's Finder Sync extension mechanism. macOS requires users to enable Finder extensions manually:

1. Open MenuWish.
2. Click **Authorize**.
3. Enable **MenuWish** in the **File Provider** extension sheet.

Before permission is granted, all switches are shown as off and disabled. After permission is enabled, the app restores the default or saved settings.

## Notes

- Current version: `0.1.4`.
- Creating iWork files does not launch the corresponding app; opening and editing requires Numbers, Pages, or Keynote. Templates were created with version 26.3.1; compatibility with older iWork versions is not yet verified.
- The distributed app is not notarized yet. Users may need to allow it manually in macOS security settings.

## License

MenuWish is released under the [MIT License](LICENSE).

Action icons use the MIT-licensed [Hugeicons Stroke Rounded](https://github.com/hugeicons/hugeicons) set and a matching MenuWish Markdown icon. See [icon sources and attribution](Shared/MenuIcons/README.md).
