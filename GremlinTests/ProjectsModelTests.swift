import Foundation
import GremlinKit
import Testing
@testable import Gremlin

@MainActor
struct ProjectsModelTests {
    let workspace: TestWorkspace
    let grot = FakeGrot()
    let ports = FakePorts(["/dev/cu.usbmodem1"])
    let model: ProjectsModel

    static let unoConfig = """
        fqbn = "arduino:avr:uno"
        port = "/dev/cu.usbmodem1"
        baud_rate = 57600
        """

    init() throws {
        workspace = try TestWorkspace()
        model = ProjectsModel(store: workspace.store, grot: grot, ports: ports, watchesFiles: false)
    }

    /// Adds a project to the store and loads the model.
    @discardableResult
    private func addProject(_ name: String, grotConfig: String? = unoConfig) async throws -> String {
        let path = try workspace.makeProject(name, grotConfig: grotConfig)
        let id = try workspace.store.add(path: path, title: name, description: "").id
        await model.loadProjects()
        return id
    }

    // MARK: Loading

    @Test func loadPopulatesInspectedProjects() async throws {
        let id = try await addProject("blink")
        #expect(model.projects.map(\.id) == [id])
        #expect(model.projects[0].hasInoFile)
        #expect(model.projects[0].portAvailable)
        #expect(!model.isLoading)
    }

    @Test func loadValidatesConfigs() async throws {
        let id = try await addProject("blink")
        #expect(model.configValidation[id] == true)
        #expect(grot.commands() == ["validate"])
        #expect(model.outputLog.isEmpty)
    }

    @Test func failedValidationIsLogged() async throws {
        grot.setResult(CommandOutput(exitCode: 1, stderr: "missing fqbn"), for: "validate")
        let id = try await addProject("blink")
        #expect(model.configValidation[id] == false)
        #expect(model.outputLog.map(\.command) == ["validate"])
    }

    @Test func projectsWithoutConfigAreNotValidated() async throws {
        let id = try await addProject("blink", grotConfig: nil)
        #expect(model.configValidation[id] == nil)
        #expect(grot.calls.isEmpty)
    }

    @Test func grotRunsWithConfigPathInProjectDirectory() async throws {
        let id = try await addProject("blink")
        let call = try #require(grot.calls.first)
        let project = try #require(model.projects.first { $0.id == id })
        #expect(call.arguments == ["validate", "-c", ProjectInspector.grotConfigURL(for: project.config).path(percentEncoded: false)])
        #expect(call.directory == project.config.url)
    }

    // MARK: Editing

    @Test func addUpdateAndRemove() async throws {
        let path = try workspace.makeProject("blink", grotConfig: Self.unoConfig)
        try model.addProject(path: path, title: "Blink", description: "")
        let id = try #require(model.projects.first?.id)
        // Validation runs in the background after adding
        #expect(await waitUntil { model.configValidation[id] == true })

        try model.updateProject(id: id, title: "Blinky", description: "LED")
        #expect(model.projects[0].config.title == "Blinky")
        #expect(try workspace.store.project(id: id).description == "LED")

        try model.removeProject(id: id)
        #expect(model.projects.isEmpty)
        #expect(model.configValidation[id] == nil)
        #expect(try workspace.store.load().isEmpty)
    }

    @Test func addRejectsDuplicates() async throws {
        let path = try workspace.makeProject("blink")
        try model.addProject(path: path, title: "A", description: "")
        #expect(throws: ProjectStoreError.duplicatePath) {
            try model.addProject(path: path + "/", title: "B", description: "")
        }
    }

    @Test func loadsOnlyOnceUntilRefreshed() async throws {
        try await addProject("blink")
        #expect(grot.commands() == ["validate"])
        await model.loadProjectsIfNeeded()
        #expect(grot.commands() == ["validate"])
        await model.loadProjects()
        #expect(grot.commands() == ["validate", "validate"])
    }

    @Test func newestValidationWins() async throws {
        let id = try await addProject("blink")
        // The first (slow) run sees a broken config; the second (fast) sees it fixed
        grot.enqueue(.failure("missing fqbn"), after: .milliseconds(300), for: "validate")
        grot.enqueue(CommandOutput(exitCode: 0), after: .zero, for: "validate")

        async let first: Void = model.validateConfig(id: id)
        try await Task.sleep(for: .milliseconds(50))
        await model.validateConfig(id: id)
        await first

        #expect(model.configValidation[id] == true)
        #expect(!model.outputLog.contains { $0.command == "validate" })
    }

    @Test func removingDuringValidationLeavesNoState() async throws {
        let id = try await addProject("blink")
        grot.enqueue(.failure("bad"), after: .milliseconds(200), for: "validate")
        async let validation: Void = model.validateConfig(id: id)
        try await Task.sleep(for: .milliseconds(50))
        try model.removeProject(id: id)
        await validation

        #expect(model.configValidation[id] == nil)
        #expect(model.outputLog.isEmpty)
    }

    @Test func removingDuringBuildLeavesNoOperationState() async throws {
        let id = try await addProject("blink")
        grot.enqueue(CommandOutput(exitCode: 0), after: .milliseconds(200), for: "build")
        async let build: Void = model.buildProject(id: id)
        try await Task.sleep(for: .milliseconds(50))
        try model.removeProject(id: id)
        await build

        #expect(model.operations[id] == nil)
    }

    // MARK: Operations

    @Test func operationsDefaultToIdle() {
        #expect(model.operations(for: "unknown") == ProjectOperations())
        #expect(!model.operations(for: "unknown").isBusy)
    }

    @Test func buildLogsOutputAndResetsState() async throws {
        let id = try await addProject("blink")
        grot.setResult(CommandOutput(exitCode: 2, stdout: "", stderr: "undeclared identifier"), for: "build")

        await model.buildProject(id: id)

        let entry = try #require(model.outputLog.last)
        #expect(entry.command == "build")
        #expect(entry.projectTitle == "blink")
        #expect(entry.output.exitCode == 2)
        #expect(!model.operations(for: id).building)
    }

    @Test func loadRunsGrotAndSharesBaudRate() async throws {
        let id = try await addProject("blink")
        var loadedBaud: Int?
        model.onProjectLoaded = { loadedBaud = $0 }

        await model.loadToBoard(id: id)

        #expect(grot.commands().last == "load")
        #expect(model.outputLog.last?.command == "load")
        #expect(loadedBaud == 57600)
        #expect(!model.operations(for: id).loading)
    }

    @Test func failedLoadDoesNotShareBaudRate() async throws {
        let id = try await addProject("blink")
        grot.setResult(.failure("upload failed"), for: "load")
        var loadedBaud: Int?
        model.onProjectLoaded = { loadedBaud = $0 }

        await model.loadToBoard(id: id)
        #expect(loadedBaud == nil)
    }

    @Test func loadStopsWhenPortIsUnplugged() async throws {
        let id = try await addProject("blink")
        ports.set([])

        await model.loadToBoard(id: id)

        #expect(!grot.commands().contains("load"))
        #expect(model.projects[0].portAvailable == false)
        #expect(model.portScanErrors[id] == "Port \"/dev/cu.usbmodem1\" is not connected. Plug in your Arduino and try again.")
        #expect(model.outputLog.last?.output.exitCode == 1)
    }

    @Test func loadStopsWhenNoPortConfigured() async throws {
        let id = try await addProject("blink", grotConfig: #"fqbn = "arduino:avr:uno""#)
        await model.loadToBoard(id: id)
        #expect(!grot.commands().contains("load"))
        #expect(model.portScanErrors[id]?.contains("No port configured") == true)
    }

    @Test func teensyLoadSkipsPortCheck() async throws {
        let id = try await addProject("teensy", grotConfig: #"fqbn = "teensy:avr:teensy41""#)
        ports.set([])
        await model.loadToBoard(id: id)
        #expect(grot.commands().last == "load")
    }

    @Test func updatePortWritesConfigAndLogs() async throws {
        let id = try await addProject("blink", grotConfig: "fqbn = \"arduino:avr:uno\"\nport = \"/dev/cu.old\"")
        ports.set(["/dev/cu.Bluetooth-Incoming-Port", "/dev/cu.usbmodem9"])

        await model.updatePort(id: id)

        #expect(try workspace.grotConfig(of: "blink").contains(#"port = "/dev/cu.usbmodem9""#))
        #expect(model.projects[0].grotConfig?.port == "/dev/cu.usbmodem9")
        #expect(model.projects[0].portAvailable)
        #expect(model.portScanErrors[id] == nil)
        #expect(model.outputLog.last?.output.stdout == "Port updated to /dev/cu.usbmodem9")
        #expect(!model.operations(for: id).updatingPort)
    }

    @Test func updatePortIsIgnoredWhileLoading() async throws {
        let id = try await addProject("blink", grotConfig: "fqbn = \"arduino:avr:uno\"\nport = \"/dev/cu.usbmodem1\"")
        ports.set(["/dev/cu.usbmodem1", "/dev/cu.usbmodem9"])
        grot.enqueue(CommandOutput(exitCode: 0), after: .milliseconds(200), for: "load")
        async let load: Void = model.loadToBoard(id: id)
        try await Task.sleep(for: .milliseconds(50))

        await model.updatePort(id: id)
        await load

        #expect(try workspace.grotConfig(of: "blink").contains("/dev/cu.usbmodem1\""))
        #expect(!model.outputLog.contains { $0.command == "update-port" })
    }

    @Test func updatePortRefusesSymlinkedConfig() async throws {
        let id = try await addProject("blink")
        let config = workspace.root.appending(path: "blink/.grotconfig")
        let elsewhere = workspace.root.appending(path: "elsewhere.toml")
        try FileManager.default.moveItem(at: config, to: elsewhere)
        try FileManager.default.createSymbolicLink(at: config, withDestinationURL: elsewhere)

        await model.updatePort(id: id)

        #expect(model.portScanErrors[id]?.contains("symbolic link") == true)
        #expect(try String(contentsOf: elsewhere, encoding: .utf8) == Self.unoConfig)
    }

    @Test func updatePortWithoutArduinoReportsError() async throws {
        let id = try await addProject("blink")
        ports.set(["/dev/cu.Bluetooth-Incoming-Port"])

        await model.updatePort(id: id)

        #expect(model.portScanErrors[id] == "No Arduino-like port found. Connect your device and try again.")
        #expect(model.projects[0].portAvailable == false)
        #expect(model.outputLog.last?.command == "update-port")
        #expect(try workspace.grotConfig(of: "blink") == Self.unoConfig)
    }

    // MARK: File changes

    @Test func fileChangeReinspectsAndRevalidates() async throws {
        let id = try await addProject("blink", grotConfig: nil)
        try workspace.makeProject("blink", grotConfig: Self.unoConfig)

        await model.projectFilesChanged(id: id)

        #expect(model.projects[0].hasGrotConfig)
        #expect(model.configValidation[id] == true)
    }

    @Test func removedConfigClearsValidation() async throws {
        let id = try await addProject("blink")
        try FileManager.default.removeItem(at: workspace.root.appending(path: "blink/.grotconfig"))

        await model.projectFilesChanged(id: id)

        #expect(!model.projects[0].hasGrotConfig)
        #expect(model.configValidation[id] == nil)
    }

    @Test func portErrorClearsWhenPortReturns() async throws {
        let id = try await addProject("blink")
        ports.set([])
        await model.loadToBoard(id: id)
        #expect(model.portScanErrors[id] != nil)

        ports.set(["/dev/cu.usbmodem1"])
        await model.projectFilesChanged(id: id)

        #expect(model.projects[0].portAvailable)
        #expect(model.portScanErrors[id] == nil)
    }

    @Test func fileChangeForUnknownProjectIsIgnored() async {
        await model.projectFilesChanged(id: "nope")
        #expect(model.projects.isEmpty)
    }

    // MARK: Output log

    @Test func outputLogIDsIncrementAndClear() {
        model.appendOutput(projectTitle: "A", command: "build", output: CommandOutput(exitCode: 0))
        model.appendOutput(projectTitle: "B", command: "load", output: CommandOutput(exitCode: 0))
        #expect(model.outputLog.map(\.id) == [1, 2])
        #expect(model.outputLog.map(\.projectTitle) == ["A", "B"])

        model.clearOutput()
        #expect(model.outputLog.isEmpty)
    }

    @Test func outputLogKeepsRecentEntries() {
        for i in 0..<(OutputLog.maxEntries + 5) {
            model.appendOutput(projectTitle: "P\(i)", command: "build", output: CommandOutput(exitCode: 0))
        }
        #expect(model.outputLog.count == OutputLog.maxEntries)
        #expect(model.outputLog.first?.projectTitle == "P5")
    }

    @Test func longOutputKeepsItsEnd() {
        let long = String(repeating: "x", count: OutputLog.maxCharactersPerStream) + "the error"
        model.appendOutput(projectTitle: "P", command: "build", output: .failure(long))
        let stderr = model.outputLog[0].output.stderr
        #expect(stderr.hasSuffix("the error"))
        #expect(stderr.count < long.count + 40)
    }
}
