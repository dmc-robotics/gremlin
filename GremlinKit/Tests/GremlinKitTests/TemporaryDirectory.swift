import Foundation

/// A uniquely named directory under the system temp dir, removed on deinit.
final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appending(path: "GremlinKitTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    /// Creates a subdirectory and returns its path.
    func makeDirectory(_ name: String) throws -> String {
        let directory = url.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.path(percentEncoded: false)
    }

    func write(_ content: String, to relativePath: String) throws {
        try content.write(to: url.appending(path: relativePath), atomically: true, encoding: .utf8)
    }
}
