import SwiftUI
import AppKit

struct CleanView: View {
    @State private var targets: [CleanTarget] = CleanCatalog.allTargets()
    @State private var scanning = false
    @State private var working = false
    @State private var dryRun = true
    @State private var log = ""
    @State private var showApplyConfirm = false
    @State private var search = ""
    @State private var categoryFilter = "All"

    var categories: [String] { ["All"] + CleanCategory.allCases.map { $0.rawValue } }
    var filtered: [CleanTarget] {
        targets.filter { t in
            let mc = categoryFilter == "All" || t.category.rawValue == categoryFilter
            let q = search.trimmingCharacters(in: .whitespaces)
            let ms = q.isEmpty || t.label.localizedCaseInsensitiveContains(q)
                                || t.detail.localizedCaseInsensitiveContains(q)
                                || t.paths.contains(where: { $0.localizedCaseInsensitiveContains(q) })
            return mc && ms
        }
    }
    var selected: [CleanTarget] { targets.filter { $0.selected } }
    var totalBytes: Int64 { selected.compactMap { $0.size }.reduce(0, +) }

    var body: some View {
        VStack(spacing: 12) {
            tccBanner
            toolbar
            content
        }
        .padding(16)
        .navigationTitle("Clean")
        .alert("Apply \(selected.count) cleanup task(s)?", isPresented: $showApplyConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Apply", role: .destructive) { apply(dry: false) }
        } message: {
            let dangerCount = selected.filter { $0.dangerous }.count
            let needsAdmin  = selected.contains(where: { $0.requiresAdmin })
            var msg = "These items will be deleted permanently (not Trash)."
            if dangerCount > 0 { msg += "\n\n⚠ \(dangerCount) flagged dangerous." }
            if needsAdmin { msg += "\n\nAdmin password requested for system items." }
            return Text(msg)
        }
    }

    private var tccBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle").foregroundStyle(.blue)
            Text("Click any 🔓 to escalate that item to admin (bypasses TCC blocks like ~/Library/Caches). Items with a solid 🔒 always need admin.")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Open Privacy Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
            }
            .buttonStyle(.link).font(.caption)
            .help("To clean every protected path without password prompts, grant Meister Proper Full Disk Access here.")
        }
        .padding(8)
        .background(.blue.opacity(0.08), in: .rect(cornerRadius: 6))
    }

    private var toolbar: some View {
        HStack {
            Button { Task { await scanSizes() } } label: {
                Label(scanning ? "Scanning…" : "Calculate Sizes", systemImage: "ruler")
            }.disabled(scanning || working)

            Picker("", selection: $categoryFilter) {
                ForEach(categories, id: \.self) { Text($0).tag($0) }
            }.frame(width: 200)

            TextField("Search…", text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 220)

            Button {
                let allOn = filtered.allSatisfy { $0.selected }
                let ids = Set(filtered.map { $0.id })
                for i in targets.indices where ids.contains(targets[i].id) {
                    targets[i].selected = !allOn && !targets[i].dangerous && !targets[i].requiresAdmin
                }
            } label: { Label("Toggle Safe", systemImage: "checkmark.square") }.disabled(working)

            Button { for i in targets.indices { targets[i].selected = false } } label: {
                Label("Clear", systemImage: "square")
            }.disabled(working)

            Spacer()
            Toggle("Dry run", isOn: $dryRun).toggleStyle(.checkbox)
            Text("\(selected.count) sel · \(byteString(totalBytes))").foregroundStyle(.secondary)
            Button { apply(dry: true) } label: { Label("Preview", systemImage: "eye") }
                .disabled(selected.isEmpty || working)
            Button(role: .destructive) { showApplyConfirm = true } label: {
                Label("Apply", systemImage: "trash")
            }
            .buttonStyle(.borderedProminent).tint(.red)
            .disabled(selected.isEmpty || working)
        }
    }

    private var content: some View {
        HSplitView {
            List {
                ForEach(CleanCategory.allCases, id: \.self) { cat in
                    let group = filtered.filter { $0.category == cat }
                    if !group.isEmpty {
                        Section {
                            ForEach(group) { item in row(item) }
                        } header: {
                            HStack {
                                Text(cat.rawValue)
                                Spacer()
                                let groupBytes = group.compactMap { $0.size }.reduce(0, +)
                                if groupBytes > 0 { Text(byteString(groupBytes)).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
            }
            .frame(minWidth: 580)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Log").font(.headline)
                    Spacer()
                    if working { ProgressView().controlSize(.small) }
                    if !log.isEmpty { Button("Clear") { log = "" }.buttonStyle(.bordered) }
                }
                LogPane(placeholder: "Select items, then Preview or Apply.", log: log)
            }
            .padding(.leading, 8)
            .frame(minWidth: 320)
        }
    }

    private func row(_ item: CleanTarget) -> some View {
        HStack(alignment: .top) {
            Toggle("", isOn: bindingFor(item)).labelsHidden().padding(.top, 4)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(item.label).fontWeight(.medium)
                    lockButton(for: item)
                    if item.dangerous { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red).help("Dangerous") }
                }
                Text(item.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if !item.paths.isEmpty {
                    Text(item.paths.joined(separator: " · "))
                        .font(.system(.caption2, design: .monospaced)).foregroundStyle(.tertiary)
                        .lineLimit(1).truncationMode(.middle)
                }
                if let cmd = item.command {
                    Text(cmd).font(.system(.caption2, design: .monospaced)).foregroundStyle(.blue.opacity(0.7))
                        .lineLimit(1).truncationMode(.tail)
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
        .padding(.vertical, 3)
        .contentShape(.rect)
        .onTapGesture {
            if let i = targets.firstIndex(where: { $0.id == item.id }) { targets[i].selected.toggle() }
        }
    }

    private func lockButton(for item: CleanTarget) -> some View {
        Button {
            guard !item.requiresAdmin else { return }
            if let i = targets.firstIndex(where: { $0.id == item.id }) {
                targets[i].useAdminOverride.toggle()
            }
        } label: {
            Image(systemName: item.effectiveAdmin ? "lock.fill" : "lock.open")
                .foregroundStyle(item.effectiveAdmin ? .orange : .secondary.opacity(0.5))
        }
        .buttonStyle(.plain)
        .disabled(item.requiresAdmin)
        .help(item.requiresAdmin
              ? "Always runs with admin (TCC-protected path)"
              : (item.useAdminOverride
                 ? "Admin override on — click to disable"
                 : "Click to run this item with admin (bypasses TCC)"))
    }

    private func bindingFor(_ item: CleanTarget) -> Binding<Bool> {
        Binding(
            get: { targets.first(where: { $0.id == item.id })?.selected ?? false },
            set: { v in if let i = targets.firstIndex(where: { $0.id == item.id }) { targets[i].selected = v } }
        )
    }

    private func byteString(_ b: Int64) -> String {
        if b == 0 { return "0 B" }
        let f = ByteCountFormatter(); f.countStyle = .file
        return f.string(fromByteCount: b)
    }

    @MainActor
    private func scanSizes() async {
        scanning = true
        let snapshot = targets
        let results: [(UUID, Int64)] = await withTaskGroup(of: (UUID, Int64).self) { group in
            for t in snapshot where !t.paths.isEmpty {
                group.addTask { (t.id, CleanService.computeSize(for: t)) }
            }
            var out: [(UUID, Int64)] = []
            for await r in group { out.append(r) }
            return out
        }
        for (id, size) in results {
            if let i = targets.firstIndex(where: { $0.id == id }) { targets[i].size = size }
        }
        scanning = false
    }

    private func apply(dry: Bool) {
        let chosen = selected
        log = ""
        working = true
        Task {
            await CleanService.apply(chosen, dryRun: dry) { line in
                await MainActor.run { log += line + "\n" }
            }
            await MainActor.run { working = false }
            if !dry { await scanSizes() }
        }
    }
}
