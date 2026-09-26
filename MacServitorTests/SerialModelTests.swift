import Foundation
import ServitorKit
import Testing
@testable import MacServitor

/// Ported from servitor/tests/renderer/stores/serial.test.ts, plus connection handling.
@MainActor
struct SerialModelTests {
    let ports = FakePorts(["/dev/cu.Bluetooth-Incoming-Port", "/dev/cu.usbmodem1"])
    let connector = FakeConnector()
    let model: SerialModel

    init() {
        model = SerialModel(ports: ports, connector: connector)
    }

    private func connect() throws -> FakeConnection {
        model.refreshPorts()
        model.connect()
        return try #require(connector.lastConnection)
    }

    @Test func refreshListsArduinoFirstAndSelectsIt() {
        model.refreshPorts()
        #expect(model.availablePorts.map(\.path) == ["/dev/cu.usbmodem1", "/dev/cu.Bluetooth-Incoming-Port"])
        #expect(model.selectedPort == "/dev/cu.usbmodem1")
    }

    @Test func refreshKeepsAValidSelection() {
        model.refreshPorts()
        model.selectedPort = "/dev/cu.Bluetooth-Incoming-Port"
        model.refreshPorts()
        #expect(model.selectedPort == "/dev/cu.Bluetooth-Incoming-Port")
    }

    @Test func connectOpensSelectedPortAtSelectedBaud() throws {
        model.selectedBaudRate = 9600
        _ = try connect()
        #expect(connector.opened.map(\.path) == ["/dev/cu.usbmodem1"])
        #expect(connector.opened.map(\.baudRate) == [9600])
        #expect(model.isConnected)
        #expect(model.connectedPort == "/dev/cu.usbmodem1")
        #expect(model.connectedBaudRate == 9600)
    }

    @Test func connectFailureShowsError() {
        connector.failOpens(with: .openFailed(path: "/dev/cu.usbmodem1", reason: "Resource busy"))
        model.refreshPorts()
        model.connect()
        #expect(!model.isConnected)
        #expect(model.connectionError == "Could not open /dev/cu.usbmodem1: Resource busy")
    }

    @Test func receivedLinesFillTheBuffer() async throws {
        let connection = try connect()
        connection.receive("hello", "temp:25")
        #expect(await waitUntil { model.buffer.messages.count == 2 })
        #expect(model.buffer.messages.map(\.text) == ["hello", "temp:25"])
        #expect(model.buffer.seriesValues["temp"] == [25])
    }

    @Test func disconnectClosesConnection() throws {
        let connection = try connect()
        model.disconnect()
        #expect(connection.isClosed)
        #expect(!model.isConnected)
        #expect(model.connectedPort == nil)
    }

    @Test func connectionLossResetsStateAndShowsReason() async throws {
        let connection = try connect()
        connection.continuation.yield(.disconnected(reason: "Device not configured"))
        #expect(await waitUntil { !model.isConnected })
        #expect(model.connectionError == "Connection lost: Device not configured")
    }

    @Test func reconnectAfterConnectionLoss() async throws {
        let first = try connect()
        first.continuation.yield(.disconnected(reason: "unplugged"))
        #expect(await waitUntil { !model.isConnected })

        model.connect()
        let second = try #require(connector.lastConnection)
        #expect(second !== first)
        #expect(model.isConnected)
        second.receive("back")
        #expect(await waitUntil { model.buffer.messages.last?.text == "back" })
    }

    @Test func refreshWhileConnectedKeepsSelection() throws {
        _ = try connect()
        ports.set(["/dev/cu.Bluetooth-Incoming-Port"])
        model.refreshPorts()
        #expect(model.selectedPort == "/dev/cu.usbmodem1")
    }

    @Test func sendAppendsNewline() async throws {
        let connection = try connect()
        #expect(await model.send("LED:on"))
        #expect(connection.writes == ["LED:on\n"])
    }

    @Test func blankInputIsNotSent() async throws {
        let connection = try connect()
        #expect(!(await model.send("  \n")))
        #expect(connection.writes.isEmpty)
    }

    @Test func sendWhileDisconnectedFails() async {
        #expect(!(await model.send("x")))
    }

    @Test func writeFailureShowsError() async throws {
        let connection = try connect()
        connection.failWrites(with: .writeFailed("Timed out"))
        #expect(!(await model.send("x")))
        #expect(model.connectionError == "Write failed: Timed out")
    }

    @Test func clearEmptiesBuffer() async throws {
        let connection = try connect()
        connection.receive("a:1")
        #expect(await waitUntil { !model.buffer.messages.isEmpty })
        model.clear()
        #expect(model.buffer.messages.isEmpty)
        #expect(!model.buffer.hasPlotData)
    }

    @Test func preferredBaudAppliesOnlyWhenDisconnected() throws {
        model.setPreferredBaudRate(57600)
        #expect(model.selectedBaudRate == 57600)

        _ = try connect()
        model.setPreferredBaudRate(9600)
        #expect(model.selectedBaudRate == 57600)
    }

    @Test func nonStandardBaudIsOffered() {
        model.setPreferredBaudRate(74880)
        #expect(model.baudRateOptions.contains(74880))
        #expect(model.baudRateOptions.contains(115_200))
    }

    @Test func logTextJoinsLines() async throws {
        let connection = try connect()
        connection.receive("one", "two")
        #expect(await waitUntil { model.buffer.messages.count == 2 })
        #expect(model.logText == "one\ntwo")
    }
}

struct PlotPointTests {
    @Test func samplesWithTheSameTimestampHaveDistinctIDs() {
        var buffer = SerialBuffer()
        let t0 = Date(timeIntervalSince1970: 0)
        buffer.append("a:1", at: t0)
        buffer.append("a:2", at: t0)
        let ids = PlotPoint.points(from: buffer).map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func missingSamplesSplitSegments() {
        var buffer = SerialBuffer()
        let t0 = Date(timeIntervalSince1970: 0)
        buffer.append("a:1", at: t0)
        buffer.append("b:5", at: t0 + 1)
        buffer.append("a:3", at: t0 + 2)

        let points = PlotPoint.points(from: buffer)
        let a = points.filter { $0.series == "a" }
        #expect(a.map(\.elapsed) == [0, 2])
        #expect(Set(a.map(\.segment)).count == 2)
        #expect(points.filter { $0.series == "b" }.map(\.value) == [5])
    }
}
