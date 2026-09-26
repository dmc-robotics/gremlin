import Foundation
import Testing
@testable import ServitorKit

/// Ported from the parseGrotConfig / updatePortInConfig cases in servitor/tests/main/project-manager.test.ts
struct GrotConfigParserTests {
    @Test func parsesAllFields() {
        let config = GrotConfigParser.parse("""
            fqbn = "arduino:avr:uno"
            port = "/dev/cu.usbmodem1234"
            sketch_path = "mysketch.ino"
            baud_rate = 115200
            target_core = "arduino:avr"
            flash_split = 0.5
            """)
        #expect(config == GrotConfig(
            fqbn: "arduino:avr:uno",
            port: "/dev/cu.usbmodem1234",
            sketchPath: "mysketch.ino",
            baudRate: 115200,
            targetCore: "arduino:avr",
            flashSplit: 0.5
        ))
    }

    @Test func defaultsForMissingFields() {
        let config = GrotConfigParser.parse("")
        #expect(config.baudRate == 9600)
        #expect(config.fqbn.isEmpty)
        #expect(config.port.isEmpty)
        #expect(config.sketchPath.isEmpty)
        #expect(config.targetCore.isEmpty)
        #expect(config.flashSplit == nil)
    }

    @Test func toleratesWhitespaceAroundEquals() {
        #expect(GrotConfigParser.parse(#"fqbn   =   "arduino:avr:nano""#).fqbn == "arduino:avr:nano")
    }

    @Test func ignoresKeysNotAtLineStart() {
        let config = GrotConfigParser.parse("""
            # fqbn = "commented:out"
            fqbn = "real:value"
            """)
        #expect(config.fqbn == "real:value")
    }

    @Test func nonPositiveBaudUsesDefault() {
        #expect(GrotConfigParser.parse("baud_rate = 0").baudRate == GrotConfigParser.defaultBaudRate)
    }

    @Test func emptyValueDoesNotReachNextLine() {
        let config = GrotConfigParser.parse("port =\nfqbn = \"arduino:avr:uno\"")
        #expect(config.port.isEmpty)
        #expect(config.fqbn == "arduino:avr:uno")
    }

    @Test func emptyPortIsAppendedNotMerged() {
        let result = GrotConfigParser.updatingPort(in: "port =\nfqbn = \"x\"", to: "/dev/cu.a")
        #expect(result == "port =\nfqbn = \"x\"\nport = \"/dev/cu.a\"\n")
    }

    @Test func writePortUpdatesFile() throws {
        let temp = try TemporaryDirectory()
        try temp.write("port = \"/dev/old\"", to: ".grotconfig")
        let url = temp.url.appending(path: ".grotconfig")
        try GrotConfigParser.writePort("/dev/cu.usbmodem1101", toConfigAt: url)
        #expect(try String(contentsOf: url, encoding: .utf8) == "port = \"/dev/cu.usbmodem1101\"")
    }

    @Test(arguments: ["/dev/cu.x\"\nport = \"evil", "/dev/x; rm", "cu.usbmodem1", "/dev/../etc/passwd"])
    func writePortRejectsNonDevicePaths(port: String) throws {
        let temp = try TemporaryDirectory()
        try temp.write("port = \"/dev/old\"", to: ".grotconfig")
        #expect(throws: GrotConfigError.invalidPort(port)) {
            try GrotConfigParser.writePort(port, toConfigAt: temp.url.appending(path: ".grotconfig"))
        }
    }

    @Test func writePortRefusesSymlink() throws {
        let temp = try TemporaryDirectory()
        try temp.write("secret = \"x\"", to: "elsewhere.toml")
        let link = temp.url.appending(path: ".grotconfig")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: temp.url.appending(path: "elsewhere.toml"))
        #expect(throws: GrotConfigError.symbolicLink) {
            try GrotConfigParser.writePort("/dev/cu.a", toConfigAt: link)
        }
        #expect(try String(contentsOf: temp.url.appending(path: "elsewhere.toml"), encoding: .utf8) == "secret = \"x\"")
    }

    @Test func detectsTeensy() {
        #expect(GrotConfigParser.parse(#"fqbn = "teensy:avr:teensy41""#).isTeensy)
        #expect(!GrotConfigParser.parse(#"fqbn = "arduino:avr:uno""#).isTeensy)
    }

    @Test func updatesQuotedPort() {
        let result = GrotConfigParser.updatingPort(in: #"port = "/dev/old.port""#, to: "/dev/cu.usbmodem1234")
        #expect(result == #"port = "/dev/cu.usbmodem1234""#)
    }

    @Test func updatesUnquotedPort() {
        let result = GrotConfigParser.updatingPort(in: "port = /dev/old.port", to: "/dev/cu.usbmodem1234")
        #expect(result == #"port = "/dev/cu.usbmodem1234""#)
    }

    @Test func appendsMissingPort() {
        let result = GrotConfigParser.updatingPort(in: "fqbn = \"arduino:avr:uno\"\n\n", to: "/dev/cu.x")
        #expect(result == "fqbn = \"arduino:avr:uno\"\nport = \"/dev/cu.x\"\n")
    }

    @Test func preservesOtherFields() {
        let result = GrotConfigParser.updatingPort(
            in: "fqbn = \"arduino:avr:uno\"\nport = \"/dev/a\"\nbaud_rate = 9600",
            to: "/dev/b"
        )
        #expect(result == "fqbn = \"arduino:avr:uno\"\nport = \"/dev/b\"\nbaud_rate = 9600")
    }

    @Test func onlyUpdatesThePortKey() {
        let result = GrotConfigParser.updatingPort(
            in: "backup_port = \"/dev/cu.second\"\nport = \"/dev/cu.first\"",
            to: "/dev/cu.updated"
        )
        #expect(result == "backup_port = \"/dev/cu.second\"\nport = \"/dev/cu.updated\"")
    }
}
