import Foundation

struct OrphanLeftover: Identifiable, Hashable {
    let id = UUID()
    let bundleId: String      // reconstructed bundle id
    let path: String
    let location: String      // friendly location label
    var size: Int64
    var selected: Bool = false
}

enum OrphanFinder {
    /// Scan dirs that house per-bundle data and return entries whose bundle id
    /// no longer matches any installed app.
    static func scan(includeApple: Bool = false) async -> [OrphanLeftover] {
        await Task.detached(priority: .userInitiated) {
            let installed = AppListService.scanSync()
            let installedIds = Set(installed.map { $0.bundleId.lowercased() }.filter { !$0.isEmpty })
            return collect(installedIds: installedIds, includeApple: includeApple)
        }.value
    }

    static let scanLocations: [(label: String, path: String, isPlistDir: Bool)] = {
        let h = NSHomeDirectory()
        return [
            ("Application Support",   "\(h)/Library/Application Support",      false),
            ("Caches",                "\(h)/Library/Caches",                   false),
            ("Containers",            "\(h)/Library/Containers",               false),
            ("Group Containers",      "\(h)/Library/Group Containers",         false),
            ("HTTP Storages",         "\(h)/Library/HTTPStorages",             false),
            ("WebKit",                "\(h)/Library/WebKit",                   false),
            ("Saved Application State","\(h)/Library/Saved Application State", false),
            ("Logs",                  "\(h)/Library/Logs",                     false),
            ("Preferences",           "\(h)/Library/Preferences",              true),
            ("Preferences/ByHost",    "\(h)/Library/Preferences/ByHost",       true),
            ("Application Scripts",   "\(h)/Library/Application Scripts",      false),
            ("LaunchAgents",          "\(h)/Library/LaunchAgents",             true),
        ]
    }()

    /// Bundle prefixes considered "system" — present without any /Applications entry.
    /// We skip these unless includeApple == true.
    static let systemPrefixes: [String] = [
        "com.apple.",
        "com.adobe.",
        "com.google.Chrome.framework",   // helpers
        "com.microsoft.OneAuth",
        "com.microsoft.AutoUpdate",
        "com.barebones.",                // legitimate but hard to match
        "com.intel.",
        "com.nvidia.",
        "com.logi.",
        "com.zsa.",                      // keyboard tooling
        "com.amazon.aws.",
    ]

    private static func collect(installedIds: Set<String>, includeApple: Bool) -> [OrphanLeftover] {
        var out: [OrphanLeftover] = []
        let fm = FileManager.default

        for loc in scanLocations {
            guard let entries = try? fm.contentsOfDirectory(atPath: loc.path) else { continue }
            for entry in entries where !entry.hasPrefix(".") {
                guard let bid = bundleIdFromEntry(entry, isPlistDir: loc.isPlistDir) else { continue }
                if !includeApple && isSystem(bid) { continue }
                if isInstalled(bid: bid, installed: installedIds) { continue }
                let full = (loc.path as NSString).appendingPathComponent(entry)
                let size = sizeOf(full)
                guard size > 0 else { continue }
                out.append(OrphanLeftover(bundleId: bid, path: full, location: loc.label, size: size))
            }
        }
        return out.sorted { $0.size > $1.size }
    }

    /// Extract a candidate bundle id from a file/dir name. Returns nil if not bundle-id-shaped.
    /// Examples:
    ///   "com.example.App"                     → "com.example.App"
    ///   "com.example.App.plist"               → "com.example.App"        (plistDir)
    ///   "com.example.App.UUID.plist" (ByHost) → "com.example.App"
    private static func bundleIdFromEntry(_ name: String, isPlistDir: Bool) -> String? {
        var n = name
        if isPlistDir {
            if !n.hasSuffix(".plist") { return nil }
            n.removeLast(".plist".count)
            // ByHost: trim trailing UUID (32 hex chars + dashes possibly).
            // Pattern: <bid>.<UUID> where UUID is 36 chars with dashes or 32 hex.
            if let dot = n.range(of: ".", options: .backwards) {
                let suffix = String(n[dot.upperBound...])
                if suffix.count == 36 && suffix.contains("-") { n.removeSubrange(dot.lowerBound..<n.endIndex) }
                else if suffix.count == 32, suffix.allSatisfy({ $0.isHexDigit }) {
                    n.removeSubrange(dot.lowerBound..<n.endIndex)
                }
            }
        }
        // Must be reverse-DNS: at least 2 dots, starts with lowercase tld-like prefix.
        let parts = n.split(separator: ".")
        guard parts.count >= 3 else { return nil }
        let head = parts[0].lowercased()
        let allowedTLDs: Set<String> = ["com", "org", "net", "io", "ai", "co", "me",
                                        "dev", "app", "xyz", "us", "uk", "de", "tv",
                                        "ly", "fm", "edu", "biz", "info"]
        guard allowedTLDs.contains(head) else { return nil }
        return n
    }

    private static func isSystem(_ bid: String) -> Bool {
        let lower = bid.lowercased()
        return systemPrefixes.contains { lower.hasPrefix($0.lowercased()) }
    }

    private static func isInstalled(bid: String, installed: Set<String>) -> Bool {
        let lower = bid.lowercased()
        if installed.contains(lower) { return true }
        // Treat orphan as "installed" if any installed bundle is its descendant or ancestor.
        for inst in installed {
            if inst.hasPrefix(lower + ".") { return true }     // installed is child namespace
            if lower.hasPrefix(inst + ".") { return true }     // orphan is helper of installed
        }
        return false
    }

    private static func sizeOf(_ path: String) -> Int64 {
        let r = ShellRunner.run(executable: "/usr/bin/du", arguments: ["-sk", path])
        guard let first = r.output.split(separator: "\t", maxSplits: 1).first,
              let kb = Int64(first.trimmingCharacters(in: .whitespaces))
        else { return 0 }
        return kb * 1024
    }

    /// Move selected leftovers to Trash. Returns log.
    static func remove(_ items: [OrphanLeftover]) async -> String {
        await Task.detached(priority: .userInitiated) {
            var log = ""
            let fm = FileManager.default
            for item in items where fm.fileExists(atPath: item.path) {
                do {
                    try fm.trashItem(at: URL(fileURLWithPath: item.path), resultingItemURL: nil)
                    log += "→ trash \(item.path)\n"
                } catch {
                    let r = ShellRunner.run(executable: "/bin/rm", arguments: ["-rf", item.path])
                    log += "rm -rf \(item.path) → \(r.exit)\n"
                }
            }
            log += "\nDone (\(items.count) leftover\(items.count == 1 ? "" : "s") removed)\n"
            return log
        }.value
    }
}

private extension Character {
    var isHexDigit: Bool { isASCII && (isNumber || ("a"..."f").contains(lowercased().first ?? " ")) }
}
