import AppKit

@main
struct AppKitChecks {
    static func require(_ value: @autoclosure () -> Bool, _ message: String) {
        precondition(value(), message)
    }

    @MainActor static func main() {
        _ = NSApplication.shared
        let page = URL(string: "https://github.com/Goonwb/MenuWish/releases/tag/v0.1.3")!
        let markdown = "Introduction\r\n\r\n\r\n## Changes\r\n\r\n\r\n- **分类与排序**：中文与 emoji 🎉\r\n- [Release page](https://github.com/Goonwb/MenuWish/releases)\r\n\r\n---\r\n\r\n## 更新内容\r\n- 中文说明"
        let short = ReleaseNotesView(release: ReleaseDetails(version: "v0.1.3", page: page, notes: markdown), isEnglish: false)
        let shortScroll = short.subviews.compactMap { $0 as? NSScrollView }.first!
        let shortText = shortScroll.documentView as! NSTextView
        require(!shortText.string.contains("\n\n"), "Source blank lines became empty visual paragraphs")
        require(!shortText.string.contains("\r"), "CRLF caused extra paragraphs")
        require(shortText.string.contains("分类与排序") && shortText.string.contains("🎉"), "Unicode release notes were damaged")
        var hasLink = false
        let content = shortText.attributedString()
        content.enumerateAttribute(.link, in: NSRange(location: 0, length: content.length)) { value, _, _ in
            if value != nil { hasLink = true }
        }
        require(hasLink, "The release page link was lost")
        require(shortText.string.contains("Release page\n\u{FFFC}\n更新内容"),
            "The bilingual divider was lost or rendered as literal Markdown")
        let headingIndex = (content.string as NSString).range(of: "更新内容").location
        let headingFont = content.attribute(.font, at: headingIndex, effectiveRange: nil) as! NSFont
        let bodyFont = content.attribute(.font, at: 0, effectiveRange: nil) as! NSFont
        require(headingFont.pointSize > bodyFont.pointSize, "Headings are indistinguishable from body text")

        let rules = ReleaseNotesView(release: ReleaseDetails(version: "v1.0", page: page,
            notes: "---\n***\n___\n- - -\n*\t*\t*\n_ _ _\n- Ordinary list\n**Bold text**"), isEnglish: false)
        let rulesText = rules.subviews.compactMap { $0 as? NSScrollView }.first!.documentView as! NSTextView
        var ruleCount = 0
        let rulesContent = rulesText.attributedString()
        rulesContent.enumerateAttribute(.attachment, in: NSRange(location: 0, length: rulesContent.length)) { value, range, _ in
            guard let attachment = value as? NSTextAttachment, let cell = attachment.attachmentCell else { return }
            ruleCount += 1
            require(cell.cellSize().width == rulesText.textContainer!.containerSize.width,
                "The divider does not match the text width")
            let glyphs = rulesText.layoutManager!.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let bounds = rulesText.layoutManager!.boundingRect(forGlyphRange: glyphs, in: rulesText.textContainer!)
            require(bounds.minX >= 0 && bounds.maxX <= rulesText.textContainer!.containerSize.width,
                "The divider extends beyond the text container")
            require(bounds.height < 20, "The divider introduced an oversized blank row")
        }
        require(ruleCount == 6, "Markdown thematic-break variants were not rendered")
        require(rulesText.string.contains("•\tOrdinary list") && rulesText.string.contains("Bold text"),
            "A list item or inline emphasis was mistaken for a divider")

        let long = ReleaseNotesView(release: ReleaseDetails(version: "v0.1.3", page: page,
            notes: Array(repeating: markdown, count: 100).joined(separator: "\n\n")), isEnglish: false)
        let scroll = long.subviews.compactMap { $0 as? NSScrollView }.first!
        let text = scroll.documentView as! NSTextView
        let height = text.frame.height
        require(height > scroll.contentSize.height, "Long notes have no scroll range")
        let start = CFAbsoluteTimeGetCurrent()
        for index in 0..<300 {
            let y = CGFloat(index % 100) / 99 * (height - scroll.contentSize.height)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
            scroll.reflectScrolledClipView(scroll.contentView)
            text.layoutManager!.ensureLayout(for: text.textContainer!)
            require(text.frame.height == height, "The document height changes during scrolling")
        }
        require(ceil(text.layoutManager!.usedRect(for: text.textContainer!).height) + 20 <= height,
            "The final paragraph is clipped")
        print("PASS: compact formatting, Unicode and links, bilingual dividers and heading hierarchy, fixed document height across 300 scroll positions (\(Int((CFAbsoluteTimeGetCurrent() - start) * 1000)) ms)")
    }
}
