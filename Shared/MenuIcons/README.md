# MenuWish action icons

One 24 × 24 grid, 1.5-unit strokes, rounded ends and corners. The app and Finder extension share these SVG sources. Menu icons are 16 pt with 1× and 2× representations.

All custom artwork is rasterized into sRGB RGBA bitmaps. Colored settings icons have their tint baked into the pixels rather than relying on template tinting in `NSImageView`; template callers also use RGBA instead of gray + alpha contexts. This avoids a separate grayscale SVG rendering path. Local rendering checks passed on macOS 15.7.9; the reporter confirmed that the test build restored the missing icons on the affected colleague’s Mac (reported as macOS 27).

The host app keeps colored preference rows and reorder dialogs using the shared `MenuWishAssets.actionColor` palette: neutral gray for Text, indigo for Markdown, green for Numbers, orange for Pages, blue for Keynote and Copy Path, and teal for Terminal.

Finder menus and the host menu-layout preview deliberately use monochrome artwork. `finderMenuImage` resolves black for the system's light appearance and white for dark appearance when each menu opens, including the MenuWish parent icon. The RGB pixels and transparency are baked into 1× and 2× TIFF representations; the cache distinguishes resolved foreground colors. App-specific appearance preferences do not determine the Finder icon color.

On macOS 15.7.9, FinderSync transmits TIFF bitmap data and drops `NSImage.isTemplate`. Template images and SF Symbols therefore do not reliably turn white on hover. The public menu API does not forward custom view or hover handling. This fallback removes hue collisions with the system accent but does not implement selected-state recoloring, and cannot guarantee contrast for every accent/background combination. Do not claim full hover or theme compatibility from host previews or bitmap tests; inspect the real Finder menu for those cases.

Six icons are from the MIT-licensed Hugeicons Stroke Rounded set, retrieved 2026-09-28 from https://github.com/hugeicons/hugeicons/tree/main/icons. Original artwork is unmodified. The bundled LICENSE-Hugeicons.txt applies to these files:

| MenuWish file | Hugeicons source |
| --- | --- |
| text.svg | file-02.svg |
| numbers.svg | grid-table.svg |
| pages.svg | file-edit.svg |
| keynote.svg | presentation-01.svg |
| terminal.svg | command-line.svg |
| copy-path.svg | link-04.svg |

markdown.svg is a MenuWish drawing of M + down arrow, using the same grid and stroke specification. The existing MenuWish sparkle brand mark is preserved separately.

After a Release build, verify monochrome TIFF transport and light/dark cache isolation with:

```zsh
xcrun swiftc -swift-version 6 -module-cache-path build/ModuleCache.noindex Shared/MenuWishAssets.swift Tests/FinderIconChecks.swift -o build/finder-icon-checks
build/finder-icon-checks build/Build/Products/Release/MenuWishFinderExtension.appex
```

These checks do not simulate Finder highlight backgrounds or replace visual theme testing.
