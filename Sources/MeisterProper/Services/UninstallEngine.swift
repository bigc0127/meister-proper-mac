import Foundation

enum UninstallEngine {
    /// Discover leftover paths for an app: bundle id matches and app-name matches.
    static func leftoverPaths(for app: InstalledApp) -> [String] {
        let home = NSHomeDirectory()
        let userDirs = [
            "\(home)/Library/Preferences",
            "\(home)/Library/Preferences/ByHost",
            "\(home)/Library/Application Support",
            "\(home)/Library/Caches",
            "\(home)/Library/Containers",
            "\(home)/Library/Group Containers",
            "\(home)/Library/Saved Application State",
            "\(home)/Library/LaunchAgents",
            "\(home)/Library/HTTPStorages",
            "\(home)/Library/WebKit",
            "\(home)/Library/Cookies",
            "\(home)/Library/Application Scripts",
            "\(home)/Library/Logs",
        ]
        let systemDirs = [
            "/Library/Preferences",
            "/Library/Application Support",
            "/Library/Caches",
            "/Library/LaunchAgents",
            "/Library/LaunchDaemons",
            "/Library/PrivilegedHelperTools",
            "/Library/Logs/DiagnosticReports",
        ]

        var matches: [String] = []
        let bid = app.bundleId
        let nm  = app.name

        for dir in userDirs + systemDirs {
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir) else { continue }
            for n in names {
                if matchesApp(name: n, bundleId: bid, appName: nm) {
                    matches.append((dir as NSString).appendingPathComponent(n))
                }
            }
        }
        return matches
    }

    private static func matchesApp(name n: String, bundleId bid: String, appName: String) -> Bool {
        let lower = n.lowercased()
        if !bid.isEmpty {
            let bidLower = bid.lowercased()
            if lower.hasPrefix(bidLower) || lower.contains(bidLower) { return true }
        }
        if !appName.isEmpty {
            let appLower = appName.lowercased()
            // Match dirs/plists named exactly the app, case-insensitively, but avoid
            // matching very generic names like "Cache" (handled by length check).
            if appLower.count >= 4, lower.hasPrefix(appLower) || lower == appLower {
                return true
            }
        }
        return false
    }

    /// Move app + leftovers to Trash (or rm -rf if `permanent`).
    /// System-scope items are batched into a single admin script.
    /// Returns combined log.
    static func uninstall(_ apps: [InstalledApp], leftovers: [InstalledApp.ID: [String]], permanent: Bool) async -> String {
        var log = ""
        let home = NSHomeDirectory()
        let trashDir = "\(home)/.Trash"

        var systemPathsToRemove: [String] = []

        for app in apps {
            log += "\n▶ \(app.name)\n"

            // App bundle itself
            let appPath = app.path
            let isSystemApp = appPath.hasPrefix("/System/")
            if isSystemApp {
                log += "  skip (system app, not removable): \(appPath)\n"
            } else if appPath.hasPrefix("/Applications/") || appPath.hasPrefix(home) {
                if permanent {
                    let r = ShellRunner.run(executable: "/bin/rm", arguments: ["-rf", appPath])
                    log += "  rm -rf \(appPath) → \(r.exit)\n"
                } else {
                    let dest = (trashDir as NSString).appendingPathComponent((appPath as NSString).lastPathComponent)
                    let r = moveToTrash(src: appPath, dest: dest)
                    log += "  → trash \(appPath) (\(r ? "ok" : "fail"))\n"
                }
            } else {
                // System scope (e.g. /Library/...) — batch
                systemPathsToRemove.append(appPath)
            }

            // Leftovers
            let paths = leftovers[app.id] ?? []
            for p in paths {
                let isSystem = p.hasPrefix("/Library/")
                if isSystem {
                    systemPathsToRemove.append(p)
                    continue
                }
                if permanent {
                    let r = ShellRunner.run(executable: "/bin/rm", arguments: ["-rf", p])
                    log += "  rm -rf \(p) → \(r.exit)\n"
                } else {
                    let dest = (trashDir as NSString).appendingPathComponent((p as NSString).lastPathComponent)
                    let ok = moveToTrash(src: p, dest: dest)
                    log += "  → trash \(p) (\(ok ? "ok" : "fail"))\n"
                }
            }
        }

        if !systemPathsToRemove.isEmpty {
            log += "\n=== Admin batch (\(systemPathsToRemove.count) system paths) ===\n"
            var script = "set +e\n"
            for p in systemPathsToRemove {
                script += "if [ -e '\(p)' ]; then /bin/rm -rf '\(p)' && echo 'removed \(p)'; fi\n"
            }
            let tmp = (NSTemporaryDirectory() as NSString).appendingPathComponent("mp-uninstall-\(UUID().uuidString).sh")
            try? script.write(toFile: tmp, atomically: true, encoding: .utf8)
            _ = ShellRunner.run(executable: "/bin/chmod", arguments: ["+x", tmp])
            let r = ShellRunner.run(executable: "/usr/bin/osascript",
                                    arguments: ["-e", "do shell script \"/bin/bash \(tmp)\" with administrator privileges"])
            try? FileManager.default.removeItem(atPath: tmp)
            let parts = r.output.split(omittingEmptySubsequences: false) { $0 == "\n" || $0 == "\r" }
            for p in parts where !p.isEmpty { log += String(p) + "\n" }
            log += "[admin exit \(r.exit)]\n"
        }

        return log
    }

    private static func moveToTrash(src: String, dest baseDest: String) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: src) else { return false }
        var dest = baseDest
        var i = 1
        while fm.fileExists(atPath: dest) {
            dest = "\(baseDest) \(i)"
            i += 1
        }
        do {
            try fm.moveItem(atPath: src, toPath: dest)
            return true
        } catch {
            // fallback: NSWorkspace recycle
            let url = URL(fileURLWithPath: src)
            do {
                try fm.trashItem(at: url, resultingItemURL: nil)
                return true
            } catch {
                return false
            }
        }
    }
}
