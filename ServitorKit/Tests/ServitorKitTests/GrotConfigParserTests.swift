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
