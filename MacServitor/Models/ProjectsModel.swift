import Foundation
import Observation
import ServitorKit

/// Which grot commands are running for a project.
struct ProjectOperations: Equatable {
    var building = false
    var loading = false
    var updatingPort = false

    var isBusy: Bool { building || loading || updatingPort }
}

/// One command's result in the output panel.
struct OutputEntry: Identifiable, Equatable {
    let id: Int
    let projectTitle: String
    let command: String
    let output: CommandOutput
    let timestamp: Date
}

/// State and actions for the Projects page. Port of servitor's `stores/dashboard.ts`.
@MainActor
@Observable
final class ProjectsModel {
    private(set) var projects: [ProjectData] = []
    private(set) var isLoading = false
    private(set) var loadError: String?
    private(set) var operations: [String: ProjectOperations] = [:]
    /// Latest port problem per project, shown as the Port badge tooltip.
    private(set) var portScanErrors: [String: String] = [:]
    /// `grot validate` result per project; missing while validation is pending.
    private(set) var configValidation: [String: Bool] = [:]
    private(set) var outputLog: [OutputEntry] = []

    /// Called with a project's baud rate after it is loaded onto the board,
    /// so the Serial page defaults to it.
    @ObservationIgnored var onProjectLoaded: ((Int) -> Void)?

    @ObservationIgnored private var nextLogID = 1
    @ObservationIgnored private let store: ProjectStore
    @ObservationIgnored private let grot: any GrotRunning
    @ObservationIgnored private let ports: any SerialPortListing
    @ObservationIgnored private let watchesFiles: Bool
    @ObservationIgnored private lazy var watcher = ProjectWatcher { [weak self] ids in
        Task { @MainActor in
            for id in ids {
                await self?.projectFilesChanged(id: id)
            }
        }
    }

    init(
        store: ProjectStore = ProjectStore(fileURL: ProjectStore.defaultFileURL),
        grot: any GrotRunning = GrotRunner(),
        ports: any SerialPortListing = SerialPortDiscovery(),
        watchesFiles: Bool = true
    ) {
        self.store = store
        self.grot = grot
        self.ports = ports
        self.watchesFiles = watchesFiles
    }

    func operations(for id: String) -> ProjectOperations {
        operations[id] ?? ProjectOperations()
    }

    // MARK: - Project list

    /// Reloads projects from disk, then validates their configs.
    func loadProjects() async {
        isLoading = true
        do {
            let available = availablePortPaths()
            projects = try store.load().map { ProjectInspector.inspect($0, availablePorts: available) }
            portScanErrors = [:]
            loadError = nil
        } catch {
            loadError = "Could not read projects: \(error.localizedDescription)"
        }
        isLoading = false
        restartWatcher()
        await validateAllConfigs()
    }

    func addProject(path: String, title: String, description: String) async throws {
        let config = try store.add(path: path, title: title, description: description)
        projects.append(ProjectInspector.inspect(config, availablePorts: availablePortPaths()))
        restartWatcher()
        await validateConfig(id: config.id)
    }

    func updateProject(id: String, title: String, description: String) throws {
        let config = try store.update(id: id, title: title, description: description)
        guard let index = index(of: id) else { return }
        projects[index].config = config
    }

    func removeProject(id: String) throws {
        try store.remove(id: id)
        projects.removeAll { $0.id == id }
        operations[id] = nil
        portScanErrors[id] = nil
        configValidation[id] = nil
        restartWatcher()
    }

    /// Re-reads a project after its `.grotconfig` or sketch changed on disk.
    func projectFilesChanged(id: String) async {
        guard let index = index(of: id) else { return }
        let hadConfig = projects[index].hasGrotConfig
        let data = ProjectInspector.inspect(projects[index].config, availablePorts: availablePortPaths())
        projects[index] = data

        if data.hasGrotConfig {
            await validateConfig(id: id)
        } else if hadConfig {
            configValidation[id] = nil
        }
    }

    // MARK: - grot commands

    func validateConfig(id: String) async {
        guard let project = project(id), project.hasGrotConfig else {
            configValidation[id] = nil
            return
        }
        let output = await runGrot("validate", for: project.config)
        configValidation[id] = output.succeeded
        if !output.succeeded {
            appendOutput(projectTitle: project.config.title, command: "validate", output: output)
        }
    }

    func validateAllConfigs() async {
        await withTaskGroup(of: Void.self) { group in
            for project in projects where project.hasGrotConfig {
                group.addTask { await self.validateConfig(id: project.id) }
            }
        }
    }

    func buildProject(id: String) async {
        guard let project = project(id) else { return }
        operations[id, default: ProjectOperations()].building = true
        defer { operations[id, default: ProjectOperations()].building = false }

        let output = await runGrot("build", for: project.config)
        appendOutput(projectTitle: project.config.title, command: "build", output: output)
    }

    func loadToBoard(id: String) async {
        guard let project = project(id) else { return }
        operations[id, default: ProjectOperations()].loading = true
        defer { operations[id, default: ProjectOperations()].loading = false }

        // Teensy boards are loaded without a serial port
        if project.grotConfig?.isTeensy != true, let problem = portProblem(for: project.config) {
            markPortUnavailable(id: id, reason: problem)
            appendOutput(projectTitle: project.config.title, command: "load", output: .failure(problem))
            return
        }

        let output = await runGrot("load", for: project.config)
        appendOutput(projectTitle: project.config.title, command: "load", output: output)
        if output.succeeded, let baudRate = project.grotConfig?.baudRate {
            onProjectLoaded?(baudRate)
        }
    }

    /// Finds the most likely Arduino port and writes it to the project's `.grotconfig`.
    func updatePort(id: String) async {
        guard let project = project(id) else { return }
        operations[id, default: ProjectOperations()].updatingPort = true
        defer { operations[id, default: ProjectOperations()].updatingPort = false }

        let title = project.config.title
        do {
            guard let port = ports.availablePorts().first(where: \.isLikelyArduino)?.path else {
                throw PortScanError.noArduinoFound
            }
            let configURL = ProjectInspector.grotConfigURL(for: project.config)
            let content = try String(contentsOf: configURL, encoding: .utf8)
            try GrotConfigParser.updatingPort(in: content, to: port)
                .write(to: configURL, atomically: true, encoding: .utf8)

            if let index = index(of: id) {
                projects[index].grotConfig?.port = port
                projects[index].portAvailable = true
            }
            portScanErrors[id] = nil
            appendOutput(projectTitle: title, command: "update-port", output: CommandOutput(exitCode: 0, stdout: "Port updated to \(port)"))
        } catch {
            markPortUnavailable(id: id, reason: error.localizedDescription)
            appendOutput(projectTitle: title, command: "update-port", output: .failure(error.localizedDescription))
        }
    }

    // MARK: - Output log

    func appendOutput(projectTitle: String, command: String, output: CommandOutput) {
        outputLog.append(OutputEntry(
            id: nextLogID,
            projectTitle: projectTitle,
            command: command,
            output: output,
            timestamp: .now
        ))
        nextLogID += 1
    }

    func clearOutput() {
        outputLog = []
    }

    // MARK: - Helpers

    private enum PortScanError: LocalizedError {
        case noArduinoFound

        var errorDescription: String? {
            "No Arduino-like port found. Connect your device and try again."
        }
    }

    private func project(_ id: String) -> ProjectData? {
        projects.first { $0.id == id }
    }

    private func index(of id: String) -> Int? {
        projects.firstIndex { $0.id == id }
    }

    private func availablePortPaths() -> Set<String> {
        Set(ports.availablePorts().map(\.path))
    }

    private func runGrot(_ command: String, for config: ProjectConfig) async -> CommandOutput {
        let configPath = ProjectInspector.grotConfigURL(for: config).path(percentEncoded: false)
        return await grot.run([command, "-c", configPath], in: config.url)
    }

    /// Why the configured port can't be used right now, reading `.grotconfig` fresh from disk.
    private func portProblem(for config: ProjectConfig) -> String? {
        let configURL = ProjectInspector.grotConfigURL(for: config)
        guard let content = try? String(contentsOf: configURL, encoding: .utf8) else {
            return "No .grotconfig file found in project directory"
        }
        let port = GrotConfigParser.parse(content).port
        if port.isEmpty {
            return "No port configured. Use \"Scan Port\" to detect your Arduino."
        }
        if !availablePortPaths().contains(port) {
            return "Port \"\(port)\" is not connected. Plug in your Arduino and try again."
        }
        return nil
    }

    private func markPortUnavailable(id: String, reason: String) {
        if let index = index(of: id) {
            projects[index].portAvailable = false
        }
        portScanErrors[id] = reason
    }

    private func restartWatcher() {
        guard watchesFiles else { return }
        watcher.watch(projects.map(\.config))
    }
}
