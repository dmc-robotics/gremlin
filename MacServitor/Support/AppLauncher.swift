import AppKit

/// Opens files and folders in the terminal or editor chosen in Settings.
@MainActor
enum AppLauncher {
    static func open(_ url: URL, withAppAt appPath: String) {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            showError("“\(url.lastPathComponent)” doesn't exist.", detail: url.path(percentEncoded: false))
            return
        }
        NSWorkspace.shared.open(
            [url],
            withApplicationAt: URL(filePath: appPath),
            configuration: NSWorkspace.OpenConfiguration()
        ) { _, error in
            guard let error else { return }
            Task { @MainActor in
                showError("Couldn't open “\(url.lastPathComponent)”.", detail: error.localizedDescription)
            }
        }
    }

    /// "Terminal" for "/System/Applications/Utilities/Terminal.app"
    static func displayName(ofAppAt path: String) -> String {
        FileManager.default.displayName(atPath: path).replacing(/\.app$/, with: "")
    }

    private static func showError(_ message: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.alertStyle = .warning
        alert.runModal()
    }
}
