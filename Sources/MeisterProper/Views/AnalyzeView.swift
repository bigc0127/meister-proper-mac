import SwiftUI
import AppKit

struct AnalyzeView: View {
    @State private var rootPath: String = NSHomeDirectory()
    @State private var nodes: [DiskNode] = []
    @State private var path: [String] = []   // breadcrumb
    @State private var loading = false

    var body: some View {
        VStack(spacing: 12) {
            toolbar
            breadcrumb
            list
        }
        .padding(16)
        .navigationTitle("Analyze")
        .task { await load(rootPath) }
    }

    private var toolbar: some View {
        HStack {
            TextField("Path", text: $rootPath).textFieldStyle(.roundedBorder)
                .onSubmit { Task { await load(rootPath) } }
            Button { Task { await load(rootPath) } } label: { Label("Scan", systemImage: "magnifyingglass") }
                .disabled(loading)
            Button("Home") { rootPath = NSHomeDirectory(); Task { await load(rootPath) } }
            Button("/") { rootPath = "/"; Task { await load(rootPath) } }
        }
    }

    private var breadcrumb: some View {
        HStack {
            ForEach(Array(path.enumerated()), id: \.offset) { idx, comp in
                Button(comp) {
                    let newPath = "/" + path.prefix(idx + 1).joined(separator: "/")
                    rootPath = newPath
                    Task { await load(newPath) }
                }.buttonStyle(.link)
                if idx < path.count - 1 { Text("›").foregroundStyle(.secondary) }
            }
            Spacer()
            if loading { ProgressView().controlSize(.small) }
        }
    }

    private var list: some View {
        let totalBytes = nodes.map { $0.size }.reduce(0, +)
        return List {
            ForEach(nodes) { node in
                HStack {
                    Image(systemName: node.isDirectory ? "folder.fill" : "doc.fill")
                        .foregroundStyle(node.isDirectory ? .blue : .secondary)
                    Button(node.name) {
                        if node.isDirectory { rootPath = node.path; Task { await load(node.path) } }
                    }.buttonStyle(.plain)
                    Spacer()
                    if totalBytes > 0 {
                        let frac = Double(node.size) / Double(totalBytes)
                        ProgressView(value: frac)
                            .progressViewStyle(.linear)
                            .frame(width: 120)
                            .tint(node.size > 1_073_741_824 ? .red : (node.size > 104_857_600 ? .orange : .green))
                    }
                    Text(byteString(node.size))
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(node.size > 1_073_741_824 ? .red : (node.size > 104_857_600 ? .orange : .secondary))
                        .frame(width: 90, alignment: .trailing)
                    if node.isDirectory {
                        Button { NSWorkspace.shared.open(URL(fileURLWithPath: node.path)) } label: {
                            Image(systemName: "arrow.up.right.square")
                        }.buttonStyle(.borderless).help("Reveal in Finder")
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func byteString(_ b: Int64) -> String {
        let f = ByteCountFormatter(); f.countStyle = .file
        return f.string(fromByteCount: b)
    }

    @MainActor
    private func load(_ p: String) async {
        loading = true
        let exp = (p as NSString).expandingTildeInPath
        rootPath = exp
        path = exp.split(separator: "/").map(String.init)
        nodes = await DiskAnalyzer.scanLevel(path: exp)
        loading = false
    }
}
