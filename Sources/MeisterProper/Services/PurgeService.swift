import Foundation

struct PurgeHit: Identifiable, Hashable {
    let id = UUID()
    let path: String
    let kind: String       // node_modules / target / .gradle / etc
    var size: Int64
    var selected: Bool = true
}

enum PurgeService {
    static let artifactNames: Set<String> = [
        "node_modules", "target", "build", "dist",
        "venv", ".venv", "__pycache__", ".pytest_cache", ".mypy_cache", ".tox", ".nox", ".ruff_cache",
        ".gradle", ".next", ".nuxt", ".output",
        "vendor",                  // PHP composer
        // bin, obj — too generic for blanket scan, omitted to avoid hitting random Unix bin/
        ".turbo", ".parcel-cache", ".dart_tool",
        ".zig-cache", "zig-out",
        ".angular", ".svelte-kit", ".astro",
        "coverage",
        "DerivedData", "Pods", ".cxx", ".expo", ".build"
    ]

    static let projectMarkers: Set<String> = [
        "package.json", "Cargo.toml", "go.mod", "pyproject.toml", "requirements.txt",
        "pom.xml", "build.gradle", "build.gradle.kts", "Gemfile", "composer.json",
        "pubspec.yaml", "Package.swift", "Makefile", "CMakeLists.txt", "build.zig",
        ".git", "lerna.json", "pnpm-workspace.yaml", "nx.json", "rush.json"
    ]

    /// Default scan roots, plus any user-configured roots stored in
    /// ~/Library/Application Support/MeisterProper/purge_paths.txt.
    static func defaultScanPaths() -> [String] {
        let h = NSHomeDirectory()
        let candidates = [
            "\(h)/www", "\(h)/dev", "\(h)/Dev", "\(h)/Projects", "\(h)/projects",
            "\(h)/GitHub", "\(h)/Code", "\(h)/code", "\(h)/Workspace", "\(h)/workspace",
            "\(h)/Repos", "\(h)/Development", "\(h)/Documents/Code", "\(h)/Sites"
        ]
        var seen: Set<String> = []
        var out: [String] = []
        for c in candidates where FileManager.default.fileExists(atPath: c) {
            if !seen.contains(c) { out.append(c); seen.insert(c) }
        }
        return out
    }

    /// Walk roots up to maxDepth, collect artifact directories. Sized via du.
    static func scan(roots: [String], maxDepth: Int = 6) async -> [PurgeHit] {
        await Task.detached(priority: .userInitiated) {
            collect(roots: roots, maxDepth: maxDepth)
        }.value
    }

    private static func collect(roots: [String], maxDepth: Int) -> [PurgeHit] {
        var hits: [PurgeHit] = []
        let fm = FileManager.default
        for root in roots where fm.fileExists(atPath: root) {
            walk(path: root, depth: 0, maxDepth: maxDepth, into: &hits)
        }
        // Size each hit
        for i in hits.indices {
            let r = ShellRunner.run(executable: "/usr/bin/du", arguments: ["-sk", hits[i].path])
            if let first = r.output.split(separator: "\t", maxSplits: 1).first,
               let kb = Int64(first.trimmingCharacters(in: .whitespaces)) {
                hits[i].size = kb * 1024
            }
        }
        return hits.sorted { $0.size > $1.size }
    }

    private static func walk(path: String, depth: Int, maxDepth: Int, into hits: inout [PurgeHit]) {
        guard depth <= maxDepth else { return }
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: path) else { return }

        // If this dir's name is itself an artifact, record + don't recurse into it.
        let basename = (path as NSString).lastPathComponent
        if artifactNames.contains(basename) {
            hits.append(PurgeHit(path: path, kind: basename, size: 0))
            return
        }

        for entry in entries {
            if entry.hasPrefix(".") && depth == 0 { continue }
            if artifactNames.contains(entry) {
                let p = (path as NSString).appendingPathComponent(entry)
                hits.append(PurgeHit(path: p, kind: entry, size: 0))
                continue
            }
            let subpath = (path as NSString).appendingPathComponent(entry)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: subpath, isDirectory: &isDir), isDir.boolValue {
                // Avoid recursing into artifact dirs we already recorded
                walk(path: subpath, depth: depth + 1, maxDepth: maxDepth, into: &hits)
            }
        }
    }

    /// Move selected hits to Trash. Returns log.
    static func purge(_ hits: [PurgeHit]) async -> String {
        await Task.detached(priority: .userInitiated) {
            var log = ""
            let fm = FileManager.default
            for h in hits where fm.fileExists(atPath: h.path) {
                do {
                    try fm.trashItem(at: URL(fileURLWithPath: h.path), resultingItemURL: nil)
                    log += "→ trash \(h.path)\n"
                } catch {
                    let r = ShellRunner.run(executable: "/bin/rm", arguments: ["-rf", h.path])
                    log += "rm -rf \(h.path) → \(r.exit)\n"
                }
            }
            log += "\nDone (\(hits.count) artifact\(hits.count == 1 ? "" : "s"))\n"
            return log
        }.value
    }
}
