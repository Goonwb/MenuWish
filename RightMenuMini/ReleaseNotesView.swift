import AppKit

/// Native, selectable release notes. No web view, scripts, or remote images.
@MainActor
final class ReleaseNotesView: NSView {
    init(release: ReleaseDetails, isEnglish: Bool) {
        let notes: String
        if let body = release.notes {
            notes = body.isEmpty
                ? (isEnglish ? "No release notes were provided for this version." : "本次发布未填写更新说明。")
                : body
        } else {
            notes = isEnglish
                ? "The version was checked, but release notes are temporarily unavailable. Open the release page to read them."
                : "已确认版本信息，暂时无法获取更新明细。可前往发布页面查看。"
        }
        let hasNotes = release.notes?.isEmpty == false
        super.init(frame: NSRect(x: 0, y: 0, width: 450, height: hasNotes ? 300 : 110))

        let title = NSTextField(labelWithString: (isEnglish ? "Release notes · " : "发布日志 · ") + release.version)
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.frame = NSRect(x: 0, y: bounds.height - 22, width: bounds.width, height: 20)
        addSubview(title)

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height - 30))
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.borderType = .bezelBorder
        scroll.wantsLayer = true

        // Lay out this read-only document once, before displaying it. Letting a
        // vertically resizable text view discover its height while scrolling
        // changes the scroll range and produces visible jumps.
        let width = scroll.contentSize.width
        let contentWidth = width - 24
        let storage = NSTextStorage(attributedString: Self.formatted(notes, contentWidth: contentWidth))
        let layout = NSLayoutManager()
        layout.allowsNonContiguousLayout = false
        storage.addLayoutManager(layout)
        let container = NSTextContainer(containerSize: NSSize(width: contentWidth, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        container.widthTracksTextView = false
        container.heightTracksTextView = false
        layout.addTextContainer(container)
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: scroll.contentSize.height), textContainer: container)
        text.isEditable = false
        text.isSelectable = true
        text.isVerticallyResizable = false
        text.isHorizontallyResizable = false
        text.isContinuousSpellCheckingEnabled = false
        text.textContainerInset = NSSize(width: 12, height: 10)
        layout.ensureLayout(for: container)
        text.setFrameSize(NSSize(width: width, height: max(scroll.contentSize.height, ceil(layout.usedRect(for: container).height) + 20)))
        scroll.documentView = text
        addSubview(scroll)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private static func formatted(_ markdown: String, contentWidth: CGFloat) -> NSAttributedString {
        let output = NSMutableAttributedString()
        // Bound display work; the complete original always remains on the release page.
        let body = String(markdown.prefix(40_000)).replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var paragraphBreak = false
        for line in body.components(separatedBy: "\n") {
            var content = line.trimmingCharacters(in: .whitespaces)
            if content.isEmpty {
                paragraphBreak = true
                continue
            }
            // Recognize thematic breaks before list markers or inline Markdown.
            let rule = content.filter { $0 != " " && $0 != "\t" }
            if rule.count >= 3, let marker = rule.first, "-*_".contains(marker),
               rule.allSatisfy({ $0 == marker }) {
                let attachment = NSTextAttachment()
                attachment.attachmentCell = ReleaseNotesSeparatorCell(width: contentWidth)
                let separator = NSMutableAttributedString(attachment: attachment)
                let paragraph = NSMutableParagraphStyle()
                paragraph.paragraphSpacingBefore = output.length == 0 ? 0 : 10
                paragraph.paragraphSpacing = 8
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 1), .paragraphStyle: paragraph
                ]
                separator.addAttributes(attributes, range: NSRange(location: 0, length: separator.length))
                output.append(separator)
                output.append(NSAttributedString(string: "\n", attributes: attributes))
                paragraphBreak = false
                continue
            }
            var heading = false
            var listItem = false
            if let range = content.range(of: #"^#{1,6}\s+"#, options: .regularExpression) {
                content.removeSubrange(range)
                heading = true
            } else if content.hasPrefix("- ") || content.hasPrefix("* ") {
                content = "•\t" + content.dropFirst(2)
                listItem = true
            }
            let paragraph = NSMutableParagraphStyle()
            // Blank source lines delimit paragraphs; they are not empty rows.
            paragraph.paragraphSpacingBefore = output.length == 0 ? 0 : (heading ? 10 : (paragraphBreak ? 4 : 0))
            paragraph.paragraphSpacing = heading ? 5 : 3
            paragraph.lineSpacing = 2
            if listItem {
                paragraph.headIndent = 14
                paragraph.tabStops = [NSTextTab(textAlignment: .left, location: 14)]
            }
            paragraphBreak = false
            let font = NSFont.systemFont(ofSize: heading ? 15 : 13, weight: heading ? .semibold : .regular)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph
            ]
            if let parsed = try? AttributedString(markdown: content,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                let rendered = NSMutableAttributedString(string: String(parsed.characters), attributes: attributes)
                for run in parsed.runs {
                    let start = String(parsed[..<run.range.lowerBound].characters).utf16.count
                    let length = String(parsed[run.range].characters).utf16.count
                    let range = NSRange(location: start, length: length)
                    if run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true {
                        rendered.addAttribute(.font, value: NSFont.systemFont(ofSize: font.pointSize, weight: .semibold), range: range)
                    }
                    if let link = run.link, ["https", "http"].contains(link.scheme?.lowercased() ?? "") {
                        rendered.addAttribute(.link, value: link, range: range)
                    }
                }
                output.append(rendered)
            } else {
                output.append(NSAttributedString(string: content, attributes: attributes))
            }
            output.append(NSAttributedString(string: "\n", attributes: attributes))
        }
        if output.length > 0 { output.deleteCharacters(in: NSRange(location: output.length - 1, length: 1)) }
        if markdown.count > body.count {
            output.append(NSAttributedString(string: "\n…", attributes: [.foregroundColor: NSColor.secondaryLabelColor]))
        }
        return output
    }
}

/// A vector rule uses the current appearance's separator color when drawn.
private final class ReleaseNotesSeparatorCell: NSTextAttachmentCell {
    private let ruleWidth: CGFloat

    init(width: CGFloat) {
        ruleWidth = width
        super.init(textCell: "")
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func cellSize() -> NSSize { NSSize(width: ruleWidth, height: 1) }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        NSColor.separatorColor.setFill()
        NSRect(x: cellFrame.minX, y: cellFrame.midY - 0.5, width: cellFrame.width, height: 1).fill()
    }

    override func wantsToTrackMouse() -> Bool { false }
}
