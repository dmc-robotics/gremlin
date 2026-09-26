import CoreServices
import Foundation
import Synchronization

/// Watches project directories for changes to `.grotconfig` or `<dir>.ino` using FSEvents.
/// FSEvents coalesces bursts of events (e.g. an editor's save-then-rename) within `latency`,
/// so no separate debounce is needed.
public final class ProjectWatcher: Sendable {
    public typealias ChangeHandler = @Sendable (Set<String>) -> Void

    /// FSEventStreamRef is thread-safe to stop and release; it's only created and torn down here.
    private struct Stream: @unchecked Sendable {
        let ref: FSEventStreamRef
    }

    private struct State {
        var stream: Stream?
        var projects: [ProjectConfig] = []
    }

    private let latency: TimeInterval
    private let onChange: ChangeHandler
    private let queue = DispatchQueue(label: "ProjectWatcher")
    private let state = Mutex(State())

    /// - Parameter onChange: called on a background queue with the IDs of projects whose
    ///   relevant files changed.
    public init(latency: TimeInterval = 0.5, onChange: @escaping ChangeHandler) {
        self.latency = latency
        self.onChange = onChange
    }

    deinit {
        stop()
    }

    /// Replaces the set of watched projects.
    public func watch(_ projects: [ProjectConfig]) {
        stop()
        let paths = projects.map(\.path).filter { FileManager.default.fileExists(atPath: $0) }
        guard !paths.isEmpty else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes
        )
        guard let stream = FSEventStreamCreate(
            nil,
            { _, info, count, eventPaths, _, _ in
                guard let info else { return }
                let watcher = Unmanaged<ProjectWatcher>.fromOpaque(info).takeUnretainedValue()
                let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] ?? []
                watcher.handle(Array(paths.prefix(count)))
            },
            &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            flags
        ) else { return }

        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        state.withLock {
            $0.stream = Stream(ref: stream)
            $0.projects = projects
        }
    }

    public func stop() {
        let stream = state.withLock { state -> Stream? in
            defer {
                state.stream = nil
                state.projects = []
            }
            return state.stream
        }
        guard let stream else { return }
        FSEventStreamStop(stream.ref)
        FSEventStreamInvalidate(stream.ref)
        FSEventStreamRelease(stream.ref)
    }

    private func handle(_ eventPaths: [String]) {
        let projects = state.withLock { $0.projects }
        let changed = Self.changedProjectIDs(eventPaths: eventPaths, projects: projects)
        if !changed.isEmpty {
            onChange(changed)
        }
    }

    /// Maps FSEvents file paths to the IDs of projects whose relevant files they touch.
    /// FSEvents reports canonical paths, so project paths are canonicalized before comparing.
    static func changedProjectIDs(eventPaths: [String], projects: [ProjectConfig]) -> Set<String> {
        var relevant: [String: String] = [:]
        for project in projects {
            let directory = canonicalPath(project.path)
            relevant["\(directory)/\(GrotConfigParser.fileName)"] = project.id
            relevant["\(directory)/\(project.sketchFileName)"] = project.id
        }
        return Set(eventPaths.compactMap { relevant[canonicalPath($0)] })
    }

    /// Resolves symlinks (e.g. `/var` → `/private/var`) for paths that exist.
    /// Paths that don't exist (e.g. a deleted file) resolve through their parent directory.
    static func canonicalPath(_ path: String) -> String {
        if let resolved = realpath(path, nil) {
            defer { free(resolved) }
            return String(cString: resolved)
        }
        let url = URL(filePath: path)
        let parent = url.deletingLastPathComponent().path(percentEncoded: false)
        guard let resolvedParent = realpath(parent, nil) else { return path }
        defer { free(resolvedParent) }
        return String(cString: resolvedParent) + "/" + url.lastPathComponent
    }
}
