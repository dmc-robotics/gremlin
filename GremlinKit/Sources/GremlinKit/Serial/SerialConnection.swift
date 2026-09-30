import Darwin
import Foundation
import Synchronization

/// A line received from the device, without its line ending.
public struct SerialLine: Hashable, Sendable {
    public var timestamp: Date
    public var text: String

    public init(timestamp: Date, text: String) {
        self.timestamp = timestamp
        self.text = text
    }
}

public enum SerialEvent: Sendable {
    /// Every complete line from one read, delivered together so the UI updates once per batch.
    case lines([SerialLine])
    /// The device went away (unplugged, read error). Not sent after `close()`.
    case disconnected(reason: String)
}

public enum SerialError: LocalizedError, Equatable {
    case openFailed(path: String, reason: String)
    case configureFailed(String)
    case writeFailed(String)
    case closed

    public var errorDescription: String? {
        switch self {
        case let .openFailed(path, reason): "Could not open \(path): \(reason)"
        case let .configureFailed(reason): "Could not configure port: \(reason)"
        case let .writeFailed(reason): "Write failed: \(reason)"
        case .closed: "Not connected to a serial port"
        }
    }
}

/// An open serial connection. A protocol so app models can be tested with a fake.
public protocol SerialConnectionProtocol: AnyObject, Sendable {
    var events: AsyncStream<SerialEvent> { get }
    func write(_ text: String) async throws
    func close()
}

/// Opens serial connections. A protocol so app models can be tested with a fake.
public protocol SerialConnecting: Sendable {
    func open(path: String, baudRate: Int) throws -> any SerialConnectionProtocol
}

public struct SerialConnector: SerialConnecting {
    public init() {}

    public func open(path: String, baudRate: Int) throws -> any SerialConnectionProtocol {
        try SerialConnection(path: path, baudRate: baudRate)
    }
}

/// A POSIX serial port: raw 8N1, no flow control, newline-framed reads.
///
/// Opening the device raises DTR, which resets most Arduino boards. HUPCL (left on) lowers
/// it again on close.
public final class SerialConnection: SerialConnectionProtocol {
    /// Highest rate `cfsetspeed` accepts on macOS; faster rates need `IOSSIOSPEED`.
    private static let maxStandardBaudRate = 230_400
    /// `_IOW('T', 2, speed_t)` from IOKit/serial/ioss.h (function-like macros aren't imported)
    private static let IOSSIOSPEED: UInt = 0x8008_5402
    /// `_IO('t', 13)` from sys/ttycom.h: exclusive use, so a second opener gets EBUSY
    private static let TIOCEXCL: UInt = 0x2000_740D
    private static let readChunkSize = 4096
    /// Chunks read per wake-up, so a very fast device can't keep the read queue busy forever
    private static let maxChunksPerRead = 16
    /// Longest a single write may wait for the device to accept data
    private static let writeTimeout: TimeInterval = 2

    public let events: AsyncStream<SerialEvent>

    private let fd: Int32
    private let readQueue: DispatchQueue
    /// Separate from reads, so a device that stops accepting data can't stall incoming lines.
    /// The fd is closed on this queue, after any write in progress.
    private let writeQueue: DispatchQueue
    private let continuation: AsyncStream<SerialEvent>.Continuation
    private let readSource: DispatchSourceRead
    private let isClosed = Mutex(false)
    /// Only touched on `readQueue`
    nonisolated(unsafe) private var framer = LineFramer()

    public init(path: String, baudRate: Int) throws {
        // O_NONBLOCK so open doesn't wait for carrier detect, and so reads never block the queue
        let fd = Darwin.open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard fd >= 0 else {
            throw SerialError.openFailed(path: path, reason: Self.errnoDescription())
        }
        do {
            try Self.configure(fd, baudRate: baudRate)
        } catch {
            Darwin.close(fd)
            throw error
        }

        self.fd = fd
        readQueue = DispatchQueue(label: "SerialConnection.read \(path)")
        writeQueue = DispatchQueue(label: "SerialConnection.write \(path)")
        (events, continuation) = AsyncStream.makeStream(of: SerialEvent.self)
        readSource = DispatchSource.makeReadSource(fileDescriptor: fd, queue: readQueue)

        readSource.setEventHandler { [weak self] in self?.readAvailable() }
        readSource.setCancelHandler { [writeQueue] in
            writeQueue.async { Darwin.close(fd) }
        }
        readSource.activate()
    }

    deinit {
        close()
    }

    public func write(_ text: String) async throws {
        let bytes = Array(text.utf8)
        try await withCheckedThrowingContinuation { (result: CheckedContinuation<Void, Error>) in
            writeQueue.async { [self] in
                result.resume(with: Result { try writeAll(bytes) })
            }
        }
    }

    /// Closes the port without sending `.disconnected`. Safe to call more than once.
    public func close() {
        guard markClosed() else { return }
        readSource.cancel()
        continuation.finish()
    }

    /// Returns true if this call closed the connection.
    private func markClosed() -> Bool {
        isClosed.withLock { closed in
            defer { closed = true }
            return !closed
        }
    }

    // MARK: - Reading (on `readQueue`)

    private func readAvailable() {
        var buffer = [UInt8](repeating: 0, count: Self.readChunkSize)
        var received: [UInt8] = []
        // Anything left after the last chunk triggers the read source again
        for _ in 0..<Self.maxChunksPerRead {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
            if count > 0 {
                received.append(contentsOf: buffer[0..<count])
            } else if count < 0 && (errno == EAGAIN || errno == EINTR) {
                break
            } else {
                // 0 = end of file (device gone); < 0 = error such as ENXIO after unplug
                let reason = count == 0 ? "Port closed" : Self.errnoDescription()
                emit(framer.append(received))
                lost(reason)
                return
            }
        }
        emit(framer.append(received))
    }

    private func emit(_ lines: [SerialLine]) {
        if !lines.isEmpty {
            continuation.yield(.lines(lines))
        }
    }

    private func lost(_ reason: String) {
        guard markClosed() else { return }
        continuation.yield(.disconnected(reason: reason))
        continuation.finish()
        readSource.cancel()
    }

    // MARK: - Writing (on `writeQueue`)

    private func writeAll(_ bytes: [UInt8]) throws {
        let deadline = Date.now.addingTimeInterval(Self.writeTimeout)
        var offset = 0
        while offset < bytes.count {
            guard !isClosed.withLock({ $0 }) else { throw SerialError.closed }
            let written = bytes[offset...].withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
            if written >= 0 {
                offset += written
            } else if errno == EAGAIN {
                // Output buffer full: wait until the port can take more, up to the deadline
                let remaining = Int32(deadline.timeIntervalSinceNow * 1000)
                var pollDescriptor = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
                if remaining <= 0 || poll(&pollDescriptor, 1, remaining) <= 0 {
                    throw SerialError.writeFailed("Timed out: the device isn't reading")
                }
            } else if errno != EINTR {
                throw SerialError.writeFailed(Self.errnoDescription())
            }
        }
    }

    // MARK: - Setup

    private static func configure(_ fd: Int32, baudRate: Int) throws {
        guard ioctl(fd, TIOCEXCL) == 0 else {
            throw SerialError.configureFailed(errnoDescription())
        }

        var options = termios()
        guard tcgetattr(fd, &options) == 0 else {
            throw SerialError.configureFailed(errnoDescription())
        }
        cfmakeraw(&options)
        options.c_cflag |= tcflag_t(CLOCAL | CREAD | CS8)
        options.c_cflag &= ~tcflag_t(PARENB | CSTOPB | CRTSCTS)

        let isStandardRate = baudRate <= maxStandardBaudRate
        cfsetspeed(&options, speed_t(isStandardRate ? baudRate : Int(B9600)))
        guard tcsetattr(fd, TCSANOW, &options) == 0 else {
            throw SerialError.configureFailed(errnoDescription())
        }

        if !isStandardRate {
            var speed = speed_t(baudRate)
            guard ioctl(fd, IOSSIOSPEED, &speed) == 0 else {
                throw SerialError.configureFailed("\(baudRate) baud: \(errnoDescription())")
            }
        }
        tcflush(fd, TCIOFLUSH)
    }

    private static func errnoDescription() -> String {
        String(cString: strerror(errno))
    }
}
