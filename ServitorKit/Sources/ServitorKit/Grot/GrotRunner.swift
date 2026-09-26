import Foundation

/// Runs grot subcommands. A protocol so app models can be tested with a fake.
public protocol GrotRunning: Sendable {
    /// Runs `grot <arguments>` with `directory` as the working directory, so relative paths
    /// in `.grotconfig` resolve correctly.
    func run(_ arguments: [String], in directory: URL) async -> CommandOutput
    func version() async -> String?
}

public struct GrotRunner: GrotRunning {
    public static let defaultTimeout: Duration = .seconds(5 * 60)
    private static let versionTimeout: Duration = .seconds(5)

    /// Name looked up on PATH, or an absolute path.
    public var executable: String
    /// nil uses the login shell's environment (see `ShellEnvironment`).
    public var environment: [String: String]?
    public var timeout: Duration

    public init(
        executable: String = "grot",
        environment: [String: String]? = nil,
        timeout: Duration = GrotRunner.defaultTimeout
    ) {
        self.executable = executable
        self.environment = environment
        self.timeout = timeout
    }

    public func run(_ arguments: [String], in directory: URL) async -> CommandOutput {
        var environment = await resolvedEnvironment()
        // grot only colors terminal output; the output panel renders its colors
        environment["CLICOLOR_FORCE"] = "1"
        guard let grot = Self.locate(executable, path: environment["PATH"]) else {
            return .failure(notFoundMessage(path: environment["PATH"]))
        }
        return await ProcessRunner.runAsync(
            executable: grot,
            arguments: arguments,
            currentDirectory: directory,
            environment: environment,
            timeout: timeout
        )
    }

    /// The version number reported by `grot --version`, or nil if grot can't be run.
    public func version() async -> String? {
        let environment = await resolvedEnvironment()
        guard let grot = Self.locate(executable, path: environment["PATH"]) else { return nil }
        let output = await ProcessRunner.runAsync(
            executable: grot,
            arguments: ["--version"],
            environment: environment,
            timeout: Self.versionTimeout
        )
        guard output.succeeded else { return nil }
        return Self.parseVersion(output.stdout.isEmpty ? output.stderr : output.stdout)
    }

    /// Finds `name` in the absolute PATH directories only, so a project folder can never
    /// supply its own grot. A name containing "/" must be an absolute path.
    static func locate(_ name: String, path: String?) -> URL? {
        let candidates = name.contains("/")
            ? [name].filter { $0.hasPrefix("/") }
            : ShellEnvironment.absolutePATH(path ?? "").split(separator: ":").map { "\($0)/\(name)" }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }.map { URL(filePath: $0) }
    }

    static func parseVersion(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.firstMatch(of: /\d+\.\d+[\.\d]*/).map { String($0.output) } ?? trimmed
    }

    private func resolvedEnvironment() async -> [String: String] {
        var resolved: [String: String]
        if let environment {
            resolved = environment
        } else {
            resolved = await ShellEnvironment.resolved()
        }
        // grot runs arduino-cli from the project folder, so drop relative PATH entries there too
        resolved["PATH"] = ShellEnvironment.absolutePATH(resolved["PATH"] ?? "")
        return resolved
    }

    private func notFoundMessage(path: String?) -> String {
        "\(executable) not found. Install the grot gem, or check that it's on your login shell's PATH (\(path ?? ""))."
    }
}
