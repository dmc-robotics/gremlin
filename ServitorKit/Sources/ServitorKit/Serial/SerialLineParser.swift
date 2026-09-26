import Foundation

public enum SerialMessageKind: String, Sendable {
    case data, error, warn, info, debug, log
}

/// A named numeric value from a data line such as `temp:25`.
public struct SerialValue: Hashable, Sendable {
    public var name: String
    public var value: Double

    public init(name: String, value: Double) {
        self.name = name
        self.value = value
    }
}

public struct ParsedSerialLine: Hashable, Sendable {
    public var kind: SerialMessageKind
    /// Values in the order they appeared; set only for `.data`.
    public var values: [SerialValue]
    /// Text after the level prefix for log levels, or the trimmed line for plain logs.
    public var message: String?
}

/// Parses the human-readable protocol sketches send over serial:
///
///     temp:25             → data (single value)
///     x:10,y:20,z:30      → data (multiple values)
///     ERROR:message       → error   (also WARN, INFO, DEBUG; case-sensitive)
///     anything else       → plain log
public enum SerialLineParser {
    // Computed because Regex isn't Sendable; literals are compiled at build time, so this is cheap.
    private static var dataPattern: Regex<Substring> {
        /^[a-zA-Z_]\w*:-?\d+(?:\.\d+)?(?:,[a-zA-Z_]\w*:-?\d+(?:\.\d+)?)*$/
            .asciiOnlyWordCharacters()
            .asciiOnlyDigits()
    }
    private static var logLevelPattern: Regex<(Substring, Substring, Substring)> {
        /^(ERROR|WARN|INFO|DEBUG):(.+)$/
    }

    public static func parse(_ line: String) -> ParsedSerialLine {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return ParsedSerialLine(kind: .log, values: [], message: nil)
        }

        if let match = trimmed.wholeMatch(of: logLevelPattern) {
            let kind = SerialMessageKind(rawValue: match.1.lowercased()) ?? .log
            return ParsedSerialLine(kind: kind, values: [], message: String(match.2))
        }

        if trimmed.wholeMatch(of: dataPattern) != nil {
            let values = trimmed.split(separator: ",").compactMap { pair -> SerialValue? in
                let parts = pair.split(separator: ":", maxSplits: 1)
                guard parts.count == 2, let number = Double(parts[1]) else { return nil }
                return SerialValue(name: String(parts[0]), value: number)
            }
            if !values.isEmpty {
                return ParsedSerialLine(kind: .data, values: values, message: nil)
            }
        }

        return ParsedSerialLine(kind: .log, values: [], message: trimmed)
    }
}
