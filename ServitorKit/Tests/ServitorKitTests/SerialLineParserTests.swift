import Testing
@testable import ServitorKit

/// Ported from servitor/tests/renderer/serial-parser.test.ts
struct SerialLineParserTests {
    private func values(_ line: String) -> [String: Double] {
        Dictionary(uniqueKeysWithValues: SerialLineParser.parse(line).values.map { ($0.name, $0.value) })
    }

    // MARK: Plain log messages

    @Test func plainTextIsLog() {
        let result = SerialLineParser.parse("hello world")
        #expect(result.kind == .log)
        #expect(result.message == "hello world")
    }

    @Test(arguments: ["", "   "])
    func emptyOrWhitespaceIsLog(line: String) {
        #expect(SerialLineParser.parse(line).kind == .log)
    }

    @Test func plainMessageIsTrimmed() {
        #expect(SerialLineParser.parse("  hello  ").message == "hello")
    }

    // MARK: Log levels

    @Test(arguments: [
        ("ERROR:something went wrong", SerialMessageKind.error, "something went wrong"),
        ("WARN:low memory", .warn, "low memory"),
        ("INFO:system ready", .info, "system ready"),
        ("DEBUG:loop count 42", .debug, "loop count 42"),
        ("ERROR:divide by zero at line 42", .error, "divide by zero at line 42")
    ])
    func logLevels(line: String, kind: SerialMessageKind, message: String) {
        let result = SerialLineParser.parse(line)
        #expect(result.kind == kind)
        #expect(result.message == message)
    }

    @Test func logLevelsAreCaseSensitive() {
        #expect(SerialLineParser.parse("error:not a level").kind == .log)
    }

    // MARK: Data values

    @Test func singleInteger() {
        #expect(SerialLineParser.parse("temp:25").kind == .data)
        #expect(values("temp:25") == ["temp": 25])
    }

    @Test func multiplePairs() {
        #expect(values("A:10,B:20,C:30") == ["A": 10, "B": 20, "C": 30])
    }

    @Test func pairsKeepTheirOrder() {
        #expect(SerialLineParser.parse("z:1,a:2,m:3").values.map(\.name) == ["z", "a", "m"])
    }

    @Test func negativeAndFloatValues() {
        #expect(values("temp:-5") == ["temp": -5])
        #expect(values("temp:25.5") == ["temp": 25.5])
        #expect(values("x:-1.5,y:2.0") == ["x": -1.5, "y": 2.0])
    }

    @Test func underscoreInKey() {
        #expect(values("soil_moisture:512") == ["soil_moisture": 512])
    }

    // MARK: Malformed input

    @Test(arguments: [":25", "temp:", "1sensor:25", "temp:25,bad", "temp:hot", "température:25", "temp:٣"])
    func malformedIsLog(line: String) {
        #expect(SerialLineParser.parse(line).kind == .log)
    }
}
