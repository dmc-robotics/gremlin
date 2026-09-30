import Foundation

/// Project metadata persisted in `projects.json`.
public struct ProjectConfig: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    /// Absolute directory path
    public var path: String
    public var title: String
    public var description: String
    /// Milliseconds since 1970
    public var addedAt: Int64

    public init(id: String, path: String, title: String, description: String, addedAt: Int64) {
        self.id = id
        self.path = path
        self.title = title
        self.description = description
        self.addedAt = addedAt
    }

    public var url: URL { URL(filePath: path, directoryHint: .isDirectory) }

    /// Name of the project directory; grot expects `<directoryName>.ino` inside it.
    public var directoryName: String { url.lastPathComponent }

    public var sketchFileName: String { "\(directoryName).ino" }
}

/// Fields read from a `.grotconfig` (TOML) file.
public struct GrotConfig: Hashable, Sendable {
    public var fqbn: String
    public var port: String
    public var sketchPath: String
    public var baudRate: Int
    public var targetCore: String
    public var flashSplit: Double?

    public init(fqbn: String, port: String, sketchPath: String, baudRate: Int, targetCore: String, flashSplit: Double?) {
        self.fqbn = fqbn
        self.port = port
        self.sketchPath = sketchPath
        self.baudRate = baudRate
        self.targetCore = targetCore
        self.flashSplit = flashSplit
    }

    /// Teensy boards are loaded by teensy_loader and have no serial port to configure.
    public var isTeensy: Bool { fqbn.lowercased().hasPrefix("teensy:") }
}

/// Project metadata combined with what's currently on disk and which ports are plugged in.
public struct ProjectData: Identifiable, Hashable, Sendable {
    public var config: ProjectConfig
    public var grotConfig: GrotConfig?
    public var hasInoFile: Bool
    public var hasGrotConfig: Bool
    public var directoryAccessible: Bool
    public var portAvailable: Bool

    public init(
        config: ProjectConfig,
        grotConfig: GrotConfig?,
        hasInoFile: Bool,
        hasGrotConfig: Bool,
        directoryAccessible: Bool,
        portAvailable: Bool
    ) {
        self.config = config
        self.grotConfig = grotConfig
        self.hasInoFile = hasInoFile
        self.hasGrotConfig = hasGrotConfig
        self.directoryAccessible = directoryAccessible
        self.portAvailable = portAvailable
    }

    public var id: String { config.id }
}

/// Result of running a command-line tool.
public struct CommandOutput: Hashable, Sendable {
    public var exitCode: Int32
    public var stdout: String
    public var stderr: String

    public init(exitCode: Int32, stdout: String = "", stderr: String = "") {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }

    public var succeeded: Bool { exitCode == 0 }

    public static func failure(_ message: String) -> CommandOutput {
        CommandOutput(exitCode: 1, stderr: message)
    }
}
