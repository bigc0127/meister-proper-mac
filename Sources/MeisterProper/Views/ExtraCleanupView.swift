import SwiftUI

struct ExtraCleanupView: View {
    @State private var items: [CleanupItem] = ExtraCleanupService.defaultItems()
    @State private var scanning = false
    @State private var working = false
    @State private var log = ""
    @State private var showConfirm = false

    var totalSelectedBytes: Int64 {
        items.filter { $0.selected }.compactMap { $0.size }.reduce(0, +)
    }

    var selectedCount: Int { items.filter { $0.selected }.count }

    var body: some View {
        VStack(spacing: 12) {
            toolbar
            content
        }
        .padding(16)
        .navigationTitle("Extra Cleanup")
        .alert("Apply \(selectedCount) cleanup task(s)?", isPresented: $showConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Apply", role: .destructive) { runApply() }
        } message: {
            let needsAdmin = items.contains(where: { $0.selected && $0.requiresAdmin })
            let dangerCount = items.filter { $0.selected && $0.dangerous }.count
            var msg = "Selected items will be deleted permanently (not Trash)."
            if dangerCount > 0 { msg += "\n\n⚠ \(dangerCount) item(s) flagged dangerous — review before applying." }
            if needsAdmin { msg += "\n\nAdmin password will be requested for system items." }
            return Text(msg)
        }
    }

    private var toolbar: some View {
        HStack {
            Button { Task { await scanSizes() } } label: {
                Label(scanning ? "Scanning…" : "Calculate Sizes", systemImage: "ruler")
            }
            .disabled(scanning || working)

            Button {
                let allOn = items.allSatisfy { $0.selected }
                for i in items.indices { items[i].selected = !allOn && !items[i].dangerous && !items[i].requiresAdmin }
            } label: { Label("Select Safe", systemImage: "checkmark.square") }
                .disabled(working)

            Button { for i in items.indices { items[i].selected = false } } label: {
                Label("Clear", systemImage: "square")
            }.disabled(working)

            Spacer()
            Text("\(selectedCount) selected · \(byteString(totalSelectedBytes))").foregroundStyle(.secondary)
            Button(role: .destructive) { showConfirm = true } label: {
                Label("Clean Selected", systemImage: "trash")
            }
            .buttonStyle(.borderedProminent).tint(.red)
            .disabled(selectedCount == 0 || working)
        }
    }

    private var content: some View {
        HSplitView {
            List {
                ForEach(items) { item in
                    HStack(alignment: .top) {
                        Toggle("", isOn: bindingFor(item)).labelsHidden().padding(.top, 4)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(item.name).fontWeight(.medium)
                                if item.requiresAdmin {
                                    Image(systemName: "lock.fill").foregroundStyle(.orange).help("Requires admin")
                                }
                                if item.dangerous {
                                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red).help("Dangerous — review carefully")
                                }
                            }
                            Text(item.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            if !item.paths.isEmpty {
                                Text(item.paths.joined(separator: " · ")).font(.system(.caption2, design: .monospaced)).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            if let s = item.size {
                                Text(byteString(s)).font(.system(.body, design: .monospaced))
                                    .foregroundStyle(s > 1_073_741_824 ? .red : (s > 104_857_600 ? .orange : .secondary))
                            } else if !item.paths.isEmpty {
                                Text("—").foregroundStyle(.tertiary)
                            } else {
                                Text("cmd").font(.caption).foregroundStyle(.tertiary)
                            }
                        }.frame(width: 90, alignment: .trailing)
                    }
                    .padding(.vertical, 4)
                    .contentShape(.rect)
                    .onTapGesture {
                        if let i = items.firstIndex(where: { $0.id == item.id }) { items[i].selected.toggle() }
                    }
                }
            }
            .frame(minWidth: 540)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Operation log").font(.headline)
                    Spacer()
                    if working { ProgressView().controlSize(.small) }
                    if !log.isEmpty {
                        Button("Clear") { log = "" }.buttonStyle(.bordered)
                    }
                }
                LogPane(placeholder: "No operations yet. Select items, then Clean Selected.", log: log)
            }
            .padding(.leading, 8)
            .frame(minWidth: 320)
        }
    }

    private func bindingFor(_ item: CleanupItem) -> Binding<Bool> {
        Binding(
            get: { items.first(where: { $0.id == item.id })?.selected ?? false },
            set: { v in if let i = items.firstIndex(where: { $0.id == item.id }) { items[i].selected = v } }
        )
    }

    private func byteString(_ b: Int64) -> String {
        if b == 0 { return "0 B" }
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: b)
    }

    @MainActor
    private func scanSizes() async {
        scanning = true
        let snapshot = items
        let results: [(UUID, Int64)] = await withTaskGroup(of: (UUID, Int64).self) { group in
            for item in snapshot where !item.paths.isEmpty {
                group.addTask { (item.id, ExtraCleanupService.computeSize(for: item)) }
            }
            var out: [(UUID, Int64)] = []
            for await r in group { out.append(r) }
            return out
        }
        for (id, size) in results {
            if let i = items.firstIndex(where: { $0.id == id }) { items[i].size = size }
        }
        scanning = false
    }

    private func runApply() {
        let chosen = items.filter { $0.selected }
        working = true
        Task.detached {
            let result = ExtraCleanupService.apply(chosen)
            await MainActor.run {
                log = result + (log.isEmpty ? "" : "\n---\n" + log)
                working = false
            }
            await scanSizes()
        }
    }
}
