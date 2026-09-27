import Foundation
import Testing
@testable import GremlinKit

/// Runs GrotRunner against a fake `grot` shell script.
struct GrotRunnerTests {
    let temp: TemporaryDirectory
    let fakeGrot: String

    init() throws {
        temp = try TemporaryDirectory()
        fakeGrot = temp.url.appending(path: "grot").path(percentEncoded: false)
        try temp.write("""
            #!/bin/sh
            case "$1" in
              --version) echo "grot 1.4.2" ;;
              build) echo "building in $(pwd)"; echo "args: $*" ;;
              env) echo "CLICOLOR_FORCE=$CLICOLOR_FORCE" ;;
              path) echo "$PATH" ;;
              fail) echo "compile error" >&2; exit 3 ;;
              sleep) sleep 10 ;;
            esac
            """, to: "grot")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeGrot)
    }

    private func runner(timeout: Duration = GrotRunner.defaultTimeout) -> GrotRunner {
        GrotRunner(executable: fakeGrot, environment: ProcessInfo.processInfo.environment, timeout: timeout)
    }

    @Test func runsInProjectDirectoryWithArguments() async throws {
        let project = try temp.makeDirectory("blink")
        let output = await runner().run(["build", "-c", "x/.grotconfig"], in: URL(filePath: project))
        #expect(output.exitCode == 0)
        #expect(output.stdout.contains("building in \(ProjectWatcher.canonicalPath(project))"))
        #expect(output.stdout.contains("args: build -c x/.grotconfig"))
    }

    @Test func asksGrotForColoredOutput() async {
        let output = await runner().run(["env"], in: temp.url)
        #expect(output.stdout == "CLICOLOR_FORCE=1\n")
    }

    @Test func reportsFailureExitCodeAndStderr() async {
        let output = await runner().run(["fail"], in: temp.url)
        #expect(output.exitCode == 3)
        #expect(output.stderr == "compile error\n")
        #expect(!output.succeeded)
    }

    @Test func missingExecutableReportsReason() async {
        let missing = GrotRunner(executable: "/nonexistent/grot", environment: [:])
        let output = await missing.run(["build"], in: temp.url)
        #expect(output.exitCode != 0)
        #expect(output.stderr.contains("/nonexistent/grot not found"))
    }

    @Test func findsGrotOnAbsolutePATHEntries() async throws {
        let bin = try temp.makeDirectory("bin")
        try FileManager.default.copyItem(atPath: fakeGrot, toPath: bin + "grot")
        let runner = GrotRunner(environment: ["PATH": "/usr/bin:\(bin)"])
        #expect(await runner.version() == "1.4.2")
    }

    @Test func ignoresRelativePATHEntries() async throws {
        // A project folder shipping its own bin/grot must not be run
        let project = try temp.makeDirectory("project")
        try FileManager.default.createDirectory(atPath: project + "bin", withIntermediateDirectories: true)
        try FileManager.default.copyItem(atPath: fakeGrot, toPath: project + "bin/grot")
        let runner = GrotRunner(environment: ["PATH": "bin:.:/usr/bin"])
        let output = await runner.run(["build"], in: URL(filePath: project))
        #expect(!output.succeeded)
        #expect(output.stderr.contains("grot not found"))
    }

    @Test func passesOnlyAbsolutePATHToGrot() async {
        let runner = GrotRunner(executable: fakeGrot, environment: ["PATH": "bin:/usr/bin::/bin:."])
        let output = await runner.run(["path"], in: temp.url)
        #expect(output.stdout == "/usr/bin:/bin\n")
    }

    @Test func timesOut() async {
        let output = await runner(timeout: .milliseconds(300)).run(["sleep"], in: temp.url)
        #expect(!output.succeeded)
        #expect(output.stderr.contains("Timed out"))
    }

    @Test func version() async {
        #expect(await runner().version() == "1.4.2")
        #expect(await GrotRunner(executable: "/nonexistent/grot", environment: [:]).version() == nil)
    }

    @Test func parsesPATHAfterMarker() {
        let output = "Welcome to zsh!\nPATH=/wrong\n__GREMLIN_PATH__/opt/homebrew/bin:/usr/bin\n"
        #expect(ShellEnvironment.parsePATH(output) == "/opt/homebrew/bin:/usr/bin")
        #expect(ShellEnvironment.parsePATH("PATH=/usr/bin") == nil)
    }

    @Test func absolutePATHDropsRelativeEntries() {
        #expect(ShellEnvironment.absolutePATH(".:bin::/usr/bin:/opt/homebrew/bin:") == "/usr/bin:/opt/homebrew/bin")
    }

    @Test func loginShellPATHIsReadable() {
        // Runs the user's real login shell, as the app does
        let path = ShellEnvironment.loginShellPATH()
        #expect(path?.contains("/usr/bin") == true)
    }
}
