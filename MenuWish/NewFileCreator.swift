import Foundation

enum NewFileCreator {
    /// Exclusive writes preserve existing files, even when two requests pick the same name.
    static func create(_ kind: NewFileKind, in folder: URL, templates: URL?) throws -> URL {
        let contents: Data
        if kind.usesTemplate {
            guard let templates else {
                throw CocoaError(.fileReadNoSuchFile)
            }
            contents = try Data(contentsOf: templates.appendingPathComponent("Blank.\(kind.fileExtension)"))
        } else {
            contents = Data()
        }

        var number = 1
        while true {
            let suffix = number == 1 ? "" : " \(number)"
            let file = folder.appendingPathComponent("Untitled\(suffix).\(kind.fileExtension)")
            do {
                try contents.write(to: file, options: .withoutOverwriting)
                return file
            } catch CocoaError.fileWriteFileExists {
                number += 1
            }
        }
    }
}
