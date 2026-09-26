import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case projects
    case serial

    var id: Self { self }

    var title: String {
        switch self {
        case .projects: "Projects"
        case .serial: "Serial Monitor"
        }
    }

    var systemImage: String {
        switch self {
        case .projects: "square.grid.2x2"
        case .serial: "cable.connector"
        }
    }
}

/// Sidebar navigation with the page in the detail column. The sidebar toggle and
/// ⌃⌘S come from NavigationSplitView and SidebarCommands.
struct RootView: View {
    @SceneStorage("selectedPage") private var selection: SidebarItem = .projects

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: sidebarSelection) { item in
                Label(item.title, systemImage: item.systemImage)
            }
            .navigationSplitViewColumnWidth(min: Layout.sidebarMinWidth, ideal: Layout.sidebarIdealWidth)
        } detail: {
            switch selection {
            case .projects: ProjectsView()
            case .serial: SerialView()
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ConnectionIndicator()
            }
            .sharedBackgroundVisibility(.hidden)
        }
    }

    /// List selection is optional; ignore deselection so a page is always shown.
    private var sidebarSelection: Binding<SidebarItem?> {
        Binding(
            get: { selection },
            set: { if let item = $0 { selection = item } }
        )
    }
}

/// Green when a serial port is connected.
struct ConnectionIndicator: View {
    @Environment(SerialModel.self) private var serial

    var body: some View {
        let text = serial.connectedPort.map { "Serial connected to \($0)" } ?? "Serial not connected"
        Image(systemName: "circle.fill")
            .font(.system(size: 10))
            .foregroundStyle(serial.isConnected ? AnyShapeStyle(.green) : AnyShapeStyle(.tertiary))
            .help(text)
            .accessibilityLabel(text)
    }
}
