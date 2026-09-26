import Foundation
import Testing
@testable import ServitorKit

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
        #expect(output.stderr.contains("No such file or directory"))
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

    @Test func parsesPATHFromEnvOutput() {
        let env = "HOME=/Users/x\nPATH=/opt/homebrew/bin:/usr/bin\nSHELL=/bin/zsh\n"
        #expect(ShellEnvironment.parsePATH(fromEnv: env) == "/opt/homebrew/bin:/usr/bin")
        #expect(ShellEnvironment.parsePATH(fromEnv: "HOME=/x") == nil)
    }
}
