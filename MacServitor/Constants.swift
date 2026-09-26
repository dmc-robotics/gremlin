import Foundation

enum SerialSettings {
    static let baudRates = [300, 1200, 2400, 4800, 9600, 19200, 38400, 57600, 115_200, 230_400, 460_800, 921_600, 1_000_000, 2_000_000]
    static let defaultBaudRate = 115_200
}

/// UserDefaults keys and default values for Settings.
enum Preferences {
    static let terminalAppKey = "terminalAppPath"
    static let editorAppKey = "editorAppPath"
    static let defaultTerminalApp = "/System/Applications/Utilities/Terminal.app"
    static let defaultEditorApp = "/System/Applications/TextEdit.app"
}

enum Layout {
    static let windowMinWidth: CGFloat = 760
    static let windowMinHeight: CGFloat = 520
    static let defaultWindowWidth: CGFloat = 1000
    static let defaultWindowHeight: CGFloat = 720
    static let sidebarMinWidth: CGFloat = 160
    static let sidebarIdealWidth: CGFloat = 190
    static let cardMinWidth: CGFloat = 300
    static let cardSpacing: CGFloat = 16
    static let cornerRadius: CGFloat = 12
    static let projectsMinHeight: CGFloat = 200
    static let outputMinHeight: CGFloat = 90
    static let outputIdealHeight: CGFloat = 200
    static let settingsWidth: CGFloat = 480
    static let formSheetWidth: CGFloat = 460
    static let splitHandleHeight: CGFloat = 6
    static let appIconSize: CGFloat = 16
    static let connectionDotSize: CGFloat = 10
    static let helpPopoverWidth: CGFloat = 440
    static let helpPopoverHeight: CGFloat = 520
}

enum OutputLog {
    /// Older entries are dropped beyond this
    static let maxEntries = 200
    /// Longer stdout/stderr keeps only its end
    static let maxCharactersPerStream = 100_000
}

extension Date {
    /// `2026-09-26-142233` in local time, for file names.
    var fileNameTimestamp: String {
        formatted(Date.VerbatimFormatStyle(
            format: """
                \(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits)-\
                \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased))\(minute: .twoDigits)\(second: .twoDigits)
                """,
            timeZone: .current,
            calendar: .current
        ))
    }

    /// `14:03:22.123`, used for serial and output timestamps.
    var timeWithMilliseconds: String {
        formatted(Date.VerbatimFormatStyle(
            format: """
                \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\
                \(minute: .twoDigits):\(second: .twoDigits).\(secondFraction: .fractional(3))
                """,
            timeZone: .current,
            calendar: .current
        ))
    }
}
