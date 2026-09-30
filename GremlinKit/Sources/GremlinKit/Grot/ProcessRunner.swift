import Foundation
import Synchronization

/// Runs a command-line tool to completion, capturing its output.
enum ProcessRunner {
    /// Time between SIGTERM and SIGKILL on timeout (interactive shells ignore SIGTERM),
    /// and how long to keep reading output after the process exits.
    static let gracePeriod: Duration = .seconds(2)

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
        // Read both pipes as data arrives so a chatty process can't fill one and block
        let stdout = OutputCollector(stdoutPipe)
        let stderr = OutputCollector(stderrPipe)

        do {
            try process.run()
        } catch {
            stdout.stop()
            stderr.stop()
            return .failure(error.localizedDescription)
        }

        let timedOut = Mutex(false)
        let pid = process.processIdentifier
        let timeoutWork = DispatchWorkItem {
            guard process.isRunning else { return }
            timedOut.withLock { $0 = true }
            process.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + gracePeriod.timeInterval) {
                guard process.isRunning else { return }
                // Include its children when it leads a process group; they may ignore SIGTERM too
                kill(getpgid(pid) == pid ? -pid : pid, SIGKILL)
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout.timeInterval, execute: timeoutWork)
        process.waitUntilExit()
        timeoutWork.cancel()

        // A background process it started (e.g. an agent launched from .zshrc) can keep the
        // pipes open after it exits, so only wait briefly for the rest of the output
        let outputDeadline = DispatchTime.now() + gracePeriod.timeInterval
        let outputData = stdout.finish(by: outputDeadline)
        var errorText = String(decoding: stderr.finish(by: outputDeadline), as: UTF8.self)
        if timedOut.withLock({ $0 }) {
            errorText += "\nTimed out after \(Int(timeout.timeInterval)) seconds"
        }
        return CommandOutput(
            exitCode: process.terminationStatus,
            stdout: String(decoding: outputData, as: UTF8.self),
            stderr: errorText
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

/// Accumulates everything written to a pipe until end of file.
private final class OutputCollector: Sendable {
    private let handle: FileHandle
    private let data = Mutex(Data())
    private let reachedEnd = DispatchSemaphore(value: 0)

    init(_ pipe: Pipe) {
        handle = pipe.fileHandleForReading
        handle.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard let self, !chunk.isEmpty else {
                handle.readabilityHandler = nil
                self?.reachedEnd.signal()
                return
            }
            data.withLock { $0.append(chunk) }
        }
    }

    /// Everything read so far, waiting until `deadline` for the writer to close the pipe.
    func finish(by deadline: DispatchTime) -> Data {
        _ = reachedEnd.wait(timeout: deadline)
        stop()
        return data.withLock { Data($0) }
    }

    func stop() {
        handle.readabilityHandler = nil
    }
}

extension Duration {
    var timeInterval: TimeInterval {
        let (seconds, attoseconds) = components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
    }
}
