import ServitorKit
import SwiftUI

/// A project's identity, board settings, file/port status, and grot actions.
struct ProjectCard: View {
    let project: ProjectData
    let onEdit: () -> Void

    @Environment(ProjectsModel.self) private var model
    @AppStorage(Preferences.terminalAppKey) private var terminalApp = Preferences.defaultTerminalApp
    @AppStorage(Preferences.editorAppKey) private var editorApp = Preferences.defaultEditorApp

    private var operations: ProjectOperations { model.operations(for: project.id) }

    private var canRunGrot: Bool {
        !operations.isBusy && project.hasGrotConfig && project.directoryAccessible
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding()
            Divider()
            details
                .padding()
                .frame(maxHeight: .infinity, alignment: .top)
            Divider()
            actions
                .padding()
        }
        .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: Layout.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Layout.cornerRadius)
                .strokeBorder(.separator)
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(project.config.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Button("Edit Project", systemImage: "pencil", action: onEdit)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .disabled(operations.isBusy)
                    .help("Edit project")
            }
            Button {
                AppLauncher.open(project.config.url, withAppAt: terminalApp)
            } label: {
                Text(project.config.path)
                    .font(.caption.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .buttonStyle(.link)
            .foregroundStyle(.secondary)
            .help("Open in \(AppLauncher.displayName(ofAppAt: terminalApp)): \(project.config.path)")

            if !project.config.description.isEmpty {
                Text(project.config.description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.top, 2)
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let config = project.grotConfig {
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
                    GridRow {
                        DetailItem(label: "Board", value: config.fqbn)
                        if let core = coreDisplay(config) {
                            DetailItem(label: "Core", value: core)
                        }
                    }
                    GridRow {
                        DetailItem(label: "Port", value: config.isTeensy ? "--" : (config.port.isEmpty ? "not set" : config.port))
                        DetailItem(label: "Baud", value: String(config.baudRate))
                    }
                }
            } else {
                Text("No configuration available")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if project.directoryAccessible {
                HStack(spacing: 8) {
                    configBadge
                    sketchBadge
                    portBadge
                }
            } else {
                Label("Project files not found", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.red)
            }
        }
    }

    private var actions: some View {
        HStack {
            Button {
                Task { await model.buildProject(id: project.id) }
            } label: {
                ActionLabel(title: "Build", systemImage: "hammer", isRunning: operations.building)
            }
            .help("Build with grot")

            Button {
                Task { await model.loadToBoard(id: project.id) }
            } label: {
                ActionLabel(title: "Load", systemImage: "square.and.arrow.up", isRunning: operations.loading)
            }
            .help("Load onto board with grot")
        }
        .controlSize(.large)
        .disabled(!canRunGrot)
    }

    // MARK: - Status badges

    private var configBadge: some View {
        let state: StatusBadge.State = if !project.hasGrotConfig {
            .fail
        } else if let valid = model.configValidation[project.id] {
            valid ? .ok : .fail
        } else {
            .pending
        }
        let help = if !project.hasGrotConfig {
            "No .grotconfig file found in \"\(project.config.directoryName)\"."
        } else if state == .fail {
            "Config failed validation. See the output panel for details."
        } else {
            "Open .grotconfig"
        }
        return StatusBadge(title: "Config", state: state, help: help) {
            AppLauncher.open(ProjectInspector.grotConfigURL(for: project.config), withAppAt: editorApp)
        }
    }

    private var sketchBadge: some View {
        StatusBadge(
            title: "Sketch",
            state: project.hasInoFile ? .ok : .fail,
            help: project.hasInoFile
                ? "Open \(project.config.sketchFileName)"
                : "Expected \"\(project.config.sketchFileName)\" not found in project directory."
        ) {
            AppLauncher.open(ProjectInspector.sketchURL(for: project.config), withAppAt: editorApp)
        }
    }

    @ViewBuilder
    private var portBadge: some View {
        if project.grotConfig?.isTeensy == true {
            StatusBadge(title: "Port", state: .pending, help: "Teensy boards don't use a serial port", action: {})
                .disabled(true)
        } else {
            let port = project.grotConfig?.port ?? ""
            let state: StatusBadge.State = !port.isEmpty && project.portAvailable ? .ok : .fail
            let help = if let error = model.portScanErrors[project.id] {
                error
            } else if port.isEmpty {
                "No port configured. Click to scan for your Arduino."
            } else if state == .fail {
                "Port \"\(port)\" is not currently connected. Click to scan again."
            } else {
                "Click to scan for your Arduino's port"
            }
            StatusBadge(title: "Port", state: state, help: help, isRunning: operations.updatingPort) {
                Task { await model.updatePort(id: project.id) }
            }
            .disabled(operations.updatingPort)
        }
    }

    private func coreDisplay(_ config: GrotConfig) -> String? {
        guard !config.targetCore.isEmpty else { return nil }
        guard let split = config.flashSplit else { return config.targetCore }
        return "\(config.targetCore) \(Int((split * 100).rounded()))%"
    }
}

private struct DetailItem: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(value)
        }
        .font(.caption)
    }
}

/// Full-width button label that swaps its icon for a spinner while running.
private struct ActionLabel: View {
    let title: String
    let systemImage: String
    let isRunning: Bool

    var body: some View {
        HStack(spacing: 6) {
            if isRunning {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: systemImage)
            }
            Text(title)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Clickable capsule showing whether a project file or port is OK.
struct StatusBadge: View {
    enum State {
        case ok, fail, pending
    }

    let title: String
    let state: State
    let help: String
    var isRunning = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if isRunning {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Image(systemName: symbol)
                }
                Text(title)
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(tint)
            .background(tint.opacity(0.15), in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var symbol: String {
        state == .fail ? "xmark.circle.fill" : "checkmark.circle.fill"
    }

    private var tint: Color {
        switch state {
        case .ok: .green
        case .fail: .red
        case .pending: .secondary
        }
    }
}
