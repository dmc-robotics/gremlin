import Foundation

/// The ANSI colors grot's Colorator emits (grot/lib/grot/cli/colorator.rb).
public enum ANSIColor: Sendable, Hashable {
    case black, red, green, yellow, blue, magenta, cyan, white, gray, brightWhite

    private static let byCode: [Int: ANSIColor] = [
        30: .black, 31: .red, 32: .green, 33: .yellow, 34: .blue, 35: .magenta, 36: .cyan, 37: .white,
        90: .gray, 97: .brightWhite
    ]

    static func foreground(code: Int) -> ANSIColor? { byCode[code] }

    static func background(code: Int) -> ANSIColor? {
        (40...47).contains(code) ? byCode[code - 10] : nil
    }
}

public struct ANSIStyle: Hashable, Sendable {
    public var bold = false
    public var italic = false
    public var underline = false
    public var foreground: ANSIColor?
    public var background: ANSIColor?

    public init() {}
}

public struct ANSISegment: Hashable, Sendable {
    public var text: String
    public var style: ANSIStyle
}

/// Splits grot command output into styled segments.
///
/// SGR codes (colors, bold, italic, underline) become styles. Other escape sequences
/// (cursor movement, erase line, hide cursor) are dropped. Carriage returns become newlines
/// so spinner frames show as separate lines, and runs of blank lines are collapsed.
public enum ANSIText {
    // Computed because Regex isn't Sendable; literals are compiled at build time, so this is cheap.
    private static var sgr: Regex<(Substring, Substring)> { /\u{1B}\[([\d;]*)m/ }
    private static var nonSGR: Regex<Substring> { /\u{1B}\[[\d;?]*[A-Za-ln-z]/ }
    private static var anyEscape: Regex<Substring> { /\u{1B}\[[\d;?]*[A-Za-z]/ }

    public static func parse(_ text: String) -> [ANSISegment] {
        let cleaned = text
            .replacing(nonSGR, with: "")
            .replacing("\r\n", with: "\n")
            .replacing("\r", with: "\n")
            .replacing(/\n{3,}/, with: "\n\n")

        var segments: [ANSISegment] = []
        var style = ANSIStyle()
        var remainder = cleaned[...]

        while let match = remainder.firstMatch(of: sgr) {
            append(remainder[..<match.range.lowerBound], style: style, to: &segments)
            apply(codes: match.1, to: &style)
            remainder = remainder[match.range.upperBound...]
        }
        append(remainder, style: style, to: &segments)
        return segments
    }

    public static func strip(_ text: String) -> String {
        text.replacing(anyEscape, with: "")
    }

    private static func append(_ text: Substring, style: ANSIStyle, to segments: inout [ANSISegment]) {
        guard !text.isEmpty else { return }
        segments.append(ANSISegment(text: String(text), style: style))
    }

    private static func apply(codes: Substring, to style: inout ANSIStyle) {
        // ESC[m is the same as ESC[0m
        let numbers = codes.isEmpty ? [0] : codes.split(separator: ";").compactMap { Int($0) }
        for code in numbers {
            switch code {
            case 0: style = ANSIStyle()
            case 1: style.bold = true
            case 3: style.italic = true
            case 4: style.underline = true
            default:
                if let color = ANSIColor.foreground(code: code) {
                    style.foreground = color
                } else if let color = ANSIColor.background(code: code) {
                    style.background = color
                }
            }
        }
    }
}
