import SwiftUI

struct InstallerView: View {
    @State private var hits: [InstallerHit] = []
    @State private var scanning = false
    @State private var working = false
    @State private var log = ""
    @State private var ageFilter: Int = 0    // 0 = all
    @State private var showConfirm = false

    var ageFiltered: [InstallerHit] {
        if ageFilter == 0 { return hits }
        let cutoff = Date().addingTimeInterval(TimeInterval(-ageFilter * 86400))
        return hits.filter { $0.modified < cutoff }
    }
    var selected: [InstallerHit] { ageFiltered.filter { $0.selected } }
    var totalBytes: Int64 { selected.map { $0.size }.reduce(0, +) }

    var body: some View {
        VStack(spacing: 12) {
            toolbar
            content
        }
        .padding(16)
        .navigationTitle("Installers")
        .alert("Move \(selected.count) installer(s) to Trash?", isPresented: $showConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Move to Trash", role: .destructive) { apply(permanent: false) }
            Button("Delete Permanently", role: .destructive) { apply(permanent: true) }
        } message: {
            Text("Total \(byteString(totalBytes)).")
        }
        .task { await scan() }
    }

    private var toolbar: some View {
        HStack {
            Button { Task { await scan() } } label: {
                Label(scanning ? "Scanning…" : "Re-scan", systemImage: "arrow.clockwise")
            }.disabled(scanning || working)

            Picker("Age", selection: $ageFilter) {
                Text("All").tag(0); Text("≥7d").tag(7); Text("≥30d").tag(30); Text("≥90d").tag(90)
            }.pickerStyle(.segmented).frame(width: 220)

            Button {
                let allOn = ageFiltered.allSatisfy { $0.selected }
                let ids = Set(ageFiltered.map { $0.id })
                for i in hits.indices where ids.contains(hits[i].id) { hits[i].selected = !allOn }
            } label: { Label("Toggle All", systemImage: "checkmark.square") }
            Spacer()
            Text("\(ageFiltered.count) found · \(selected.count) sel · \(byteString(totalBytes))").foregroundStyle(.secondary)
            Button(role: .destructive) { showConfirm = true } label: {
                Label("Remove", systemImage: "trash")
            }
            .buttonStyle(.borderedProminent).tint(.red).disabled(selected.isEmpty || working)
        }
    }

    private var content: some View {
        HSplitView {
            List {
                if ageFiltered.isEmpty && !scanning {
                    Text("No installer files found in your Downloads / Desktop / Documents / brew cache / iCloud Downloads / Telegram / Mail Downloads.")
                        .foregroundStyle(.secondary).padding()
                } else {
                    ForEach(ageFiltered) { h in
                        HStack {
                            Toggle("", isOn: bindingFor(h)).labelsHidden()
                            Image(systemName: iconFor(ext: h.ext)).foregroundStyle(.blue).frame(width: 18)
                            VStack(alignment: .leading) {
                                Text((h.path as NSString).lastPathComponent).fontWeight(.medium)
                                Text((h.path as NSString).abbreviatingWithTildeInPath)
                                    .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                                    .lineLimit(1).truncationMode(.middle)
                            }
                            Spacer()
                            Text(h.modified.formatted(.dateTime.year().month().day())).font(.caption).foregroundStyle(.secondary)
                            Text(byteString(h.size)).font(.system(.body, design: .monospaced))
                                .foregroundStyle(h.size > 100_000_000 ? .orange : .secondary)
                                .frame(width: 90, alignment: .trailing)
                        }
                        .padding(.vertical, 2)
                        .contentShape(.rect)
                        .onTapGesture {
                            if let i = hits.firstIndex(where: { $0.id == h.id }) { hits[i].selected.toggle() }
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
            .frame(minWidth: 260)
        }
    }

    private func bindingFor(_ h: InstallerHit) -> Binding<Bool> {
        Binding(
            get: { hits.first(where: { $0.id == h.id })?.selected ?? false },
            set: { v in if let i = hits.firstIndex(where: { $0.id == h.id }) { hits[i].selected = v } }
        )
    }

    private func iconFor(ext: String) -> String {
        switch ext {
        case "dmg": return "opticaldisc"
        case "pkg", "mpkg": return "shippingbox"
        case "iso": return "opticaldiscdrive"
        case "xip": return "doc.zipper"
        case "zip": return "archivebox"
        default: return "doc"
        }
    }

    private func byteString(_ b: Int64) -> String {
        let f = ByteCountFormatter(); f.countStyle = .file
        return f.string(fromByteCount: b)
    }

    @MainActor
    private func scan() async {
        scanning = true
        log = "Scanning installer locations…\n"
        let result = await InstallerScanner.scan()
        hits = result
        scanning = false
        log += "Found \(result.count) file(s)\n"
    }

    private func apply(permanent: Bool) {
        let chosen = selected
        working = true
        log += "\n\(permanent ? "Deleting" : "Trashing") \(chosen.count) file(s)…\n"
        Task {
            let result = await InstallerScanner.remove(chosen, permanent: permanent)
            await MainActor.run {
                log += result
                working = false
                hits.removeAll { h in chosen.contains(where: { $0.id == h.id }) }
            }
        }
    }
}
