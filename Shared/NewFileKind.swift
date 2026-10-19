import Foundation

/// Shared by the settings window and Finder extension so actions stay in sync.
enum NewFileKind: String, CaseIterable {
    case text, markdown, numbers, pages, keynote, word, excel, powerpoint

    var action: String { "new-\(rawValue)" }

    var preferenceKey: String {
        switch self {
        case .text: return "isNewTextEnabled"
        case .markdown: return "isNewMarkdownEnabled"
        case .numbers: return "isNewNumbersEnabled"
        case .pages: return "isNewPagesEnabled"
        case .keynote: return "isNewKeynoteEnabled"
        case .word: return "isNewWordEnabled"
        case .excel: return "isNewExcelEnabled"
        case .powerpoint: return "isNewPowerPointEnabled"
        }
    }

    var fileExtension: String {
        switch self {
        case .text: return "txt"
        case .markdown: return "md"
        case .numbers: return "numbers"
        case .pages: return "pages"
        case .keynote: return "key"
        case .word: return "docx"
        case .excel: return "xlsx"
        case .powerpoint: return "pptx"
        }
    }

    var symbolName: String {
        switch self {
        case .text: return "file-text"
        case .markdown: return "markdown"
        case .numbers: return "tablecells"
        case .pages: return "doc.richtext"
        case .keynote: return "rectangle.on.rectangle"
        case .word: return "office-word"
        case .excel: return "office-excel"
        case .powerpoint: return "office-powerpoint"
        }
    }

    var usesTemplate: Bool { self != .text && self != .markdown }

    func title(isEnglish: Bool) -> String {
        switch self {
        case .text: return isEnglish ? "New Text" : "新建 Text"
        case .markdown: return isEnglish ? "New Markdown" : "新建 Markdown"
        case .numbers: return isEnglish ? "New Numbers Spreadsheet" : "新建 Numbers 表格"
        case .pages: return isEnglish ? "New Pages Document" : "新建 Pages 文稿"
        case .keynote: return isEnglish ? "New Keynote Presentation" : "新建 Keynote 讲演"
        case .word: return isEnglish ? "New Word Document" : "新建 Word 文档"
        case .excel: return isEnglish ? "New Excel Spreadsheet" : "新建 Excel 表格"
        case .powerpoint: return isEnglish ? "New PowerPoint Presentation" : "新建 PowerPoint 演示文稿"
        }
    }

    func detail(isEnglish: Bool) -> String {
        isEnglish ? "Create Untitled.\(fileExtension) here" : "在当前位置创建 Untitled.\(fileExtension)"
    }
}
