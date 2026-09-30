import Foundation

/// Combines stored project metadata with the current state of the project directory.
public enum ProjectInspector {
    /// - Parameter availablePorts: callout paths of the serial ports currently plugged in.
    public static func inspect(_ config: ProjectConfig, availablePorts: Set<String>) -> ProjectData {
        var grotConfig: GrotConfig?
        var hasInoFile = false
        var hasGrotConfig = false
        var directoryAccessible = false

        if let entries = try? FileManager.default.contentsOfDirectory(atPath: config.path) {
            directoryAccessible = true
            hasInoFile = entries.contains(config.sketchFileName)
            hasGrotConfig = entries.contains(GrotConfigParser.fileName)

            if hasGrotConfig,
               let content = try? String(contentsOf: grotConfigURL(for: config), encoding: .utf8) {
                grotConfig = GrotConfigParser.parse(content)
            }
        }

        let port = grotConfig?.port ?? ""
        return ProjectData(
            config: config,
            grotConfig: grotConfig,
            hasInoFile: hasInoFile,
            hasGrotConfig: hasGrotConfig,
            directoryAccessible: directoryAccessible,
            portAvailable: !port.isEmpty && availablePorts.contains(port)
        )
    }

    public static func grotConfigURL(for config: ProjectConfig) -> URL {
        config.url.appending(path: GrotConfigParser.fileName)
    }

    public static func sketchURL(for config: ProjectConfig) -> URL {
        config.url.appending(path: config.sketchFileName)
    }
}
