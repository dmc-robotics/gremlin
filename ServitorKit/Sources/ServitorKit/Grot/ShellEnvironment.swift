import Foundation

/// Apps launched from Finder or the Dock don't inherit the user's shell PATH, so Ruby gems
/// like grot aren't found. This reads PATH from the user's login shell, once, off the main thread.
public enum ShellEnvironment {
    private static let timeout: Duration = .seconds(5)
    private static let pathMarker = "__MACSERVITOR_PATH__"

    /// Started on first use and shared by every caller afterwards
    private static let resolution = Task.detached(priority: .userInitiated) { resolve() }

    /// The process environment with PATH taken from the login shell (when it can be read)
    /// and limited to absolute directories.
    public static func resolved() async -> [String: String] {
        await resolution.value
    }

    static func resolve() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = absolutePATH(loginShellPATH() ?? environment["PATH"] ?? "")
        return environment
    }

    static func loginShellPATH() -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        // -l and -i together source both .zprofile and .zshrc; rbenv and similar tools
        // usually initialize in .zshrc. The marker separates PATH from anything the rc files print.
        let output = ProcessRunner.run(
            executable: URL(filePath: shell),
            arguments: ["-l", "-i", "-c", #"printf '\n%s%s\n' "$0" "$PATH""#, pathMarker],
            timeout: timeout
        )
        guard output.succeeded else { return nil }
        return parsePATH(output.stdout)
    }

    static func parsePATH(_ output: String) -> String? {
        output.split(separator: "\n")
            .last { $0.hasPrefix(pathMarker) }
            .map { String($0.dropFirst(pathMarker.count)) }
            .flatMap { $0.isEmpty ? nil : $0 }
    }

    /// PATH without relative entries (".", "bin", or empty), which would otherwise find
    /// programs in whatever directory a command runs in, such as a project folder.
    public static func absolutePATH(_ path: String) -> String {
        path.split(separator: ":").filter { $0.hasPrefix("/") }.joined(separator: ":")
    }
}
