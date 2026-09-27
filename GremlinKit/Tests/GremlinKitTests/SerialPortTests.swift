import Darwin
import Foundation
import Testing
@testable import GremlinKit

struct SerialPortInfoTests {
    @Test(arguments: [
        SerialPortInfo(path: "/dev/cu.debug", vendorID: 0x2341),
        SerialPortInfo(path: "/dev/cu.debug", manufacturer: "Silicon Labs"),
        SerialPortInfo(path: "/dev/cu.debug", manufacturer: "wch.cn"),
        SerialPortInfo(path: "/dev/cu.usbmodem14101"),
        SerialPortInfo(path: "/dev/cu.usbserial-110"),
        SerialPortInfo(path: "/dev/cu.debug", vendorID: 0x16C0)
    ])
    func likelyArduino(port: SerialPortInfo) {
        #expect(port.isLikelyArduino)
    }

    @Test func bluetoothIsNotArduino() {
        #expect(!SerialPortInfo(path: "/dev/cu.Bluetooth-Incoming-Port").isLikelyArduino)
    }

    @Test func sortsArduinoFirstKeepingOrder() {
        let ports = ["/dev/cu.a", "/dev/cu.usbmodem2", "/dev/cu.b", "/dev/cu.usbmodem1"].map { SerialPortInfo(path: $0) }
        #expect(SerialPortInfo.sortedLikelyArduinoFirst(ports).map(\.path) ==
            ["/dev/cu.usbmodem2", "/dev/cu.usbmodem1", "/dev/cu.a", "/dev/cu.b"])
    }

    @Test func displayNameIncludesManufacturer() {
        #expect(SerialPortInfo(path: "/dev/cu.x", manufacturer: "Arduino LLC").displayName == "/dev/cu.x - Arduino LLC")
        #expect(SerialPortInfo(path: "/dev/cu.x").displayName == "/dev/cu.x")
    }

    @Test func discoveryReturnsCalloutDevices() {
        // Hardware varies; every listed port should at least be a callout device.
        #expect(SerialPortDiscovery().availablePorts().allSatisfy { $0.path.hasPrefix("/dev/cu.") })
    }
}

/// Exercises SerialConnection against a pseudo-terminal: the test holds the master side,
/// the connection opens the slave device like a real port. Ptys ignore TIOCEXCL and custom
/// baud rates, so exclusive access and IOSSIOSPEED need checking against real hardware.
@Suite(.serialized)
final class SerialConnectionTests {
    private var master: Int32 = -1
    private let slavePath: String

    init() throws {
        var master: Int32 = -1
        var slave: Int32 = -1
        var name = [CChar](repeating: 0, count: 128)
        guard openpty(&master, &slave, &name, nil, nil) == 0 else {
            throw SerialError.openFailed(path: "pty", reason: String(cString: strerror(errno)))
        }
        // Close our slave fd so the connection's descriptor is the only one open
        Darwin.close(slave)
        self.master = master
        slavePath = String(cString: name)
    }

    deinit {
        if master >= 0 { Darwin.close(master) }
    }

    private func sendFromDevice(_ text: String) {
        _ = text.withCString { Darwin.write(master, $0, strlen($0)) }
    }

    private func nextEvent(_ connection: SerialConnection) async -> SerialEvent? {
        await firstValue(of: connection.events, timeout: .seconds(3))
    }

    private func lines(_ event: SerialEvent?) -> [String] {
        if case let .lines(lines) = event { return lines.map(\.text) }
        return []
    }

    @Test func framesLinesAcrossReads() async throws {
        let connection = try SerialConnection(path: slavePath, baudRate: 115_200)
        defer { connection.close() }

        sendFromDevice("temp:2")
        try await Task.sleep(for: .milliseconds(100))
        sendFromDevice("5\r\nhello\n")

        #expect(lines(await nextEvent(connection)) == ["temp:25", "hello"])
    }

    @Test func holdsPartialLineUntilNewline() async throws {
        let connection = try SerialConnection(path: slavePath, baudRate: 9600)
        defer { connection.close() }

        sendFromDevice("partial")
        try await Task.sleep(for: .milliseconds(200))
        sendFromDevice(" line\n")

        #expect(lines(await nextEvent(connection)) == ["partial line"])
    }

    @Test func writesReachTheDevice() async throws {
        let connection = try SerialConnection(path: slavePath, baudRate: 115_200)
        defer { connection.close() }

        // On a pty, tcdrain waits for the master to read, so read while the write is in flight
        async let written: Void = connection.write("LED:on\n")
        var buffer = [UInt8](repeating: 0, count: 64)
        let count = Darwin.read(master, &buffer, buffer.count)
        try await written

        #expect(String(decoding: buffer[0..<max(count, 0)], as: UTF8.self) == "LED:on\n")
    }

    @Test func deviceGoingAwayReportsDisconnect() async throws {
        let connection = try SerialConnection(path: slavePath, baudRate: 115_200)
        Darwin.close(master)
        master = -1

        guard case .disconnected = await nextEvent(connection) else {
            Issue.record("expected .disconnected")
            return
        }
        await #expect(throws: SerialError.closed) { try await connection.write("x") }
    }

    @Test func closeEndsEventsWithoutDisconnect() async throws {
        let connection = try SerialConnection(path: slavePath, baudRate: 115_200)
        connection.close()
        connection.close()
        #expect(await nextEvent(connection) == nil)
    }

    @Test func readsBurstsLargerThanOneChunk() async throws {
        let connection = try SerialConnection(path: slavePath, baudRate: 115_200)
        defer { connection.close() }

        let lines = (1...800).map { "line \($0) padding padding" }
        let payload = lines.joined(separator: "\n") + "\n"
        // Write from another thread: the pty buffer is smaller than the payload
        let master = self.master
        Thread.detachNewThread {
            _ = payload.withCString { Darwin.write(master, $0, strlen($0)) }
        }

        var received: [String] = []
        while received.count < lines.count, let event = await nextEvent(connection) {
            received += self.lines(event)
        }
        #expect(received == lines)
    }

    @Test func stalledWriteTimesOutWithoutBlockingReads() async throws {
        let connection = try SerialConnection(path: slavePath, baudRate: 115_200)
        defer { connection.close() }

        // Nobody reads the master side, so the pty's buffer fills and the write stalls
        let bigWrite = Task { try await connection.write(String(repeating: "x", count: 200_000)) }
        try await Task.sleep(for: .milliseconds(200))

        sendFromDevice("still reading\n")
        #expect(lines(await nextEvent(connection)) == ["still reading"])

        await #expect(throws: SerialError.self) { try await bigWrite.value }
    }

    @Test func openingMissingDeviceFails() {
        #expect(throws: SerialError.self) { try SerialConnection(path: "/dev/cu.nonexistent", baudRate: 9600) }
    }
}
