import Foundation

enum ExtraCleanupService {
    static func defaultItems() -> [CleanupItem] {
        let home = NSHomeDirectory()
        return [
            CleanupItem(
                name: "Xcode DerivedData",
                detail: "Build intermediates from every Xcode/SwiftPM project. Safe — Xcode regenerates.",
                paths: ["\(home)/Library/Developer/Xcode/DerivedData"]
            ),
            CleanupItem(
                name: "Xcode Archives",
                detail: "Shipped/released app archives. Delete only if you don't need to re-symbolicate crash logs.",
                paths: ["\(home)/Library/Developer/Xcode/Archives"],
                dangerous: true
            ),
            CleanupItem(
                name: "Xcode iOS DeviceSupport",
                detail: "Per-iOS-version symbols. Re-downloaded on next device connect. Often many GB.",
                paths: ["\(home)/Library/Developer/Xcode/iOS DeviceSupport"]
            ),
            CleanupItem(
                name: "Xcode watchOS DeviceSupport",
                detail: "Per-watchOS-version symbols.",
                paths: ["\(home)/Library/Developer/Xcode/watchOS DeviceSupport"]
            ),
            CleanupItem(
                name: "Xcode tvOS DeviceSupport",
                detail: "Per-tvOS-version symbols.",
                paths: ["\(home)/Library/Developer/Xcode/tvOS DeviceSupport"]
            ),
            CleanupItem(
                name: "Xcode visionOS DeviceSupport",
                detail: "Per-visionOS-version symbols.",
                paths: ["\(home)/Library/Developer/Xcode/visionOS DeviceSupport"]
            ),
            CleanupItem(
                name: "CoreSimulator Caches",
                detail: "Shared simulator state caches.",
                paths: ["\(home)/Library/Developer/CoreSimulator/Caches"]
            ),
            CleanupItem(
                name: "CoreSimulator Logs",
                detail: "Per-device simulator logs.",
                paths: ["\(home)/Library/Logs/CoreSimulator"]
            ),
            CleanupItem(
                name: "CocoaPods cache",
                detail: "Cached pods, re-downloaded as needed.",
                paths: ["\(home)/Library/Caches/CocoaPods"]
            ),
            CleanupItem(
                name: "Carthage build cache",
                detail: "Per-project Carthage build outputs.",
                paths: ["\(home)/Library/Caches/org.carthage.CarthageKit"]
            ),
            CleanupItem(
                name: "Yarn Berry cache",
                detail: "Yarn 2+ global cache.",
                paths: ["\(home)/.yarn/berry/cache"]
            ),
            CleanupItem(
                name: "pnpm store",
                detail: "Global pnpm content-addressed store. Re-fetched lazily.",
                paths: ["\(home)/Library/pnpm/store", "\(home)/.local/share/pnpm/store"]
            ),
            CleanupItem(
                name: ".DS_Store files (home tree)",
                detail: "Recursively delete .DS_Store files under your home directory.",
                paths: [home],
                customCommand: "/usr/bin/find \(shellEscape(home)) -name .DS_Store -type f -print -delete 2>/dev/null",
                customSizeCommand: "/usr/bin/find \(shellEscape(home)) -name .DS_Store -type f -print0 2>/dev/null | /usr/bin/xargs -0 /usr/bin/stat -f %z 2>/dev/null | /usr/bin/awk '{s+=$1} END {print s+0}'"
            ),
            CleanupItem(
                name: "Diagnostic / Crash reports",
                detail: "User crash logs (~/Library/Logs/DiagnosticReports).",
                paths: ["\(home)/Library/Logs/DiagnosticReports"]
            ),
            CleanupItem(
                name: "Mail Downloads",
                detail: "Apple Mail attachment cache.",
                paths: ["\(home)/Library/Containers/com.apple.mail/Data/Library/Mail Downloads"]
            ),
            CleanupItem(
                name: "Quick Look cache",
                detail: "Resets QuickLook thumbnail and plugin cache.",
                paths: [],
                customCommand: "/usr/bin/qlmanage -r cache 2>&1 | tail -5"
            ),
            CleanupItem(
                name: "iOS Device Backups",
                detail: "iTunes/Finder iOS backups. POTENTIAL DATA LOSS — verify you have iCloud backup or don't need them.",
                paths: ["\(home)/Library/Application Support/MobileSync/Backup"],
                dangerous: true
            ),
            CleanupItem(
                name: "Empty Trash",
                detail: "Permanently delete contents of all user Trash folders.",
                paths: [],
                customCommand: "/bin/rm -rf \(shellEscape(NSHomeDirectory()))/.Trash/* \(shellEscape(NSHomeDirectory()))/.Trash/.[!.]* 2>/dev/null; echo Trash emptied"
            ),
            CleanupItem(
                name: "System Updates download",
                detail: "macOS update installer cache (/Library/Updates). Requires admin.",
                paths: ["/Library/Updates"],
                requiresAdmin: true
            ),
            CleanupItem(
                name: "Time Machine local snapshots",
                detail: "Local APFS snapshots Time Machine takes between backups. Requires admin.",
                paths: [],
                requiresAdmin: true,
                customCommand: """
                /usr/bin/tmutil listlocalsnapshotdates / 2>/dev/null | /usr/bin/awk 'NR>1 {print $1}' | while read d; do
                  if [ -n "$d" ]; then /usr/bin/tmutil deletelocalsnapshots "$d" 2>&1; fi
                done
                """
            ),
            CleanupItem(
                name: "Purge inactive memory",
                detail: "Force kernel to free inactive RAM pages. Requires admin.",
                paths: [],
                requiresAdmin: true,
                customCommand: "/usr/sbin/purge && echo Memory purged"
            ),
            CleanupItem(
                name: "Font registry cache",
                detail: "Rebuild font registry (atsutil). Logs you out of font sessions. Requires admin.",
                paths: [],
                requiresAdmin: true,
                customCommand: "/System/Library/Frameworks/ApplicationServices.framework/Versions/A/Frameworks/ATS.framework/Support/atsutil databases -remove 2>&1; echo Font caches reset"
            ),
            CleanupItem(
                name: "Docker prune (if installed)",
                detail: "Remove dangling Docker images, stopped containers, unused networks/volumes.",
                paths: [],
                customCommand: "command -v docker >/dev/null && docker system prune -a -f --volumes 2>&1 || echo 'docker not installed'"
            ),
            CleanupItem(
                name: "Homebrew autoremove + cleanup",
                detail: "Remove unused dependencies and old downloaded formula bottles.",
                paths: [],
                customCommand: "/opt/homebrew/bin/brew autoremove 2>&1; /opt/homebrew/bin/brew cleanup -s --prune=all 2>&1"
            ),
        ]
    }

    /// Compute size in bytes for paths (best effort).
    static func computeSize(for item: CleanupItem) -> Int64 {
        if let cmd = item.customSizeCommand {
            let r = ShellRunner.run(executable: "/bin/bash", arguments: ["-lc", cmd])
            let s = r.output.trimmingCharacters(in: .whitespacesAndNewlines)
            return Int64(s) ?? 0
        }
        guard !item.paths.isEmpty else { return 0 }
        var total: Int64 = 0
        for p in item.paths {
            guard FileManager.default.fileExists(atPath: p) else { continue }
            let r = ShellRunner.run(executable: "/usr/bin/du", arguments: ["-sk", p])
            if let firstField = r.output.split(separator: "\t", maxSplits: 1).first,
               let kb = Int64(firstField.trimmingCharacters(in: .whitespaces)) {
                total += kb * 1024
            }
        }
        return total
    }

    /// Apply selected items. Bundles all admin items into one osascript prompt; runs user items inline.
    static func apply(_ items: [CleanupItem]) -> String {
        var log = ""

        let userItems = items.filter { !$0.requiresAdmin }
        for item in userItems {
            log += "▶ \(item.name)\n"
            if let cmd = item.customCommand {
                let r = ShellRunner.run(executable: "/bin/bash", arguments: ["-lc", cmd])
                log += r.output + "\n[exit \(r.exit)]\n\n"
            } else {
                for path in item.paths where FileManager.default.fileExists(atPath: path) {
                    let r = ShellRunner.run(executable: "/bin/rm", arguments: ["-rf", path])
                    log += "rm -rf \(path) → exit \(r.exit)\n"
                    if !r.output.isEmpty { log += r.output + "\n" }
                }
            }
        }

        let adminItems = items.filter { $0.requiresAdmin }
        if !adminItems.isEmpty {
            var script = "set +e\n"
            for item in adminItems {
                script += "echo '▶ \(item.name)'\n"
                if let cmd = item.customCommand {
                    script += cmd + "\n"
                } else {
                    for path in item.paths {
                        script += "if [ -e \(shellEscape(path)) ]; then /bin/rm -rf \(shellEscape(path)) && echo 'removed \(path)'; fi\n"
                    }
                }
                script += "echo\n"
            }
            let r = ShellRunner.runWithAdmin(shell: "/bin/bash -c \(shellEscape(script))")
            log += "\n=== Admin batch ===\n\(r.output)\n[exit \(r.exit)]\n"
        }

        return log
    }

    private static func shellEscape(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
