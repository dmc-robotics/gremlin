import GremlinKit
import SwiftUI

/// Log of grot command results. New entries scroll into view; the arrows step between entries.
struct OutputPanel: View {
    @Environment(ProjectsModel.self) private var model
    @State private var scrolledEntryID: Int?

    private var entries: [OutputEntry] { model.outputLog }

    private var currentIndex: Int? {
        entries.firstIndex { $0.id == scrolledEntryID }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(entries) { entry in
                        OutputEntryView(entry: entry)
                            .padding(.vertical, 10)
                            .overlay(alignment: .top) {
                                if entry.id != entries.first?.id { Divider() }
                            }
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal)
            }
            .scrollPosition(id: $scrolledEntryID, anchor: .top)
            .overlay {
                if entries.isEmpty {
                    Text("No output yet. Run a build or load command.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .onChange(of: entries.last?.id) { _, newID in
            withAnimation { scrolledEntryID = newID }
        }
    }

    private var header: some View {
        HStack {
            Label("Output", systemImage: "terminal")
                .font(.subheadline.weight(.semibold))
            if !entries.isEmpty {
                Text("\(entries.count)")
                    .font(.caption.monospacedDigit())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(.quaternary, in: .capsule)
            }
            Spacer()
            if !entries.isEmpty {
                Group {
                    Button("Previous Entry", systemImage: "chevron.up") { step(by: -1) }
                        .disabled((currentIndex ?? 0) <= 0)
                    Button("Next Entry", systemImage: "chevron.down") { step(by: 1) }
                        .disabled((currentIndex ?? entries.count - 1) >= entries.count - 1)
                    Button("Clear Output", systemImage: "trash") { model.clearOutput() }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private func step(by offset: Int) {
        let index = (currentIndex ?? entries.count - 1) + offset
        guard entries.indices.contains(index) else { return }
        withAnimation { scrolledEntryID = entries[index].id }
    }
}

private struct OutputEntryView: View {
    let entry: OutputEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(entry.command.uppercased())
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(tint.opacity(0.15), in: .capsule)
                    .foregroundStyle(tint)
                Text(entry.projectTitle)
                    .fontWeight(.medium)
                Text(entry.timestamp.timeWithMilliseconds)
                    .foregroundStyle(.secondary)
                Text("exit \(entry.output.exitCode)")
                    .foregroundStyle(entry.output.succeeded ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
            }
            .font(.caption)

            if !entry.output.stdout.isEmpty {
                OutputText(text: entry.stdoutText, baseColor: .primary)
                    .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 6))
            }
            if !entry.output.stderr.isEmpty {
                OutputText(text: entry.stderrText, baseColor: .red)
                    .background(.red.opacity(0.08), in: .rect(cornerRadius: 6))
            }
        }
    }

    private var tint: Color {
        entry.output.succeeded ? .secondary : .red
    }
}

/// Monospaced command output with grot's ANSI colors.
private struct OutputText: View {
    let text: AttributedString
    let baseColor: Color

    var body: some View {
        Text(text)
            .font(.caption.monospaced())
            .foregroundStyle(baseColor)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
    }
}
