import Foundation
import Testing
@testable import ServitorKit

/// Inspector cases ported from the enrichProject tests in servitor/tests/main/project-manager.test.ts
struct ProjectInspectorTests {
    let temp: TemporaryDirectory
    let projectPath: String

    init() throws {
        temp = try TemporaryDirectory()
        projectPath = try temp.makeDirectory("blink")
    }

    private var config: ProjectConfig {
        ProjectConfig(id: "p1", path: projectPath, title: "Blink", description: "", addedAt: 0)
    }

    @Test func missingDirectoryIsInaccessible() {
        var missing = config
        missing.path = "/nonexistent/blink"
        let data = ProjectInspector.inspect(missing, availablePorts: [])
        #expect(!data.directoryAccessible)
        #expect(!data.hasInoFile)
        #expect(!data.hasGrotConfig)
        #expect(data.grotConfig == nil)
    }

    @Test func detectsSketchMatchingDirectoryName() throws {
        try temp.write("", to: "blink/blink.ino")
        let data = ProjectInspector.inspect(config, availablePorts: [])
        #expect(data.directoryAccessible)
        #expect(data.hasInoFile)
    }

    @Test func ignoresSketchWithOtherName() throws {
        try temp.write("", to: "blink/other.ino")
        #expect(!ProjectInspector.inspect(config, availablePorts: []).hasInoFile)
    }

    @Test func parsesGrotConfig() throws {
        try temp.write("fqbn = \"arduino:avr:uno\"\nport = \"/dev/cu.test\"", to: "blink/.grotconfig")
        let data = ProjectInspector.inspect(config, availablePorts: [])
        #expect(data.hasGrotConfig)
        #expect(data.grotConfig?.fqbn == "arduino:avr:uno")
        #expect(data.grotConfig?.port == "/dev/cu.test")
    }

    @Test func portAvailability() throws {
        try temp.write("port = \"/dev/cu.test\"", to: "blink/.grotconfig")
        #expect(ProjectInspector.inspect(config, availablePorts: ["/dev/cu.test"]).portAvailable)
        #expect(!ProjectInspector.inspect(config, availablePorts: ["/dev/cu.other"]).portAvailable)
    }

    @Test func noPortConfiguredIsUnavailable() throws {
        try temp.write("fqbn = \"arduino:avr:uno\"", to: "blink/.grotconfig")
        #expect(!ProjectInspector.inspect(config, availablePorts: [""]).portAvailable)
    }

    @Test func passesConfigThrough() {
        #expect(ProjectInspector.inspect(config, availablePorts: []).config == config)
    }

    @Test func trailingSlashStillFindsSketch() throws {
        try temp.write("", to: "blink/blink.ino")
        var slashed = config
        slashed.path = projectPath + "/"
        #expect(ProjectInspector.inspect(slashed, availablePorts: []).hasInoFile)
    }
}

struct ProjectStoreTests {
    let temp: TemporaryDirectory
    let store: ProjectStore
    let projectPath: String

    init() throws {
        temp = try TemporaryDirectory()
        store = ProjectStore(fileURL: temp.url.appending(path: "support/projects.json"))
        projectPath = try temp.makeDirectory("blink")
    }

    @Test func missingFileLoadsEmpty() throws {
        #expect(try store.load().isEmpty)
    }

    @Test func addPersistsTrimmedProject() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let added = try store.add(path: projectPath, title: "  Blink ", description: " LED\n", now: now)
        #expect(added.title == "Blink")
        #expect(added.description == "LED")
        #expect(added.addedAt == 1_700_000_000_000)
        #expect(try store.load() == [added])
    }

    @Test func addRejectsMissingDirectory() {
        #expect(throws: ProjectStoreError.directoryNotFound) {
            try store.add(path: "/nonexistent/dir", title: "X", description: "")
        }
    }

    @Test func addRejectsDuplicatePath() throws {
        try store.add(path: projectPath, title: "A", description: "")
        #expect(throws: ProjectStoreError.duplicatePath) {
            try store.add(path: projectPath, title: "B", description: "")
        }
    }

    @Test func addNormalizesPathSoDuplicatesAreCaught() throws {
        let trimmed = String(projectPath.dropLast())  // without the trailing slash
        let added = try store.add(path: "  \(projectPath)  ", title: "A", description: "")
        #expect(added.path == trimmed)
        #expect(throws: ProjectStoreError.duplicatePath) {
            try store.add(path: trimmed, title: "B", description: "")
        }
        #expect(throws: ProjectStoreError.duplicatePath) {
            try store.add(path: trimmed + "/../blink/", title: "C", description: "")
        }
    }

    @Test func normalizedPathExpandsTilde() {
        #expect(ProjectStore.normalizedPath("~/x/") == NSHomeDirectory() + "/x")
        #expect(ProjectStore.normalizedPath("/") == "/")
    }

    @Test func updateChangesTitleAndDescription() throws {
        let added = try store.add(path: projectPath, title: "A", description: "")
        let updated = try store.update(id: added.id, title: " B ", description: "desc")
        #expect(updated.title == "B")
        #expect(try store.project(id: added.id).description == "desc")
    }

    @Test func removeDeletesOnlyTheEntry() throws {
        let added = try store.add(path: projectPath, title: "A", description: "")
        try store.remove(id: added.id)
        #expect(try store.load().isEmpty)
        #expect(FileManager.default.fileExists(atPath: projectPath))
    }

    @Test func unknownIDThrows() {
        #expect(throws: ProjectStoreError.projectNotFound) { try store.update(id: "nope", title: "", description: "") }
        #expect(throws: ProjectStoreError.projectNotFound) { try store.remove(id: "nope") }
    }

    @Test func readsElectronFormat() throws {
        try FileManager.default.createDirectory(
            at: store.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let json = """
            [{"id": "abc", "path": "/x", "title": "T", "description": "D", "addedAt": 1712345678901}]
            """
        try json.write(to: store.fileURL, atomically: true, encoding: .utf8)
        #expect(try store.load() == [ProjectConfig(id: "abc", path: "/x", title: "T", description: "D", addedAt: 1_712_345_678_901)])
    }
}

struct ProjectWatcherTests {
    @Test func mapsRelevantFilesToProjects() throws {
        let temp = try TemporaryDirectory()
        let blink = try temp.makeDirectory("blink")
        let fade = try temp.makeDirectory("fade")
        let projects = [
            ProjectConfig(id: "b", path: blink, title: "", description: "", addedAt: 0),
            ProjectConfig(id: "f", path: fade, title: "", description: "", addedAt: 0)
        ]
        let ids = ProjectWatcher.changedProjectIDs(
            eventPaths: [
                ProjectWatcher.canonicalPath(blink + "/.grotconfig"),
                ProjectWatcher.canonicalPath(blink + "/notes.txt"),
                ProjectWatcher.canonicalPath(fade + "/blink.ino"),
                ProjectWatcher.canonicalPath(fade + "/fade.ino")
            ],
            projects: projects
        )
        #expect(ids == ["b", "f"])
    }

    @Test func rewatchingReplacesTheStream() async throws {
        let temp = try TemporaryDirectory()
        let blink = try temp.makeDirectory("blink")
        let fade = try temp.makeDirectory("fade")
        let (changes, continuation) = AsyncStream.makeStream(of: Set<String>.self)
        let watcher = ProjectWatcher(latency: 0.1) { continuation.yield($0) }
        watcher.watch([ProjectConfig(id: "b", path: blink, title: "", description: "", addedAt: 0)])
        watcher.watch([ProjectConfig(id: "f", path: fade, title: "", description: "", addedAt: 0)])
        defer { watcher.stop() }

        try await Task.sleep(for: .milliseconds(300))
        try temp.write("", to: "blink/.grotconfig")
        try temp.write("", to: "fade/.grotconfig")

        #expect(await firstValue(of: changes, timeout: .seconds(5)) == ["f"])
    }

    @Test func releasingAWatchingWatcherIsSafe() async throws {
        let temp = try TemporaryDirectory()
        let path = try temp.makeDirectory("blink")
        var watcher: ProjectWatcher? = ProjectWatcher(latency: 0.05) { _ in }
        watcher?.watch([ProjectConfig(id: "b", path: path, title: "", description: "", addedAt: 0)])
        try temp.write("", to: "blink/.grotconfig")
        watcher = nil
        // Events after release must not reach the freed watcher
        try temp.write("x", to: "blink/.grotconfig")
        try await Task.sleep(for: .milliseconds(300))
        #expect(watcher == nil)
    }

    @Test func canonicalPathResolvesVarSymlink() {
        #expect(ProjectWatcher.canonicalPath("/var/does-not-exist") == "/private/var/does-not-exist")
    }

    @Test func reportsFileChange() async throws {
        let temp = try TemporaryDirectory()
        let path = try temp.makeDirectory("blink")
        let project = ProjectConfig(id: "b", path: path, title: "", description: "", addedAt: 0)
        let (changes, continuation) = AsyncStream.makeStream(of: Set<String>.self)
        let watcher = ProjectWatcher(latency: 0.1) { continuation.yield($0) }
        watcher.watch([project])
        defer { watcher.stop() }

        // Give FSEvents a moment to start before touching the file
        try await Task.sleep(for: .milliseconds(300))
        try temp.write("port = \"/dev/x\"", to: "blink/.grotconfig")

        let received = await firstValue(of: changes, timeout: .seconds(5))
        #expect(received == ["b"])
    }
}

/// The stream's first value, or nil if none arrives within `timeout`.
func firstValue<T: Sendable>(of stream: AsyncStream<T>, timeout: Duration) async -> T? {
    await withTaskGroup(of: T?.self) { group in
        group.addTask {
            var iterator = stream.makeAsyncIterator()
            return await iterator.next()
        }
        group.addTask {
            try? await Task.sleep(for: timeout)
            return nil
        }
        let first = await group.next() ?? nil
        group.cancelAll()
        return first
    }
}
