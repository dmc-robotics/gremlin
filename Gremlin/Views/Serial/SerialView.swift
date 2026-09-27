import SwiftUI

/// Serial monitor and plotter. Port, baud, and connect controls live in the toolbar.
struct SerialView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case monitor = "Monitor"
        case plotter = "Plotter"

        var id: Self { self }
    }

    @Environment(SerialModel.self) private var serial
    @SceneStorage("serialTab") private var tab: Tab = .monitor
    @State private var showRaw = false
    @State private var isShowingHelp = false
    @State private var exportText: String?

    var body: some View {
        VStack(spacing: 0) {
            controlBar
            Divider()
            Group {
                switch tab {
                case .monitor: SerialMonitorView(showRaw: showRaw)
                case .plotter: SerialPlotterView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            SendField()
        }
        .navigationTitle("Serial Monitor")
        .toolbar { connectionToolbar }
        .fileExporter(
            isPresented: Binding(get: { exportText != nil }, set: { if !$0 { exportText = nil } }),
            item: exportText ?? "",
            contentTypes: [.plainText],
            defaultFilename: "serial-\(Date.now.fileNameTimestamp).txt"
        ) { _ in }
        .task {
            serial.refreshPorts()
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var connectionToolbar: some ToolbarContent {
        @Bindable var serial = serial
        ToolbarItemGroup(placement: .primaryAction) {
            Button("Refresh Ports", systemImage: "arrow.clockwise") { serial.refreshPorts() }
                .disabled(serial.isConnected)
                .help("Refresh ports")

            // Menus with an explicit title-and-icon label: in the toolbar, Picker pop-ups draw
            // blank and text-only labels are hidden
            Menu {
                Picker("Port", selection: $serial.selectedPort) {
                    ForEach(serial.availablePorts) { port in
                        Text(port.displayName).tag(Optional(port.path))
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                Label(portTitle, systemImage: "cable.connector.horizontal")
            }
            .labelStyle(.titleAndIcon)
            .disabled(serial.isConnected || serial.availablePorts.isEmpty)
            .help("Serial port")

            Menu {
                Picker("Baud Rate", selection: $serial.selectedBaudRate) {
                    ForEach(serial.baudRateOptions, id: \.self) { rate in
                        Text(Self.baudTitle(rate)).tag(rate)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                Label(Self.baudTitle(serial.selectedBaudRate), systemImage: "speedometer")
            }
            .labelStyle(.titleAndIcon)
            .disabled(serial.isConnected)
            .help("Baud rate")

            if serial.isConnected {
                Button("Disconnect", systemImage: "cable.connector.slash") { serial.disconnect() }
                    .labelStyle(.titleAndIcon)
            } else {
                Button("Connect", systemImage: "cable.connector") { serial.connect() }
                    .labelStyle(.titleAndIcon)
                    .disabled(serial.selectedPort == nil)
            }
        }
    }

    private var portTitle: String {
        serial.availablePorts.first { $0.path == serial.selectedPort }?.displayName
            ?? (serial.availablePorts.isEmpty ? "No Ports" : "Select a Port")
    }

    private static func baudTitle(_ rate: Int) -> String {
        "\(rate.formatted(.number.grouping(.never))) baud"
    }

    // MARK: - Control bar

    private var controlBar: some View {
        HStack(spacing: 12) {
            Picker("View", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            Toggle("Raw", isOn: $showRaw)
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(tab != .monitor)
                .help("Show lines exactly as received, without timestamps or colors")

            Button("Serial Data Protocol", systemImage: "questionmark.circle") { isShowingHelp = true }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Serial data protocol")
                .popover(isPresented: $isShowingHelp, arrowEdge: .bottom) {
                    SerialProtocolHelp()
                }

            if let error = serial.connectionError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(error)
            }

            Spacer()

            Group {
                Button("Save Log…", systemImage: "square.and.arrow.down") { exportText = serial.logText }
                    .disabled(serial.buffer.messages.isEmpty)
                    .help("Save received lines to a file")
                Button("Clear", systemImage: "trash") { serial.clear() }
                    .help("Clear received data")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

/// Text box for sending to the device. Return sends; Shift-Return inserts a newline.
private struct SendField: View {
    @Environment(SerialModel.self) private var serial
    @State private var text = ""
    @State private var isSending = false
    @FocusState private var isFocused: Bool

    private var canSend: Bool {
        serial.isConnected && !isSending && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Send to device", text: $text, prompt: Text("Send to device (Return to send)"), axis: .vertical)
                .textFieldStyle(.plain)
                .font(.body.monospaced())
                .lineLimit(1...4)
                .focused($isFocused)
                .onKeyPress(.return, phases: .down) { press in
                    if press.modifiers.contains(.shift) {
                        text += "\n"
                    } else {
                        send()
                    }
                    return .handled
                }

            Button("Send", systemImage: "arrow.up.circle.fill", action: send)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .font(.title2)
                .disabled(!canSend)
                .help("Send")
        }
        .padding(10)
        .disabled(!serial.isConnected)
        .onChange(of: serial.isConnected) { _, connected in
            if connected { isFocused = true }
        }
    }

    /// One send at a time, so pressing Return quickly can't send the same text twice
    private func send() {
        guard canSend else { return }
        let sent = text
        isSending = true
        Task {
            if await serial.send(sent), text == sent {
                text = ""
            }
            isSending = false
        }
    }
}
