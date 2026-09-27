import Foundation
import Observation
import GremlinKit

/// Which grot commands are running for a project.
struct ProjectOperations: Equatable {
    var building = false
    var loading = false
    var updatingPort = false

    var isBusy: Bool { building || loading || updatingPort }
}

/// One command's result in the output panel. The colored text is prepared once here
/// rather than on every redraw.
struct OutputEntry: Identifiable, Equatable {
    let id: Int
    let projectTitle: String
    let command: String
    let output: CommandOutput
    let timestamp: Date
    let stdoutText: AttributedString
    let stderrText: AttributedString

    init(id: Int, projectTitle: String, command: String, output: CommandOutput, timestamp: Date) {
        self.id = id
        self.projectTitle = projectTitle
        self.command = command
        self.output = CommandOutput(
            exitCode: output.exitCode,
            stdout: Self.limited(output.stdout),
            stderr: Self.limited(output.stderr)
        )
        self.timestamp = timestamp
        stdoutText = ANSIText.attributedString(self.output.stdout)
        stderrText = ANSIText.attributedString(self.output.stderr)
    }

    /// Keeps the end of very long output, where errors usually are
    private static func limited(_ text: String) -> String {
        guard text.count > OutputLog.maxCharactersPerStream else { return text }
        return "… earlier output omitted …\n" + text.suffix(OutputLog.maxCharactersPerStream)
    }
}

/// State and actions for the Projects page.
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

    @ObservationIgnored private var hasLoaded = false
    @ObservationIgnored private var nextLogID = 1
    /// Bumped per project for each validation, so only the newest result is kept
    @ObservationIgnored private var validationGeneration: [String: Int] = [:]
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

    /// Loads projects the first time the Projects page appears; file changes keep them current after that.
    func loadProjectsIfNeeded() async {
        guard !hasLoaded else { return }
        await loadProjects()
    }

    /// Reloads projects from disk (e.g. after plugging in a board), then validates their configs.
    func loadProjects() async {
        hasLoaded = true
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

    /// Adds the project and starts validating its config in the background.
    func addProject(path: String, title: String, description: String) throws {
        let config = try store.add(path: path, title: title, description: description)
        projects.append(ProjectInspector.inspect(config, availablePorts: availablePortPaths()))
        restartWatcher()
        Task { await validateConfig(id: config.id) }
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
        validationGeneration[id] = nil
        restartWatcher()
    }

    /// Re-reads a project after its `.grotconfig` or sketch changed on disk.
    func projectFilesChanged(id: String) async {
        guard let index = index(of: id) else { return }
        let hadConfig = projects[index].hasGrotConfig
        let data = ProjectInspector.inspect(projects[index].config, availablePorts: availablePortPaths())
        projects[index] = data
        if data.portAvailable {
            portScanErrors[id] = nil
        }

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
        let generation = validationGeneration[id, default: 0] + 1
        validationGeneration[id] = generation

        let output = await runGrot("validate", for: project.config)
        // A newer validation started meanwhile, or the project was removed
        guard validationGeneration[id] == generation else { return }

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
        setOperation(\.building, true, for: id)
        defer { setOperation(\.building, false, for: id) }

        let output = await runGrot("build", for: project.config)
        appendOutput(projectTitle: project.config.title, command: "build", output: output)
    }

    func loadToBoard(id: String) async {
        guard let project = project(id) else { return }
        setOperation(\.loading, true, for: id)
        defer { setOperation(\.loading, false, for: id) }

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
    /// Not while building or loading, which read that file.
    func updatePort(id: String) async {
        guard let project = project(id), !operations(for: id).isBusy else { return }
        setOperation(\.updatingPort, true, for: id)
        defer { setOperation(\.updatingPort, false, for: id) }

        let title = project.config.title
        do {
            guard let port = ports.availablePorts().first(where: \.isLikelyArduino)?.path else {
                throw PortScanError.noArduinoFound
            }
            try GrotConfigParser.writePort(port, toConfigAt: ProjectInspector.grotConfigURL(for: project.config))

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

    /// Keeps the most recent `OutputLog.maxEntries` entries.
    func appendOutput(projectTitle: String, command: String, output: CommandOutput) {
        outputLog.append(OutputEntry(
            id: nextLogID,
            projectTitle: projectTitle,
            command: command,
            output: output,
            timestamp: .now
        ))
        nextLogID += 1
        if outputLog.count > OutputLog.maxEntries {
            outputLog.removeFirst(outputLog.count - OutputLog.maxEntries)
        }
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

    /// Records an operation's state, unless the project was removed while it ran
    private func setOperation(_ keyPath: WritableKeyPath<ProjectOperations, Bool>, _ value: Bool, for id: String) {
        guard index(of: id) != nil else { return }
        operations[id, default: ProjectOperations()][keyPath: keyPath] = value
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
        guard let index = index(of: id) else { return }
        projects[index].portAvailable = false
        portScanErrors[id] = reason
    }

    private func restartWatcher() {
        guard watchesFiles else { return }
        watcher.watch(projects.map(\.config))
    }
}
