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
    private static let env = URL(filePath: "/usr/bin/env")

    /// Name looked up on PATH, or an absolute path.
    public var executable: String
    public var environment: [String: String]
    public var timeout: Duration

    public init(
        executable: String = "grot",
        environment: [String: String] = ShellEnvironment.resolved,
        timeout: Duration = GrotRunner.defaultTimeout
    ) {
        self.executable = executable
        self.environment = environment
        self.timeout = timeout
    }

    public func run(_ arguments: [String], in directory: URL) async -> CommandOutput {
        // /usr/bin/env resolves the executable on our PATH and reports a clear
        // "No such file or directory" when grot isn't installed.
        await ProcessRunner.runAsync(
            executable: Self.env,
            arguments: [executable] + arguments,
            currentDirectory: directory,
            // grot only colors terminal output; the output panel renders its colors
            environment: environment.merging(["CLICOLOR_FORCE": "1"]) { _, forced in forced },
            timeout: timeout
        )
    }

    /// The version number reported by `grot --version`, or nil if grot can't be run.
    public func version() async -> String? {
        let output = await ProcessRunner.runAsync(
            executable: Self.env,
            arguments: [executable, "--version"],
            environment: environment,
            timeout: Self.versionTimeout
        )
        guard output.succeeded else { return nil }
        return Self.parseVersion(output.stdout.isEmpty ? output.stderr : output.stdout)
    }

    static func parseVersion(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.firstMatch(of: /\d+\.\d+[\.\d]*/).map { String($0.output) } ?? trimmed
    }
}
