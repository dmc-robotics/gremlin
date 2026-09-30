import Foundation
import GremlinKit
import Synchronization
@testable import Gremlin

/// Records grot invocations and returns scripted output per subcommand.
final class FakeGrot: GrotRunning {
    struct Call: Equatable {
        let arguments: [String]
        let directory: URL
    }

    private struct Scripted {
        let output: CommandOutput
        let delay: Duration
    }

    private struct State {
        var calls: [Call] = []
        var results: [String: CommandOutput] = [:]
        /// One-off results, used in order before `results`
        var queued: [String: [Scripted]] = [:]
    }

    private let state = Mutex(State())

    var calls: [Call] { state.withLock { $0.calls } }

    func setResult(_ output: CommandOutput, for command: String) {
        state.withLock { $0.results[command] = output }
    }

    /// The next call of `command` waits `delay`, then returns `output`
    func enqueue(_ output: CommandOutput, after delay: Duration, for command: String) {
        state.withLock { $0.queued[command, default: []].append(Scripted(output: output, delay: delay)) }
    }

    func commands() -> [String] {
        calls.compactMap(\.arguments.first)
    }

    func run(_ arguments: [String], in directory: URL) async -> CommandOutput {
        let command = arguments.first ?? ""
        let scripted = state.withLock { state -> Scripted in
            state.calls.append(Call(arguments: arguments, directory: directory))
            if var queue = state.queued[command], !queue.isEmpty {
                let next = queue.removeFirst()
                state.queued[command] = queue
                return next
            }
            return Scripted(output: state.results[command] ?? CommandOutput(exitCode: 0), delay: .zero)
        }
        if scripted.delay > .zero {
            try? await Task.sleep(for: scripted.delay)
        }
        return scripted.output
    }

    func version() async -> String? { "1.0.0" }
}

final class FakePorts: SerialPortListing {
    private let ports: Mutex<[SerialPortInfo]>

    init(_ paths: [String] = []) {
        ports = Mutex(paths.map { SerialPortInfo(path: $0) })
    }

    func set(_ paths: [String]) {
        ports.withLock { $0 = paths.map { SerialPortInfo(path: $0) } }
    }

    func availablePorts() -> [SerialPortInfo] {
        ports.withLock { $0 }
    }
}

/// A connection whose incoming events the test drives.
final class FakeConnection: SerialConnectionProtocol {
    let events: AsyncStream<SerialEvent>
    let continuation: AsyncStream<SerialEvent>.Continuation
    private let state = Mutex<(writes: [String], closed: Bool, writeError: SerialError?)>(([], false, nil))

    init() {
        (events, continuation) = AsyncStream.makeStream(of: SerialEvent.self)
    }

    var writes: [String] { state.withLock { $0.writes } }
    var isClosed: Bool { state.withLock { $0.closed } }

    func failWrites(with error: SerialError) {
        state.withLock { $0.writeError = error }
    }

    func receive(_ lines: String...) {
        continuation.yield(.lines(lines.map { SerialLine(timestamp: .now, text: $0) }))
    }

    func write(_ text: String) async throws {
        try state.withLock { state in
            if let error = state.writeError { throw error }
            state.writes.append(text)
        }
    }

    func close() {
        state.withLock { $0.closed = true }
        continuation.finish()
    }
}

final class FakeConnector: SerialConnecting {
    private let state = Mutex<(opened: [(String, Int)], connection: FakeConnection?, error: SerialError?)>(([], nil, nil))

    var opened: [(path: String, baudRate: Int)] { state.withLock { $0.opened } }
    var lastConnection: FakeConnection? { state.withLock { $0.connection } }

    func failOpens(with error: SerialError) {
        state.withLock { $0.error = error }
    }

    func open(path: String, baudRate: Int) throws -> any SerialConnectionProtocol {
        try state.withLock { state in
            if let error = state.error { throw error }
            let connection = FakeConnection()
            state.opened.append((path, baudRate))
            state.connection = connection
            return connection
        }
    }
}

/// Polls until `condition` holds, letting main-actor tasks run in between.
@MainActor
func waitUntil(timeout: Duration = .seconds(2), _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        if ContinuousClock.now > deadline { return false }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return true
}

/// A temporary directory holding projects and a projects.json store.
final class TestWorkspace {
    let root: URL
    let store: ProjectStore

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "GremlinTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = ProjectStore(fileURL: root.appending(path: "projects.json"))
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    /// Creates `<name>/<name>.ino` and, if given, `<name>/.grotconfig`. Returns the directory path.
    @discardableResult
    func makeProject(_ name: String, grotConfig: String? = nil, sketch: Bool = true) throws -> String {
        let directory = root.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if sketch {
            try "".write(to: directory.appending(path: "\(name).ino"), atomically: true, encoding: .utf8)
        }
        if let grotConfig {
            try grotConfig.write(to: directory.appending(path: ".grotconfig"), atomically: true, encoding: .utf8)
        }
        return directory.path(percentEncoded: false)
    }

    func grotConfig(of name: String) throws -> String {
        try String(contentsOf: root.appending(path: "\(name)/.grotconfig"), encoding: .utf8)
    }
}
