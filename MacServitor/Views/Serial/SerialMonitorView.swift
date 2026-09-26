import ServitorKit
import SwiftUI

/// Received lines, newest at the bottom. Stays pinned to the bottom as lines arrive.
struct SerialMonitorView: View {
    let showRaw: Bool

    @Environment(SerialModel.self) private var serial

    var body: some View {
        if serial.buffer.messages.isEmpty {
            ContentUnavailableView(
                "No Messages",
                systemImage: "text.alignleft",
                description: Text("Connect to a serial port to start receiving data.")
            )
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(serial.buffer.messages) { message in
                        MessageRow(message: message, showRaw: showRaw)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .defaultScrollAnchor(.bottom)
            .defaultScrollAnchor(.bottom, for: .sizeChanges)
            .font(.body.monospaced())
            .textSelection(.enabled)
            .background(Color(nsColor: .textBackgroundColor))
        }
    }
}

private struct MessageRow: View {
    let message: SerialMessage
    let showRaw: Bool

    var body: some View {
        if showRaw {
            Text(message.text)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(message.timestamp.timeWithMilliseconds)
                    .foregroundStyle(.secondary)
                Text(message.text)
                    .foregroundStyle(color)
                    .fontWeight(message.kind == .data ? .medium : .regular)
            }
        }
    }

    private var color: AnyShapeStyle {
        switch message.kind {
        case .error: AnyShapeStyle(.red)
        case .warn: AnyShapeStyle(.orange)
        case .info: AnyShapeStyle(.tint)
        case .debug: AnyShapeStyle(.secondary)
        case .data, .log: AnyShapeStyle(.primary)
        }
    }
}
