import Foundation

struct InstallerHit: Identifiable, Hashable {
    let id = UUID()
    let path: String
    let ext: String
    let size: Int64
    let modified: Date
    var selected: Bool = false
}

enum InstallerScanner {
    static let extensions: Set<String> = ["dmg", "pkg", "mpkg", "iso", "xip", "zip"]

    static func defaultScanPaths() -> [String] {
        let h = NSHomeDirectory()
        return [
            "\(h)/Downloads",
            "\(h)/Desktop",
            "\(h)/Documents",
            "\(h)/Public",
            "\(h)/Library/Downloads",
            "/Users/Shared",
            "/Users/Shared/Downloads",
            "\(h)/Library/Caches/Homebrew",
            "\(h)/Library/Mobile Documents/com~apple~CloudDocs/Downloads",
            "\(h)/Library/Containers/com.apple.mail/Data/Library/Mail Downloads",
            "\(h)/Library/Application Support/Telegram Desktop",
            "\(h)/Downloads/Telegram Desktop",
        ]
    }

    static func scan(paths: [String]? = nil, maxDepth: Int = 2) async -> [InstallerHit] {
        await Task.detached(priority: .userInitiated) {
            collect(paths: paths ?? defaultScanPaths(), maxDepth: maxDepth)
        }.value
    }

    private static func collect(paths: [String], maxDepth: Int) -> [InstallerHit] {
        var hits: [InstallerHit] = []
        let fm = FileManager.default
        for root in paths where fm.fileExists(atPath: root) {
            walk(root: root, dir: root, depth: 0, maxDepth: maxDepth, hits: &hits)
        }
        return hits.sorted { $0.size > $1.size }
    }

    private static func walk(root: String, dir: String, depth: Int, maxDepth: Int, hits: inout [InstallerHit]) {
        guard depth <= maxDepth else { return }
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: dir) else { return }
        for n in names where !n.hasPrefix(".") {
            let full = (dir as NSString).appendingPathComponent(n)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: full, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                walk(root: root, dir: full, depth: depth + 1, maxDepth: maxDepth, hits: &hits)
            } else {
                let ext = (n as NSString).pathExtension.lowercased()
                guard extensions.contains(ext) else { continue }
                if let attrs = try? fm.attributesOfItem(atPath: full) {
                    let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
                    let mod  = attrs[.modificationDate] as? Date ?? Date()
                    hits.append(InstallerHit(path: full, ext: ext, size: size, modified: mod))
                }
            }
        }
    }

    static func remove(_ hits: [InstallerHit], permanent: Bool) async -> String {
        await Task.detached(priority: .userInitiated) {
            var log = ""
            let fm = FileManager.default
            for h in hits where fm.fileExists(atPath: h.path) {
                if permanent {
                    let r = ShellRunner.run(executable: "/bin/rm", arguments: ["-f", h.path])
                    log += "rm -f \(h.path) → \(r.exit)\n"
                } else {
                    do {
                        try fm.trashItem(at: URL(fileURLWithPath: h.path), resultingItemURL: nil)
                        log += "→ trash \(h.path)\n"
                    } catch {
                        log += "trash failed \(h.path): \(error.localizedDescription)\n"
                    }
                }
            }
            return log
        }.value
    }
}
