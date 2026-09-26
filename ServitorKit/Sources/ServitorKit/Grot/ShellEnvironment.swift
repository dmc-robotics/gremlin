import Foundation

/// Apps launched from Finder or the Dock don't inherit the user's shell PATH, so Ruby gems
/// like grot aren't found. This reads PATH from the user's login shell once.
public enum ShellEnvironment {
    private static let timeout: Duration = .seconds(5)

    /// The process environment with PATH taken from the login shell (when it can be read).
    public static let resolved: [String: String] = {
        var environment = ProcessInfo.processInfo.environment
        if let path = loginShellPATH() {
            environment["PATH"] = path
        }
        return environment
    }()

    static func loginShellPATH() -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        // -l and -i together source both .zprofile and .zshrc; rbenv and similar tools
        // usually initialize in .zshrc.
        let output = ProcessRunner.run(
            executable: URL(filePath: shell),
            arguments: ["-l", "-i", "-c", "env"],
            timeout: timeout
        )
        guard output.succeeded else { return nil }
        return parsePATH(fromEnv: output.stdout)
    }

    static func parsePATH(fromEnv output: String) -> String? {
        let pattern = /^PATH=(.+)$/.anchorsMatchLineEndings()
        return output.firstMatch(of: pattern).map { String($0.1) }
    }
}
