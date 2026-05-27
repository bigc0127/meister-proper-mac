import Foundation

struct DiskNode: Identifiable, Hashable {
    let id = UUID()
    let path: String
    let name: String
    let size: Int64
    let isDirectory: Bool
    var children: [DiskNode] = []
    var loadedChildren: Bool = false
}

enum DiskAnalyzer {
    /// Top-level analysis: scan a root path, return immediate children sized.
    static func scanLevel(path: String) async -> [DiskNode] {
        await Task.detached(priority: .userInitiated) {
            collectChildren(path: path)
        }.value
    }

    private static func collectChildren(path: String) -> [DiskNode] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: path) else { return [] }
        var out: [DiskNode] = []
        for n in entries where !n.hasPrefix(".") {
            let full = (path as NSString).appendingPathComponent(n)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: full, isDirectory: &isDir) else { continue }
            let size = sizeOf(path: full, isDirectory: isDir.boolValue)
            out.append(DiskNode(path: full, name: n, size: size, isDirectory: isDir.boolValue))
        }
        return out.sorted { $0.size > $1.size }
    }

    private static func sizeOf(path: String, isDirectory: Bool) -> Int64 {
        if !isDirectory {
            let attrs = try? FileManager.default.attributesOfItem(atPath: path)
            return (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        }
        // Directories: shell out to du -sk for accurate apparent size.
        let r = ShellRunner.run(executable: "/usr/bin/du", arguments: ["-sk", path])
        guard let first = r.output.split(separator: "\t", maxSplits: 1).first,
              let kb = Int64(first.trimmingCharacters(in: .whitespaces)) else { return 0 }
        return kb * 1024
    }
}
