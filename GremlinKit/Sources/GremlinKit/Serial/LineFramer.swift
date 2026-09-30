import Foundation

/// Splits a byte stream into newline-terminated lines.
///
/// Lines longer than `maxLineLength` are split, so a device that never sends a newline can't
/// grow memory without limit. Lines from one read get evenly spaced timestamps between the
/// previous read and now (at most `maxSpread` apart), because the device produced them over
/// that interval; giving them all the same time would stack plotted samples vertically.
struct LineFramer {
    static let maxLineLength = 4096
    static let maxSpread: TimeInterval = 1
    private static let newline = UInt8(ascii: "\n")
    private static let carriageReturn = UInt8(ascii: "\r")

    private var pending: [UInt8] = []
    private var lastRead: Date

    init(start: Date = .now) {
        lastRead = start
    }

    var pendingCount: Int { pending.count }

    mutating func append(_ bytes: some Sequence<UInt8>, at now: Date = .now) -> [SerialLine] {
        var completed: [[UInt8]] = []
        for byte in bytes {
            if byte == Self.newline {
                completed.append(pending)
                pending.removeAll(keepingCapacity: true)
            } else {
                pending.append(byte)
                if pending.count >= Self.maxLineLength {
                    completed.append(pending)
                    pending.removeAll(keepingCapacity: true)
                }
            }
        }

        let spread = min(max(now.timeIntervalSince(lastRead), 0), Self.maxSpread)
        lastRead = now
        let count = completed.count
        return completed.enumerated().map { index, bytes in
            let offset = spread * Double(count - 1 - index) / Double(count)
            return SerialLine(timestamp: now.addingTimeInterval(-offset), text: Self.decode(bytes))
        }
    }

    /// The line as sent, without its CR-LF / LF ending
    private static func decode(_ bytes: [UInt8]) -> String {
        let content = bytes.last == carriageReturn ? bytes.dropLast() : bytes[...]
        return String(decoding: content, as: UTF8.self)
    }
}
