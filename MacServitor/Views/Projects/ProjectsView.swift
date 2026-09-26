import ServitorKit
import SwiftUI

/// Project cards above a resizable output panel.
struct ProjectsView: View {
    @Environment(ProjectsModel.self) private var model
    @State private var isAdding = false
    @State private var editing: ProjectData?
    @SceneStorage("outputPanelHeight") private var outputHeight = Double(Layout.outputIdealHeight)

    var body: some View {
        BottomPanelSplit(
            panelHeight: $outputHeight,
            minContentHeight: Layout.projectsMinHeight,
            minPanelHeight: Layout.outputMinHeight
        ) {
            projectsArea
        } panel: {
            OutputPanel()
        }
        .navigationTitle("Projects")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Project", systemImage: "plus") { isAdding = true }
                    .help("Add an Arduino project directory")
            }
        }
        .sheet(isPresented: $isAdding) {
            ProjectFormSheet(mode: .add)
        }
        .sheet(item: $editing) { project in
            ProjectFormSheet(mode: .edit(project))
        }
        .task {
            await model.loadProjects()
        }
    }

    @ViewBuilder
    private var projectsArea: some View {
        if model.isLoading && model.projects.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = model.loadError {
            ContentUnavailableView("Can't Load Projects", systemImage: "exclamationmark.triangle", description: Text(error))
        } else if model.projects.isEmpty {
            ContentUnavailableView {
                Label("No Projects", systemImage: "folder")
            } description: {
                Text("Add an Arduino project directory to build and load it with grot.")
            } actions: {
                Button("Add Project") { isAdding = true }
            }
        } else {
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: Layout.cardMinWidth), spacing: Layout.cardSpacing)],
                    spacing: Layout.cardSpacing
                ) {
                    ForEach(model.projects) { project in
                        ProjectCard(project: project) { editing = project }
                    }
                }
                .padding()
            }
        }
    }
}
