import ServitorKit
import SwiftUI

extension ANSIText {
    /// grot output as styled text. Unstyled runs keep the surrounding foreground color.
    static func attributedString(_ text: String) -> AttributedString {
        parse(text).reduce(into: AttributedString()) { result, segment in
            var run = AttributedString(segment.text)
            let style = segment.style
            if let color = style.foreground {
                run.foregroundColor = color.swiftUIColor
            }
            if let color = style.background {
                run.backgroundColor = color.swiftUIColor.opacity(0.3)
            }
            var intent: InlinePresentationIntent = []
            if style.bold { intent.insert(.stronglyEmphasized) }
            if style.italic { intent.insert(.emphasized) }
            if !intent.isEmpty { run.inlinePresentationIntent = intent }
            if style.underline { run.underlineStyle = .single }
            result += run
        }
    }
}

extension ANSIColor {
    /// System colors so output stays readable in light and dark mode.
    /// Black and white map to the label color, which contrasts in either appearance.
    var swiftUIColor: Color {
        switch self {
        case .black, .white, .brightWhite: .primary
        case .red: .red
        case .green: .green
        case .yellow: .yellow
        case .blue: .blue
        case .magenta: .purple
        case .cyan: .cyan
        case .gray: .secondary
        }
    }
}
