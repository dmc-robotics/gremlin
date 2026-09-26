import Foundation
import Testing
@testable import ServitorKit

struct ProcessRunnerTests {
    private func sh(_ script: String, timeout: Duration) -> (CommandOutput, Duration) {
        let clock = ContinuousClock()
        var output: CommandOutput!
        let elapsed = clock.measure {
            output = ProcessRunner.run(executable: URL(filePath: "/bin/sh"), arguments: ["-c", script], timeout: timeout)
        }
        return (output, elapsed)
    }

    @Test func timeoutKillsAProcessThatIgnoresSIGTERM() {
        // Interactive zsh ignores SIGTERM, which is what the login-shell PATH lookup runs
        let (output, elapsed) = sh("trap '' TERM; sleep 30", timeout: .milliseconds(300))
        #expect(output.stderr.contains("Timed out"))
        #expect(elapsed < .seconds(5))
    }

    @Test func backgroundChildHoldingOutputOpenDoesNotBlock() {
        // Like an agent started from .zshrc: the shell exits but the pipe stays open
        let (output, elapsed) = sh("echo done; sleep 20 &", timeout: .seconds(30))
        #expect(output.stdout == "done\n")
        #expect(output.succeeded)
        #expect(elapsed < .seconds(5))
    }

    @Test func capturesLargeOutputOnBothPipes() {
        let (output, _) = sh("yes out | head -c 200000; yes err | head -c 200000 >&2", timeout: .seconds(10))
        #expect(output.stdout.utf8.count == 200_000)
        #expect(output.stderr.utf8.count == 200_000)
    }

    @Test func launchFailure() {
        let output = ProcessRunner.run(executable: URL(filePath: "/nonexistent"), arguments: [], timeout: .seconds(1))
        #expect(output.exitCode == 1)
        #expect(!output.stderr.isEmpty)
    }
}
