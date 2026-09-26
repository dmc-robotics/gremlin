import Foundation
import Testing
@testable import ServitorKit

/// Ported from the handleSerialData cases in servitor/tests/renderer/stores/serial.test.ts
struct SerialBufferTests {
    private let t0 = Date(timeIntervalSince1970: 1_000)

    @Test func assignsIncrementingIDsFromOne() {
        var buffer = SerialBuffer()
        #expect(buffer.append("a", at: t0).id == 1)
        #expect(buffer.append("b", at: t0).id == 2)
        #expect(buffer.messages.map(\.id) == [1, 2])
    }

    @Test func keepsTimestampTextAndKind() {
        var buffer = SerialBuffer()
        let message = buffer.append("WARN:hot", at: t0)
        #expect(message.timestamp == t0)
        #expect(message.text == "WARN:hot")
        #expect(message.kind == .warn)
    }

    @Test func trimsMessagesToCapacity() {
        var buffer = SerialBuffer(capacity: 3)
        for i in 1...5 { buffer.append("line \(i)", at: t0) }
        #expect(buffer.messages.map(\.text) == ["line 3", "line 4", "line 5"])
    }

    @Test func nonDataLinesDoNotPlot() {
        var buffer = SerialBuffer()
        buffer.append("hello", at: t0)
        #expect(buffer.timestamps.isEmpty)
        #expect(!buffer.hasPlotData)
    }

    @Test func accumulatesValuesForAKey() {
        var buffer = SerialBuffer()
        buffer.append("temp:1", at: t0)
        buffer.append("temp:2", at: t0 + 1)
        #expect(buffer.seriesNames == ["temp"])
        #expect(buffer.seriesValues["temp"] == [1, 2])
        #expect(buffer.timestamps == [t0, t0 + 1])
    }

    @Test func backfillsNewKeysWithGaps() {
        var buffer = SerialBuffer()
        buffer.append("a:1", at: t0)
        buffer.append("a:2", at: t0)
        buffer.append("a:3,b:9", at: t0)
        #expect(buffer.seriesNames == ["a", "b"])
        #expect(buffer.seriesValues["b"] == [nil, nil, 9])
    }

    @Test func fillsGapWhenKeyMissingFromLaterSample() {
        var buffer = SerialBuffer()
        buffer.append("a:1,b:2", at: t0)
        buffer.append("a:3", at: t0)
        #expect(buffer.seriesValues["a"] == [1, 3])
        #expect(buffer.seriesValues["b"] == [2, nil])
    }

    @Test func trimsSeriesInStepWithTimestamps() {
        var buffer = SerialBuffer(capacity: 2)
        buffer.append("a:1", at: t0)
        buffer.append("a:2,b:5", at: t0 + 1)
        buffer.append("a:3", at: t0 + 2)
        #expect(buffer.timestamps == [t0 + 1, t0 + 2])
        #expect(buffer.seriesValues["a"] == [2, 3])
        #expect(buffer.seriesValues["b"] == [5, nil])
    }

    @Test func clearResetsEverythingIncludingIDs() {
        var buffer = SerialBuffer(capacity: 7)
        buffer.append("a:1", at: t0)
        buffer.clear()
        #expect(buffer.messages.isEmpty)
        #expect(buffer.timestamps.isEmpty)
        #expect(buffer.seriesNames.isEmpty)
        #expect(buffer.capacity == 7)
        #expect(buffer.append("x", at: t0).id == 1)
    }
}
