import Foundation

public enum ProjectStoreError: LocalizedError, Equatable {
    case directoryNotFound
    case duplicatePath
    case projectNotFound

    public var errorDescription: String? {
        switch self {
        case .directoryNotFound: "Directory does not exist"
        case .duplicatePath: "Project at this path already exists"
        case .projectNotFound: "Project not found"
        }
    }
}

/// Persists the project list as JSON. Files on disk inside a project are never touched.
public struct ProjectStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// `~/Library/Application Support/MacServitor/projects.json`
    public static var defaultFileURL: URL {
        URL.applicationSupportDirectory
            .appending(path: "MacServitor", directoryHint: .isDirectory)
            .appending(path: "projects.json")
    }

    /// Returns an empty list if the file doesn't exist yet.
    public func load() throws -> [ProjectConfig] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        return try JSONDecoder().decode([ProjectConfig].self, from: Data(contentsOf: fileURL))
    }

    public func project(id: String) throws -> ProjectConfig {
        guard let project = try load().first(where: { $0.id == id }) else {
            throw ProjectStoreError.projectNotFound
        }
        return project
    }

    @discardableResult
    public func add(path: String, title: String, description: String, now: Date = .now) throws -> ProjectConfig {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ProjectStoreError.directoryNotFound
        }

        var projects = try load()
        guard !projects.contains(where: { $0.path == path }) else {
            throw ProjectStoreError.duplicatePath
        }

        let project = ProjectConfig(
            id: UUID().uuidString.lowercased(),
            path: path,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            addedAt: Int64(now.timeIntervalSince1970 * 1000)
        )
        projects.append(project)
        try save(projects)
        return project
    }

    @discardableResult
    public func update(id: String, title: String, description: String) throws -> ProjectConfig {
        var projects = try load()
        guard let index = projects.firstIndex(where: { $0.id == id }) else {
            throw ProjectStoreError.projectNotFound
        }
        projects[index].title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        projects[index].description = description.trimmingCharacters(in: .whitespacesAndNewlines)
        try save(projects)
        return projects[index]
    }

    public func remove(id: String) throws {
        var projects = try load()
        guard let index = projects.firstIndex(where: { $0.id == id }) else {
            throw ProjectStoreError.projectNotFound
        }
        projects.remove(at: index)
        try save(projects)
    }

    private func save(_ projects: [ProjectConfig]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        try encoder.encode(projects).write(to: fileURL, options: .atomic)
    }
}
