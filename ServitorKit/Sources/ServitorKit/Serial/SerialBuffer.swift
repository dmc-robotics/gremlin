import Foundation

/// A received line with its parse result.
public struct SerialMessage: Identifiable, Hashable, Sendable {
    public var id: Int
    public var timestamp: Date
    /// The line as received (whitespace-trimmed by the connection).
    public var text: String
    public var kind: SerialMessageKind
    public var values: [SerialValue]
    public var message: String?
}

/// Rolling buffer of received lines for the monitor, plus aligned per-key series for the plotter.
/// Every series has one entry per timestamp; `nil` marks a sample where that key was absent.
public struct SerialBuffer: Sendable {
    public static let defaultCapacity = 500

    public let capacity: Int
    public private(set) var messages: [SerialMessage] = []
    public private(set) var timestamps: [Date] = []
    /// Series names in first-seen order.
    public private(set) var seriesNames: [String] = []
    public private(set) var seriesValues: [String: [Double?]] = [:]
    private var nextID = 1

    public init(capacity: Int = SerialBuffer.defaultCapacity) {
        self.capacity = capacity
    }

    public var hasPlotData: Bool { !seriesNames.isEmpty && !timestamps.isEmpty }

    @discardableResult
    public mutating func append(_ text: String, at timestamp: Date) -> SerialMessage {
        let parsed = SerialLineParser.parse(text)
        let message = SerialMessage(
            id: nextID,
            timestamp: timestamp,
            text: text,
            kind: parsed.kind,
            values: parsed.values,
            message: parsed.message
        )
        nextID += 1

        messages.append(message)
        if messages.count > capacity {
            messages.removeFirst(messages.count - capacity)
        }

        if parsed.kind == .data {
            appendSample(parsed.values, at: timestamp)
        }
        return message
    }

    public mutating func clear() {
        self = SerialBuffer(capacity: capacity)
    }

    private mutating func appendSample(_ values: [SerialValue], at timestamp: Date) {
        timestamps.append(timestamp)

        var sample: [String: Double] = [:]
        for value in values {
            sample[value.name] = value.value
            if seriesValues[value.name] == nil {
                // New key: backfill gaps for earlier samples
                seriesNames.append(value.name)
                seriesValues[value.name] = Array(repeating: nil, count: timestamps.count - 1)
            }
        }
        for name in seriesNames {
            seriesValues[name, default: []].append(sample[name])
        }

        if timestamps.count > capacity {
            let overflow = timestamps.count - capacity
            timestamps.removeFirst(overflow)
            for name in seriesNames {
                seriesValues[name]?.removeFirst(overflow)
            }
        }
    }
}
