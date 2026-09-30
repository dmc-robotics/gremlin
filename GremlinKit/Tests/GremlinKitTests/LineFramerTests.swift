import Foundation
import Testing
@testable import GremlinKit

struct LineFramerTests {
    private let t0 = Date(timeIntervalSince1970: 1_000)

    private func texts(_ lines: [SerialLine]) -> [String] { lines.map(\.text) }

    @Test func stripsLineEndingsButKeepsWhitespace() {
        var framer = LineFramer(start: t0)
        #expect(texts(framer.append(Array("  indented\r\nplain\n".utf8), at: t0)) == ["  indented", "plain"])
    }

    @Test func holdsPartialLines() {
        var framer = LineFramer(start: t0)
        #expect(framer.append(Array("par".utf8), at: t0).isEmpty)
        #expect(texts(framer.append(Array("tial\n".utf8), at: t0)) == ["partial"])
        #expect(framer.pendingCount == 0)
    }

    @Test func keepsEmptyLines() {
        var framer = LineFramer(start: t0)
        #expect(texts(framer.append(Array("a\n\nb\n".utf8), at: t0)) == ["a", "", "b"])
    }

    @Test func splitsLinesThatNeverEnd() {
        var framer = LineFramer(start: t0)
        let flood = [UInt8](repeating: UInt8(ascii: "x"), count: LineFramer.maxLineLength * 3 + 10)
        let lines = framer.append(flood, at: t0)
        #expect(lines.count == 3)
        #expect(lines.allSatisfy { $0.text.utf8.count == LineFramer.maxLineLength })
        #expect(framer.pendingCount == 10)
    }

    @Test func spreadsTimestampsOfOneReadSinceThePreviousRead() {
        var framer = LineFramer(start: t0)
        let now = t0 + 0.3
        let lines = framer.append(Array("a:1\na:2\na:3\n".utf8), at: now)
        let offsets = lines.map { $0.timestamp.timeIntervalSince(t0) }
        #expect(zip(offsets, [0.1, 0.2, 0.3]).allSatisfy { abs($0 - $1) < 1e-6 })
    }

    @Test func spreadIsCappedAfterIdle() {
        var framer = LineFramer(start: t0)
        let now = t0 + 600
        let lines = framer.append(Array("a\nb\n".utf8), at: now)
        #expect(abs(lines[0].timestamp.timeIntervalSince(now) + LineFramer.maxSpread / 2) < 1e-6)
        #expect(lines.last?.timestamp == now)
    }
}
