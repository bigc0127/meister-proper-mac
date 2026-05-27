import SwiftUI

struct LaunchAgentsView: View {
    @State private var agents: [LaunchAgent] = []
    @State private var loading = true
    @State private var search = ""
    @State private var scopeFilter: String = "All"
    @State private var showConfirm = false
    @State private var log = ""
    @State private var working = false

    var scopes: [String] { ["All"] + LaunchAgent.Scope.allCases.map { $0.rawValue } }

    var filtered: [LaunchAgent] {
        agents.filter { a in
            let matchScope = scopeFilter == "All" || a.scope.rawValue == scopeFilter
            let q = search.trimmingCharacters(in: .whitespaces)
            let matchSearch = q.isEmpty
                || a.label.localizedCaseInsensitiveContains(q)
                || a.program.localizedCaseInsensitiveContains(q)
                || a.path.localizedCaseInsensitiveContains(q)
            return matchScope && matchSearch
        }
    }

    var selected: [LaunchAgent] { agents.filter { $0.selected } }

    var body: some View {
        VStack(spacing: 12) {
            toolbar
            if loading {
                ProgressView("Reading LaunchAgents/Daemons…").frame(maxHeight: .infinity)
            } else {
                content
            }
        }
        .padding(16)
        .navigationTitle("LaunchAgents")
        .task { await reload() }
        .alert("Disable & remove \(selected.count) item(s)?", isPresented: $showConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) { applyRemoval() }
        } message: {
            let needsAdmin = selected.contains(where: { $0.scope.requiresAdmin })
            let suffix = needsAdmin ? " System items require admin authentication." : ""
            Text("This will unload (launchctl bootout) and delete the selected plists.\(suffix)\n\n" +
                 selected.map { "• \($0.label) (\($0.scope.rawValue))" }.joined(separator: "\n"))
        }
    }

    private var toolbar: some View {
        HStack {
            TextField("Search label / program / path…", text: $search)
                .textFieldStyle(.roundedBorder).frame(maxWidth: 320)
            Picker("", selection: $scopeFilter) {
                ForEach(scopes, id: \.self) { Text($0).tag($0) }
            }.frame(width: 200)
            Spacer()
            Text("\(selected.count) selected").foregroundStyle(.secondary)
            Button(role: .destructive) { showConfirm = true } label: {
                Label("Disable & Delete", systemImage: "trash")
            }
            .buttonStyle(.borderedProminent).tint(.red)
            .disabled(selected.isEmpty || working)
            Button { Task { await reload() } } label: { Image(systemName: "arrow.clockwise") }
                .help("Re-scan")
                .disabled(working)
        }
    }

    private var content: some View {
        HSplitView {
            List {
                ForEach(LaunchAgent.Scope.allCases, id: \.self) { (scope: LaunchAgent.Scope) in
                    let group = filtered.filter { $0.scope == scope }
                    if !group.isEmpty {
                        Section {
                            ForEach(group) { a in row(for: a) }
                        } header: {
                            Text(scope.rawValue + (scope.requiresAdmin ? "  (admin)" : ""))
                        }
                    }
                }
            }
            .frame(minWidth: 520)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Operation log").font(.headline)
                    Spacer()
                    if working { ProgressView().controlSize(.small) }
                    if !log.isEmpty {
                        Button("Clear") { log = "" }.buttonStyle(.bordered)
                    }
                }
                LogPane(placeholder: "No operations yet.", log: log)
            }
            .padding(.leading, 8)
            .frame(minWidth: 320)
        }
    }

    private func row(for a: LaunchAgent) -> some View {
        HStack {
            Toggle("", isOn: bindingFor(a)).labelsHidden()
            VStack(alignment: .leading) {
                Text(a.label).fontWeight(.medium)
                Text(a.program.isEmpty ? "(no program)" : a.program)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text((a.path as NSString).lastPathComponent)
                    .font(.system(.caption2, design: .monospaced)).foregroundStyle(.tertiary)
            }
            Spacer()
            if a.scope.requiresAdmin {
                Image(systemName: "lock.fill").foregroundStyle(.orange).help("Requires admin to remove")
            }
        }
        .contentShape(.rect)
        .onTapGesture {
            if let i = agents.firstIndex(where: { $0.id == a.id }) { agents[i].selected.toggle() }
        }
    }

    private func bindingFor(_ a: LaunchAgent) -> Binding<Bool> {
        Binding(
            get: { agents.first(where: { $0.id == a.id })?.selected ?? false },
            set: { v in if let i = agents.firstIndex(where: { $0.id == a.id }) { agents[i].selected = v } }
        )
    }

    @MainActor
    private func reload() async {
        loading = true
        let prev = Set(agents.filter { $0.selected }.map { $0.path })
        var fresh = await Task.detached { LaunchAgentsService.loadAll() }.value
        for i in fresh.indices { if prev.contains(fresh[i].path) { fresh[i].selected = true } }
        agents = fresh
        loading = false
    }

    private func applyRemoval() {
        let chosen = selected
        working = true
        Task.detached {
            let result = LaunchAgentsService.remove(chosen)
            await MainActor.run {
                log = result + (log.isEmpty ? "" : "\n---\n" + log)
                working = false
            }
            await reload()
        }
    }
}
