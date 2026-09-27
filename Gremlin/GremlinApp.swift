import SwiftUI

@main
struct GremlinApp: App {
    @State private var serial: SerialModel
    @State private var projects: ProjectsModel

    init() {
        let serial = SerialModel()
        let projects = ProjectsModel()
        projects.onProjectLoaded = { [weak serial] baudRate in
            serial?.setPreferredBaudRate(baudRate)
        }
        _serial = State(initialValue: serial)
        _projects = State(initialValue: projects)
    }

    var body: some Scene {
        // Single window: the serial connection and project state are app-wide
        Window("Gremlin", id: "main") {
            RootView()
                .environment(serial)
                .environment(projects)
                .frame(minWidth: Layout.windowMinWidth, minHeight: Layout.windowMinHeight)
        }
        .defaultSize(width: Layout.defaultWindowWidth, height: Layout.defaultWindowHeight)
        .commands {
            SidebarCommands()
        }

        Settings {
            SettingsView()
        }
    }
}
