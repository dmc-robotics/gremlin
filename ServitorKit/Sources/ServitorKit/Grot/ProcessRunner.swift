import Foundation

/// Runs a command-line tool to completion, capturing its output.
enum ProcessRunner {
    /// Holds a value written on another thread. Each use is ordered by a DispatchGroup wait
    /// or by the process having exited, so no lock is needed.
    private final class Box<Value>: @unchecked Sendable {
        var value: Value
        init(_ value: Value) { self.value = value }
    }

    /// Blocks the calling thread. Launch failures are reported as exit code 1 with the reason on stderr.
    static func run(
        executable: URL,
        arguments: [String],
        currentDirectory: URL? = nil,
        environment: [String: String]? = nil,
        timeout: Duration
    ) -> CommandOutput {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
        process.environment = environment
        process.standardInput = FileHandle.nullDevice

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            return .failure(error.localizedDescription)
        }

        let timedOut = Box(false)
        let timeoutWork = DispatchWorkItem {
            if process.isRunning {
                timedOut.value = true
                process.terminate()
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout.timeInterval, execute: timeoutWork)

        // Drain both pipes concurrently so a chatty process can't fill one and block.
        let stderrBox = Box(Data())
        let group = DispatchGroup()
        DispatchQueue.global().async(group: group) {
            stderrBox.value = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        }
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()
        timeoutWork.cancel()

        var stderr = String(decoding: stderrBox.value, as: UTF8.self)
        if timedOut.value {
            stderr += "\nTimed out after \(Int(timeout.timeInterval)) seconds"
        }
        return CommandOutput(
            exitCode: process.terminationStatus,
            stdout: String(decoding: stdoutData, as: UTF8.self),
            stderr: stderr
        )
    }

    /// Runs on a background thread so callers don't block their actor.
    static func runAsync(
        executable: URL,
        arguments: [String],
        currentDirectory: URL? = nil,
        environment: [String: String]? = nil,
        timeout: Duration
    ) async -> CommandOutput {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(returning: run(
                    executable: executable,
                    arguments: arguments,
                    currentDirectory: currentDirectory,
                    environment: environment,
                    timeout: timeout
                ))
            }
        }
    }
}

extension Duration {
    var timeInterval: TimeInterval {
        let (seconds, attoseconds) = components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
    }
}
