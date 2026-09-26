import Foundation

/// Reads and edits the few `.grotconfig` fields Servitor needs. This is not a full TOML parser;
/// keys must start a line, matching grot's generated files.
public enum GrotConfigParser {
    public static let fileName = ".grotconfig"
    public static let defaultBaudRate = 9600

    public static func parse(_ content: String) -> GrotConfig {
        GrotConfig(
            fqbn: string("fqbn", in: content),
            port: string("port", in: content),
            sketchPath: string("sketch_path", in: content),
            baudRate: integer("baud_rate", in: content) ?? defaultBaudRate,
            targetCore: string("target_core", in: content),
            flashSplit: decimal("flash_split", in: content)
        )
    }

    /// Returns `content` with its `port` value replaced, quoting it if it wasn't quoted,
    /// or with a `port` line appended if there wasn't one.
    public static func updatingPort(in content: String, to newPort: String) -> String {
        let quoted = /^(port\s*=\s*)"[^"]*"/.anchorsMatchLineEndings()
        if content.contains(quoted) {
            return content.replacing(quoted, maxReplacements: 1) { "\($0.1)\"\(newPort)\"" }
        }
        let unquoted = /^(port\s*=\s*)\S+/.anchorsMatchLineEndings()
        if content.contains(unquoted) {
            return content.replacing(unquoted, maxReplacements: 1) { "\($0.1)\"\(newPort)\"" }
        }
        return trimmingTrailingWhitespace(content) + "\nport = \"\(newPort)\"\n"
    }

    private static func firstCapture(_ pattern: String, in content: String) -> String? {
        guard let regex = try? Regex<(Substring, Substring)>(pattern).anchorsMatchLineEndings(),
              let match = content.firstMatch(of: regex) else { return nil }
        return String(match.1)
    }

    private static func string(_ key: String, in content: String) -> String {
        firstCapture(#"^\#(key)\s*=\s*"([^"]*)""#, in: content) ?? ""
    }

    private static func integer(_ key: String, in content: String) -> Int? {
        firstCapture(#"^\#(key)\s*=\s*(\d+)"#, in: content).flatMap { Int($0) }
    }

    private static func decimal(_ key: String, in content: String) -> Double? {
        firstCapture(#"^\#(key)\s*=\s*([0-9]*\.?[0-9]+)"#, in: content).flatMap { Double($0) }
    }

    private static func trimmingTrailingWhitespace(_ string: String) -> String {
        var result = Substring(string)
        while let last = result.last, last.isWhitespace { result.removeLast() }
        return String(result)
    }
}
