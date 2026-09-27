import GremlinKit
import SwiftUI

/// Add a project, or edit/remove an existing one.
struct ProjectFormSheet: View {
    enum Mode {
        case add
        case edit(ProjectData)
    }

    let mode: Mode

    @Environment(ProjectsModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var path = ""
    @State private var title = ""
    @State private var description = ""
    @State private var error: String?
    @State private var isChoosingDirectory = false
    @State private var isConfirmingRemove = false
    @State private var isSubmitting = false

    init(mode: Mode) {
        self.mode = mode
        if case let .edit(project) = mode {
            _title = State(initialValue: project.config.title)
            _description = State(initialValue: project.config.description)
        }
    }

    private var isAdding: Bool {
        if case .add = mode { true } else { false }
    }

    private var canSubmit: Bool {
        let hasTitle = !title.trimmingCharacters(in: .whitespaces).isEmpty
        let hasPath = !path.trimmingCharacters(in: .whitespaces).isEmpty
        return hasTitle && (hasPath || !isAdding) && !isSubmitting
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(isAdding ? "Add Arduino Project" : "Edit Project")
                .font(.headline)
                .padding(.top)
            Form {
                Section {
                    if isAdding {
                        LabeledContent("Directory") {
                            HStack {
                                TextField("Directory", text: $path, prompt: Text("/path/to/project"))
                                    .labelsHidden()
                                    .font(.body.monospaced())
                                Button("Choose…") { isChoosingDirectory = true }
                            }
                        }
                    }
                    TextField("Name", text: $title, prompt: Text("Required"))
                    TextField("Description", text: $description, prompt: Text("Optional"), axis: .vertical)
                        .lineLimit(3...6)
                } footer: {
                    if let error {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                if case .edit = mode {
                    Button("Remove Project…", role: .destructive) { isConfirmingRemove = true }
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isAdding ? "Add Project" : "Save") { submit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSubmit)
            }
            .padding([.horizontal, .bottom])
        }
        .frame(width: Layout.formSheetWidth)
        .fileImporter(isPresented: $isChoosingDirectory, allowedContentTypes: [.folder]) { result in
            guard case let .success(url) = result else { return }
            path = url.path(percentEncoded: false)
            if title.isEmpty {
                title = url.lastPathComponent
            }
        }
        .confirmationDialog("Remove “\(title)”?", isPresented: $isConfirmingRemove) {
            Button("Remove", role: .destructive) { remove() }
        } message: {
            Text("The project is removed from Gremlin. Files on disk are not deleted.")
        }
    }

    private func submit() {
        isSubmitting = true
        error = nil
        Task {
            defer { isSubmitting = false }
            do {
                switch mode {
                case .add:
                    try model.addProject(path: path, title: title, description: description)
                case let .edit(project):
                    try model.updateProject(id: project.id, title: title, description: description)
                }
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func remove() {
        guard case let .edit(project) = mode else { return }
        do {
            try model.removeProject(id: project.id)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
