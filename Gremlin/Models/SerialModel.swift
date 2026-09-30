import Foundation
import Observation
import GremlinKit

/// The app-wide serial connection and its received data.
/// The connection stays open when switching pages.
@MainActor
@Observable
final class SerialModel {
    private(set) var availablePorts: [SerialPortInfo] = []
    var selectedPort: String?
    var selectedBaudRate = SerialSettings.defaultBaudRate
    private(set) var connectedPort: String?
    private(set) var connectedBaudRate: Int?
    private(set) var connectionError: String?
    private(set) var buffer = SerialBuffer()

    @ObservationIgnored private let ports: any SerialPortListing
    @ObservationIgnored private let connector: any SerialConnecting
    @ObservationIgnored private var connection: (any SerialConnectionProtocol)?
    @ObservationIgnored private var eventsTask: Task<Void, Never>?

    init(
        ports: any SerialPortListing = SerialPortDiscovery(),
        connector: any SerialConnecting = SerialConnector()
    ) {
        self.ports = ports
        self.connector = connector
    }

    var isConnected: Bool { connectedPort != nil }

    /// Standard rates, plus the selected rate if a project uses a non-standard one.
    var baudRateOptions: [Int] {
        Set(SerialSettings.baudRates + [selectedBaudRate]).sorted()
    }

    /// Lists ports with likely Arduinos first, and selects the first one if the
    /// current selection is gone.
    func refreshPorts() {
        availablePorts = SerialPortInfo.sortedLikelyArduinoFirst(ports.availablePorts())
        if !isConnected, !availablePorts.contains(where: { $0.path == selectedPort }) {
            selectedPort = availablePorts.first?.path
        }
    }

    func connect() {
        guard !isConnected, let path = selectedPort else { return }
        connectionError = nil
        do {
            let connection = try connector.open(path: path, baudRate: selectedBaudRate)
            self.connection = connection
            connectedPort = path
            connectedBaudRate = selectedBaudRate
            eventsTask = Task { [weak self] in
                for await event in connection.events {
                    self?.handle(event)
                }
            }
        } catch {
            connectionError = error.localizedDescription
        }
    }

    func disconnect() {
        connection?.close()
        tearDown()
    }

    /// Sends `text` followed by a newline. Returns whether it was written.
    func send(_ text: String) async -> Bool {
        guard let connection, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        do {
            try await connection.write(text + "\n")
            return true
        } catch {
            connectionError = error.localizedDescription
            return false
        }
    }

    func clear() {
        buffer.clear()
    }

    /// Used after loading a project so the next connection uses the sketch's baud rate.
    func setPreferredBaudRate(_ rate: Int) {
        guard !isConnected else { return }
        selectedBaudRate = rate
    }

    /// Everything received, one line per message, for saving to a file.
    var logText: String {
        buffer.messages.map(\.text).joined(separator: "\n")
    }

    private func handle(_ event: SerialEvent) {
        switch event {
        case let .lines(lines):
            for line in lines {
                buffer.append(line.text, at: line.timestamp)
            }
        case let .disconnected(reason):
            tearDown()
            connectionError = "Connection lost: \(reason)"
        }
    }

    private func tearDown() {
        eventsTask?.cancel()
        eventsTask = nil
        connection = nil
        connectedPort = nil
        connectedBaudRate = nil
    }
}
