import SwiftUI
import AppKit

struct UninstallPickerView: View {
    @State private var apps: [InstalledApp] = []
    @State private var loading = true
    @State private var search = ""
    @State private var sourceFilter: String = "All"
    @State private var permanent = false
    @State private var showApplyConfirm = false
    @State private var leftovers: [InstalledApp.ID: [String]] = [:]
    @State private var selectedAppForDetail: InstalledApp? = nil
    @State private var log = ""
    @State private var working = false
    @State private var iconCache: [String: NSImage] = [:]

    var sources: [String] { ["All"] + Array(Set(apps.map { $0.source })).sorted() }

    var filtered: [InstalledApp] {
        apps.filter { app in
            let matchSource = sourceFilter == "All" || app.source == sourceFilter
            let q = search.trimmingCharacters(in: .whitespaces)
            let matchSearch = q.isEmpty || app.name.localizedCaseInsensitiveContains(q) || app.bundleId.localizedCaseInsensitiveContains(q)
            return matchSource && matchSearch
        }
    }

    var selectedApps: [InstalledApp] { apps.filter { $0.selected } }

    var body: some View {
        VStack(spacing: 12) {
            toolbar
            if loading {
                ProgressView("Scanning installed apps…").frame(maxHeight: .infinity)
            } else {
                content
            }
        }
        .padding(16)
        .navigationTitle("App Uninstall")
        .task { await loadApps() }
        .alert("Uninstall \(selectedApps.count) app(s)?", isPresented: $showApplyConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Move to Trash", role: .destructive) { uninstall(permanent: false) }
            Button("Delete Permanently", role: .destructive) { uninstall(permanent: true) }
        } message: {
            let leftCount = selectedApps.reduce(0) { $0 + (leftovers[$1.id]?.count ?? 0) }
            Text("\(selectedApps.count) app(s) + \(leftCount) leftover paths.")
        }
    }

    private var toolbar: some View {
        HStack {
            TextField("Search apps…", text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 280)
            Picker("", selection: $sourceFilter) {
                ForEach(sources, id: \.self) { Text($0).tag($0) }
            }.frame(width: 140)
            Spacer()
            Text("\(selectedApps.count) selected").foregroundStyle(.secondary)
            Button { Task { await scanLeftovers() } } label: {
                Label("Find Leftovers", systemImage: "magnifyingglass")
            }.disabled(selectedApps.isEmpty || working)
            Button(role: .destructive) { showApplyConfirm = true } label: {
                Label("Uninstall", systemImage: "trash")
            }
            .buttonStyle(.borderedProminent).tint(.red)
            .disabled(selectedApps.isEmpty || working)
            Button { Task { await loadApps() } } label: { Image(systemName: "arrow.clockwise") }.help("Re-scan")
        }
    }

    private var content: some View {
        HSplitView {
            // App list
            List {
                ForEach(filtered) { app in
                    HStack {
                        Toggle("", isOn: bindingFor(app)).labelsHidden()
                        if let icon = iconFor(app.path) {
                            Image(nsImage: icon).resizable().frame(width: 28, height: 28)
                        } else {
                            Image(systemName: "app.dashed").frame(width: 28).foregroundStyle(.secondary)
                        }
                        VStack(alignment: .leading) {
                            Text(app.name).fontWeight(.medium)
                            Text(app.bundleId.isEmpty ? app.path : app.bundleId)
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Text(app.source).font(.caption).padding(4).background(.background.tertiary, in: .capsule)
                        Text(app.size).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).frame(width: 70, alignment: .trailing)
                    }
                    .padding(.vertical, 2)
                    .contentShape(.rect)
                    .onTapGesture {
                        selectedAppForDetail = app
                        if let i = apps.firstIndex(where: { $0.id == app.id }) { apps[i].selected.toggle() }
                    }
                }
            }
            .frame(minWidth: 480)

            // Leftover detail / log
            VStack(alignment: .leading, spacing: 8) {
                if let app = selectedAppForDetail, let paths = leftovers[app.id] {
                    Text("\(app.name) leftovers (\(paths.count))").font(.headline)
                    List {
                        ForEach(paths, id: \.self) { p in
                            HStack {
                                Image(systemName: p.hasPrefix("/Library/") || p.hasPrefix("/System/") ? "lock.fill" : "doc.text")
                                    .foregroundStyle(p.hasPrefix("/Library/") ? .orange : .secondary)
                                Text((p as NSString).abbreviatingWithTildeInPath)
                                    .font(.system(.caption, design: .monospaced))
                                    .lineLimit(1).truncationMode(.middle)
                            }
                        }
                    }
                    .frame(minHeight: 200)
                } else {
                    Text("Tap an app to see candidates, or click Find Leftovers for selected apps.")
                        .foregroundStyle(.secondary).padding()
                }
                Divider()
                Text("Operation log").font(.headline)
                LogPane(placeholder: "No operations yet.", log: log)
            }
            .padding(.leading, 8)
            .frame(minWidth: 360)
        }
    }

    private func bindingFor(_ app: InstalledApp) -> Binding<Bool> {
        Binding(
            get: { apps.first(where: { $0.id == app.id })?.selected ?? false },
            set: { v in if let i = apps.firstIndex(where: { $0.id == app.id }) { apps[i].selected = v } }
        )
    }

    private func iconFor(_ path: String) -> NSImage? {
        if let cached = iconCache[path] { return cached }
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let img = NSWorkspace.shared.icon(forFile: path)
        img.size = NSSize(width: 28, height: 28)
        iconCache[path] = img
        return img
    }

    @MainActor
    private func loadApps() async {
        loading = true; log = ""
        let prevSelected = Set(apps.filter { $0.selected }.map { $0.path })
        var fresh = await AppListService.scan()
        for i in fresh.indices where prevSelected.contains(fresh[i].path) { fresh[i].selected = true }
        apps = fresh
        loading = false
    }

    @MainActor
    private func scanLeftovers() async {
        working = true
        log += "Scanning leftovers for \(selectedApps.count) app(s)…\n"
        let chosen = selectedApps
        let result: [InstalledApp.ID: [String]] = await Task.detached(priority: .userInitiated) {
            var out: [InstalledApp.ID: [String]] = [:]
            for app in chosen { out[app.id] = UninstallEngine.leftoverPaths(for: app) }
            return out
        }.value
        leftovers.merge(result) { _, new in new }
        for (id, paths) in result {
            if let app = apps.first(where: { $0.id == id }) {
                log += "  \(app.name): \(paths.count) leftovers\n"
            }
        }
        working = false
    }

    private func uninstall(permanent: Bool) {
        let chosen = selectedApps
        working = true
        log += "\n\(permanent ? "Permanently deleting" : "Trashing") \(chosen.count) app(s)…\n"
        Task {
            let result = await UninstallEngine.uninstall(chosen, leftovers: leftovers, permanent: permanent)
            await MainActor.run {
                log += result
                working = false
            }
            await loadApps()
        }
    }
}
