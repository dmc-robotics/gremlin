import AppKit
import ServitorKit
import SwiftUI
import UniformTypeIdentifiers

/// The Settings window (⌘,).
struct SettingsView: View {
    @AppStorage(Preferences.terminalAppKey) private var terminalApp = Preferences.defaultTerminalApp
    @AppStorage(Preferences.editorAppKey) private var editorApp = Preferences.defaultEditorApp
    @State private var grotVersion = "…"

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    var body: some View {
        Form {
            Section("General") {
                AppPicker(
                    title: "Terminal App",
                    subtitle: "Opens when you click a project path",
                    appPath: $terminalApp
                )
                AppPicker(
                    title: "Editor App",
                    subtitle: "Opens .grotconfig and sketch files",
                    appPath: $editorApp
                )
            }
            Section("About") {
                LabeledContent("MacServitor", value: appVersion)
                LabeledContent("grot", value: grotVersion)
            }
        }
        .formStyle(.grouped)
        .frame(width: Layout.settingsWidth)
        .fixedSize()
        .task {
            grotVersion = await GrotRunner().version() ?? "not found"
        }
    }
}

/// Shows the chosen app with its icon, and a button to choose another.
private struct AppPicker: View {
    let title: String
    let subtitle: String
    @Binding var appPath: String

    var body: some View {
        LabeledContent {
            HStack(spacing: 6) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: appPath))
                    .resizable()
                    .frame(width: 16, height: 16)
                Text(AppLauncher.displayName(ofAppAt: appPath))
                Button("Choose…", action: choose)
            }
        } label: {
            Text(title)
            Text(subtitle)
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.title = "Choose \(title)"
        panel.prompt = "Choose"
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(filePath: "/Applications")
        if panel.runModal() == .OK, let url = panel.url {
            appPath = url.path(percentEncoded: false)
        }
    }
}
