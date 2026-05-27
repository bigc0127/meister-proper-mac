import Foundation

struct OptimizeTask: Identifiable, Hashable {
    let id = UUID()
    let category: String
    let label: String
    let detail: String
    let command: String
    let requiresAdmin: Bool
    var selected: Bool = false
}

enum OptimizeService {
    static func tasks() -> [OptimizeTask] {
        [
            OptimizeTask(category: "DNS / network",
                label: "Flush DNS cache",
                detail: "dscacheutil -flushcache + killall -HUP mDNSResponder.",
                command: "/usr/bin/dscacheutil -flushcache; /usr/bin/killall -HUP mDNSResponder; echo DNS flushed",
                requiresAdmin: true),
            OptimizeTask(category: "DNS / network",
                label: "Flush ARP + route cache",
                detail: "route -n flush + arp -a -d.",
                command: "/sbin/route -n flush 2>&1 | head -5; /usr/sbin/arp -a -d 2>&1 | head -5; echo done",
                requiresAdmin: true),
            OptimizeTask(category: "Caches",
                label: "Reset Quick Look cache",
                detail: "qlmanage -r cache + delete thumbnail cache.",
                command: "/usr/bin/qlmanage -r cache 2>&1 | tail -3; /bin/rm -rf '\(NSHomeDirectory())/Library/Caches/com.apple.QuickLook.thumbnailcache' 2>/dev/null; echo done",
                requiresAdmin: false),
            OptimizeTask(category: "Caches",
                label: "Rebuild icon cache",
                detail: "Removes ~/Library/Caches/com.apple.iconservices*; restarts Dock.",
                command: "/bin/rm -rf '\(NSHomeDirectory())/Library/Caches/com.apple.iconservices*' 2>/dev/null; /usr/bin/killall Dock 2>&1; echo done",
                requiresAdmin: false),
            OptimizeTask(category: "Caches",
                label: "Rebuild LaunchServices DB",
                detail: "Resets Open With / file associations. Sudo.",
                command: "/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -kill -r -domain local -domain user -domain system 2>&1 | tail -5; /usr/bin/killall Dock 2>&1; echo done",
                requiresAdmin: true),
            OptimizeTask(category: "Caches",
                label: "Rebuild font registry",
                detail: "atsutil databases -remove. Close browsers first.",
                command: "/System/Library/Frameworks/ApplicationServices.framework/Versions/A/Frameworks/ATS.framework/Support/atsutil databases -remove 2>&1; echo done",
                requiresAdmin: true),
            OptimizeTask(category: "Memory",
                label: "Purge inactive memory",
                detail: "/usr/sbin/purge — frees inactive RAM.",
                command: "/usr/sbin/purge && echo Memory purged",
                requiresAdmin: true),
            OptimizeTask(category: "Storage",
                label: "Delete Time Machine local snapshots",
                detail: "tmutil deletelocalsnapshots for every listed date.",
                command: """
                /usr/bin/tmutil listlocalsnapshotdates / 2>/dev/null | /usr/bin/awk 'NR>1 {print $1}' | while read d; do
                  [ -n "$d" ] && /usr/bin/tmutil deletelocalsnapshots "$d" 2>&1
                done; echo done
                """,
                requiresAdmin: true),
            OptimizeTask(category: "Storage",
                label: "Run periodic scripts",
                detail: "Runs daily/weekly/monthly housekeeping (log rotation, etc).",
                command: "/usr/sbin/periodic daily weekly monthly 2>&1 | tail -10; echo done",
                requiresAdmin: true),
            OptimizeTask(category: "Spotlight",
                label: "Verify Spotlight index status",
                detail: "mdutil -s / — reports enabled/disabled.",
                command: "/usr/bin/mdutil -s / 2>&1",
                requiresAdmin: false),
            OptimizeTask(category: "Spotlight",
                label: "Rebuild Spotlight index",
                detail: "mdutil -E /. Re-indexing takes 1-2 hours in the background.",
                command: "/usr/bin/mdutil -E / 2>&1",
                requiresAdmin: true),
            OptimizeTask(category: "Privacy",
                label: "Clear quarantine events",
                detail: "Empty downloaded-from history (not actual files).",
                command: "/usr/bin/sqlite3 '\(NSHomeDirectory())/Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2' 'DELETE FROM LSQuarantineEvent; VACUUM;' 2>&1; echo done",
                requiresAdmin: false),
            OptimizeTask(category: "Privacy",
                label: "Disable .DS_Store on network/USB",
                detail: "defaults write — prevents .DS_Store on remote/USB volumes.",
                command: "/usr/bin/defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true; /usr/bin/defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true; echo done",
                requiresAdmin: false),
            OptimizeTask(category: "Bluetooth",
                label: "Restart bluetoothd",
                detail: "Soft-kills bluetoothd; auto-relaunches. Close audio apps first.",
                command: "/usr/bin/pkill -TERM bluetoothd 2>&1; echo done",
                requiresAdmin: true),
        ]
    }

    static func run(_ tasks: [OptimizeTask], onProgress: @Sendable @escaping (String) async -> Void) async {
        let user  = tasks.filter { !$0.requiresAdmin }
        let admin = tasks.filter { $0.requiresAdmin }

        for t in user {
            await onProgress("▶ \(t.label)")
            let r = ShellRunner.run(executable: "/bin/bash", arguments: ["-lc", t.command])
            let lines = r.output.split(separator: "\n").prefix(8)
            for l in lines { await onProgress(String(l)) }
            await onProgress("[exit \(r.exit)]")
        }

        if !admin.isEmpty {
            await onProgress("=== Admin batch (\(admin.count) tasks) ===")
            var script = "set +e\n"
            for t in admin {
                script += "echo '▶ \(t.label.replacingOccurrences(of: "'", with: ""))'\n"
                script += t.command + "\n"
                script += "echo\n"
            }
            let tmp = (NSTemporaryDirectory() as NSString).appendingPathComponent("mp-opt-\(UUID().uuidString).sh")
            try? script.write(toFile: tmp, atomically: true, encoding: .utf8)
            _ = ShellRunner.run(executable: "/bin/chmod", arguments: ["+x", tmp])
            let r = ShellRunner.run(executable: "/usr/bin/osascript",
                                    arguments: ["-e", "do shell script \"/bin/bash \(tmp)\" with administrator privileges"])
            try? FileManager.default.removeItem(atPath: tmp)
            let parts = r.output.split(omittingEmptySubsequences: false) { $0 == "\n" || $0 == "\r" }
            for p in parts where !p.isEmpty { await onProgress(String(p)) }
            await onProgress("[admin exit \(r.exit)]")
        }
    }
}
