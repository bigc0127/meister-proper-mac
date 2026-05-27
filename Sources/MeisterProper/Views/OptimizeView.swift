import SwiftUI

struct OptimizeView: View {
    @State private var tasks: [OptimizeTask] = OptimizeService.tasks()
    @State private var working = false
    @State private var log = ""
    @State private var showConfirm = false

    var selected: [OptimizeTask] { tasks.filter { $0.selected } }

    var body: some View {
        VStack(spacing: 12) {
            toolbar
            content
        }
        .padding(16)
        .navigationTitle("Optimize")
        .alert("Run \(selected.count) optimization task(s)?", isPresented: $showConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Run", role: .destructive) { run() }
        } message: {
            let needsAdmin = selected.contains(where: { $0.requiresAdmin })
            Text(needsAdmin ? "Some tasks need admin — single password prompt will appear."
                            : "These tasks make non-destructive system maintenance changes.")
        }
    }

    private var toolbar: some View {
        HStack {
            Button { for i in tasks.indices { tasks[i].selected = !tasks[i].requiresAdmin } } label: {
                Label("Select Safe", systemImage: "checkmark.square")
            }.disabled(working)
            Button { for i in tasks.indices { tasks[i].selected = true } } label: {
                Label("Select All", systemImage: "checkmark.square.fill")
            }.disabled(working)
            Button { for i in tasks.indices { tasks[i].selected = false } } label: {
                Label("Clear", systemImage: "square")
            }.disabled(working)
            Spacer()
            Text("\(selected.count) selected").foregroundStyle(.secondary)
            if working { ProgressView().controlSize(.small) }
            Button(role: .destructive) { showConfirm = true } label: {
                Label("Run", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent).tint(.red).disabled(selected.isEmpty || working)
        }
    }

    private var content: some View {
        HSplitView {
            List {
                ForEach(groupedCategories(), id: \.self) { cat in
                    Section {
                        ForEach(tasks.filter { $0.category == cat }) { t in row(t) }
                    } header: { Text(cat) }
                }
            }
            .frame(minWidth: 540)

            VStack(alignment: .leading, spacing: 8) {
                Text("Log").font(.headline)
                LogPane(placeholder: "Select tasks and click Run.", log: log)
            }
            .padding(.leading, 8)
            .frame(minWidth: 320)
        }
    }

    private func row(_ t: OptimizeTask) -> some View {
        HStack(alignment: .top) {
            Toggle("", isOn: bindingFor(t)).labelsHidden().padding(.top, 4)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(t.label).fontWeight(.medium)
                    if t.requiresAdmin { Image(systemName: "lock.fill").foregroundStyle(.orange) }
                }
                Text(t.detail).font(.caption).foregroundStyle(.secondary)
                Text(t.command).font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.blue.opacity(0.7))
                    .lineLimit(1).truncationMode(.tail)
            }
        }
        .padding(.vertical, 2)
        .contentShape(.rect)
        .onTapGesture {
            if let i = tasks.firstIndex(where: { $0.id == t.id }) { tasks[i].selected.toggle() }
        }
    }

    private func bindingFor(_ t: OptimizeTask) -> Binding<Bool> {
        Binding(
            get: { tasks.first(where: { $0.id == t.id })?.selected ?? false },
            set: { v in if let i = tasks.firstIndex(where: { $0.id == t.id }) { tasks[i].selected = v } }
        )
    }

    private func groupedCategories() -> [String] {
        var seen: Set<String> = []
        return tasks.compactMap { t in
            if seen.contains(t.category) { return nil }
            seen.insert(t.category)
            return t.category
        }
    }

    private func run() {
        let chosen = selected
        log = ""
        working = true
        Task {
            await OptimizeService.run(chosen) { line in
                await MainActor.run { log += line + "\n" }
            }
            await MainActor.run { working = false }
        }
    }
}
