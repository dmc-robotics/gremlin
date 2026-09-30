import Foundation

public enum GrotConfigError: LocalizedError, Equatable {
    case invalidPort(String)
    case symbolicLink

    public var errorDescription: String? {
        switch self {
        case let .invalidPort(port): "\"\(port)\" isn't a serial device path"
        case .symbolicLink: ".grotconfig is a symbolic link; edit the file it points to instead"
        }
    }
}

/// Reads and edits the few `.grotconfig` fields Gremlin needs. This is not a full TOML parser;
/// keys must start a line, matching grot's generated files.
public enum GrotConfigParser {
    public static let fileName = ".grotconfig"
    public static let defaultBaudRate = 9600
    // Computed because Regex isn't Sendable; literals are compiled at build time, so this is cheap.
    /// Device paths grot accepts, e.g. /dev/cu.usbmodem1101
    private static var portPattern: Regex<Substring> { /\/dev\/[A-Za-z0-9._-]+/ }

    public static func parse(_ content: String) -> GrotConfig {
        GrotConfig(
            fqbn: string("fqbn", in: content),
            port: string("port", in: content),
            sketchPath: string("sketch_path", in: content),
            baudRate: integer("baud_rate", in: content).flatMap { $0 > 0 ? $0 : nil } ?? defaultBaudRate,
            targetCore: string("target_core", in: content),
            flashSplit: decimal("flash_split", in: content)
        )
    }

    /// Returns `content` with its `port` value replaced, quoting it if it wasn't quoted,
    /// or with a `port` line appended if there wasn't one.
    /// Only spaces and tabs separate key and value, so an empty `port =` can't reach into the next line.
    public static func updatingPort(in content: String, to newPort: String) -> String {
        let quoted = /^(port[ \t]*=[ \t]*)"[^"\n]*"/.anchorsMatchLineEndings()
        if content.contains(quoted) {
            return content.replacing(quoted, maxReplacements: 1) { "\($0.1)\"\(newPort)\"" }
        }
        let unquoted = /^(port[ \t]*=[ \t]*)\S+/.anchorsMatchLineEndings()
        if content.contains(unquoted) {
            return content.replacing(unquoted, maxReplacements: 1) { "\($0.1)\"\(newPort)\"" }
        }
        return trimmingTrailingWhitespace(content) + "\nport = \"\(newPort)\"\n"
    }

    /// Writes `port` into the `.grotconfig` at `url`. Refuses a symbolic link (writing would
    /// replace the link with a copy of whatever it points to) and anything but a device path.
    public static func writePort(_ port: String, toConfigAt url: URL) throws {
        guard port.wholeMatch(of: portPattern) != nil else {
            throw GrotConfigError.invalidPort(port)
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
        guard attributes[.type] as? FileAttributeType != .typeSymbolicLink else {
            throw GrotConfigError.symbolicLink
        }
        let content = try String(contentsOf: url, encoding: .utf8)
        try updatingPort(in: content, to: port).write(to: url, atomically: true, encoding: .utf8)
    }

    private static func firstCapture(_ pattern: String, in content: String) -> String? {
        guard let regex = try? Regex<(Substring, Substring)>(pattern).anchorsMatchLineEndings(),
              let match = content.firstMatch(of: regex) else { return nil }
        return String(match.1)
    }

    private static func string(_ key: String, in content: String) -> String {
        firstCapture(#"^\#(key)[ \t]*=[ \t]*"([^"\n]*)""#, in: content) ?? ""
    }

    private static func integer(_ key: String, in content: String) -> Int? {
        firstCapture(#"^\#(key)[ \t]*=[ \t]*(\d+)"#, in: content).flatMap { Int($0) }
    }

    private static func decimal(_ key: String, in content: String) -> Double? {
        firstCapture(#"^\#(key)[ \t]*=[ \t]*([0-9]*\.?[0-9]+)"#, in: content).flatMap { Double($0) }
    }

    private static func trimmingTrailingWhitespace(_ string: String) -> String {
        var result = Substring(string)
        while let last = result.last, last.isWhitespace { result.removeLast() }
        return String(result)
    }
}
