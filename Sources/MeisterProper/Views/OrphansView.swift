import SwiftUI

struct OrphansView: View {
    @State private var items: [OrphanLeftover] = []
    @State private var scanning = false
    @State private var working = false
    @State private var includeApple = false
    @State private var locationFilter = "All"
    @State private var search = ""
    @State private var log = ""
    @State private var showConfirm = false

    var locations: [String] { ["All"] + Array(Set(items.map { $0.location })).sorted() }

    var filtered: [OrphanLeftover] {
        items.filter { it in
            let ml = locationFilter == "All" || it.location == locationFilter
            let q = search.trimmingCharacters(in: .whitespaces)
            let ms = q.isEmpty
                || it.bundleId.localizedCaseInsensitiveContains(q)
                || it.path.localizedCaseInsensitiveContains(q)
            return ml && ms
        }
    }
    var selected: [OrphanLeftover] { filtered.filter { $0.selected } }
    var totalBytes: Int64 { selected.map { $0.size }.reduce(0, +) }
    var grandTotal: Int64 { items.map { $0.size }.reduce(0, +) }

    var body: some View {
        VStack(spacing: 12) {
            toolbar
            content
        }
        .padding(16)
        .navigationTitle("App Leftovers")
        .alert("Move \(selected.count) leftover(s) to Trash?", isPresented: $showConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Move to Trash", role: .destructive) { apply() }
        } message: {
            Text("Reclaims \(byteString(totalBytes)). Items go to Trash, recoverable until you empty it.")
        }
        .task { if items.isEmpty { await scan() } }
    }

    private var toolbar: some View {
        HStack {
            Button { Task { await scan() } } label: {
                Label(scanning ? "Scanning…" : "Re-scan", systemImage: "arrow.clockwise")
            }.disabled(scanning || working)

            Toggle("Include Apple/system", isOn: $includeApple)
                .toggleStyle(.checkbox).help("Show com.apple.* and known system-framework leftovers (rarely safe to delete).")
                .onChange(of: includeApple) { _, _ in Task { await scan() } }

            Picker("", selection: $locationFilter) {
                ForEach(locations, id: \.self) { Text($0).tag($0) }
            }.frame(width: 220)

            TextField("Search bundle id…", text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 220)

            Spacer()
            Text("\(items.count) found · \(byteString(grandTotal)) total · \(selected.count) sel · \(byteString(totalBytes))").foregroundStyle(.secondary)

            Button {
                let allOn = filtered.allSatisfy { $0.selected }
                let ids = Set(filtered.map { $0.id })
                for i in items.indices where ids.contains(items[i].id) { items[i].selected = !allOn }
            } label: { Label("Toggle All", systemImage: "checkmark.square") }.disabled(filtered.isEmpty)

            Button(role: .destructive) { showConfirm = true } label: {
                Label("Move to Trash", systemImage: "trash")
            }
            .buttonStyle(.borderedProminent).tint(.red)
            .disabled(selected.isEmpty || working)
        }
    }

    private var content: some View {
        HSplitView {
            List {
                if filtered.isEmpty && !scanning {
                    Text("Click Re-scan to find leftover files for apps that are no longer installed. Scans Application Support, Caches, Containers, HTTP Storages, WebKit, Saved Application State, Logs, Preferences, ByHost, Application Scripts, and LaunchAgents.")
                        .foregroundStyle(.secondary).padding()
                } else {
                    ForEach(filtered) { item in
                        HStack {
                            Toggle("", isOn: bindingFor(item)).labelsHidden()
                            VStack(alignment: .leading) {
                                Text(item.bundleId).fontWeight(.medium)
                                HStack(spacing: 6) {
                                    Text(item.location).font(.caption)
                                        .padding(.horizontal, 5).padding(.vertical, 2)
                                        .background(.background.tertiary, in: .capsule)
                                    Text((item.path as NSString).abbreviatingWithTildeInPath)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                }
                            }
                            Spacer()
                            Text(byteString(item.size))
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(item.size > 1_073_741_824 ? .red : (item.size > 104_857_600 ? .orange : .secondary))
                                .frame(width: 90, alignment: .trailing)
                        }
                        .padding(.vertical, 2)
                        .contentShape(.rect)
                        .onTapGesture {
                            if let i = items.firstIndex(where: { $0.id == item.id }) { items[i].selected.toggle() }
                        }
                    }
                }
            }
            .frame(minWidth: 600)

            VStack(alignment: .leading, spacing: 8) {
                Text("Log").font(.headline)
                LogPane(placeholder: "No operations yet.", log: log)
            }
            .padding(.leading, 8)
            .frame(minWidth: 280)
        }
    }

    private func bindingFor(_ item: OrphanLeftover) -> Binding<Bool> {
        Binding(
            get: { items.first(where: { $0.id == item.id })?.selected ?? false },
            set: { v in if let i = items.firstIndex(where: { $0.id == item.id }) { items[i].selected = v } }
        )
    }

    private func byteString(_ b: Int64) -> String {
        let f = ByteCountFormatter(); f.countStyle = .file
        return f.string(fromByteCount: b)
    }

    @MainActor
    private func scan() async {
        scanning = true
        log = "Cross-referencing installed apps with Library entries…\n"
        let result = await OrphanFinder.scan(includeApple: includeApple)
        items = result
        scanning = false
        log += "Found \(result.count) orphan leftover(s) · \(byteString(grandTotal)) reclaimable\n"
    }

    private func apply() {
        let chosen = selected
        working = true
        log += "\nMoving \(chosen.count) leftover(s) to Trash…\n"
        Task {
            let result = await OrphanFinder.remove(chosen)
            await MainActor.run {
                log += result
                working = false
                items.removeAll { it in chosen.contains(where: { $0.id == it.id }) }
            }
        }
    }
}
