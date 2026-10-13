import Foundation

// Use macOS itself to encode Finder's background bookmark. Hand-built bookmark
// records can fail to resolve on newer macOS versions even when the file exists.
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let data = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
FileHandle.standardOutput.write(data)
