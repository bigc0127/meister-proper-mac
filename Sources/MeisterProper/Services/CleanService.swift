import Foundation

enum CleanService {
    /// Compute size of all paths for a target. Skips missing paths.
    static func computeSize(for target: CleanTarget) -> Int64 {
        guard !target.paths.isEmpty else { return 0 }
        var total: Int64 = 0
        for p in target.paths where FileManager.default.fileExists(atPath: p) {
            let r = ShellRunner.run(executable: "/usr/bin/du", arguments: ["-sk", p])
            if let first = r.output.split(separator: "\t", maxSplits: 1).first,
               let kb = Int64(first.trimmingCharacters(in: .whitespaces)) {
                total += kb * 1024
            }
        }
        return total
    }

    /// Apply a list of selected targets. User-scope items run inline; admin-scope items
    /// are batched into a single osascript admin invocation.
    /// Calls `onProgress` with one log line per significant step (already on the calling actor).
    static func apply(_ targets: [CleanTarget], dryRun: Bool, onProgress: @Sendable @escaping (String) async -> Void) async {
        let user  = targets.filter { !$0.effectiveAdmin }
        let admin = targets.filter { $0.effectiveAdmin }

        for t in user {
            await onProgress("▶ \(t.label)")
            if dryRun {
                if let cmd = t.command { await onProgress("[dry-run] would run: \(cmd)") }
                for p in t.paths { await onProgress("[dry-run] would rm -rf \(p)") }
                continue
            }
            if let cmd = t.command {
                let r = ShellRunner.run(executable: "/bin/bash", arguments: ["-lc", cmd])
                let trimmed = r.output.split(separator: "\n").prefix(12).joined(separator: "\n")
                if !trimmed.isEmpty { await onProgress(String(trimmed)) }
                if r.exit != 0 { await onProgress("⚠ exit \(r.exit) — may indicate macOS TCC blocked the operation") }
                else { await onProgress("[exit 0]") }
            } else {
                for p in t.paths where FileManager.default.fileExists(atPath: p) {
                    // Try FileManager.trashItem first — broader perms via NSFileCoordinator.
                    do {
                        try FileManager.default.trashItem(at: URL(fileURLWithPath: p), resultingItemURL: nil)
                        await onProgress("→ trashed \(p)")
                        continue
                    } catch {
                        // Fall through to rm -rf.
                    }
                    let r = ShellRunner.run(executable: "/bin/rm", arguments: ["-rf", p])
                    if r.exit == 0 {
                        await onProgress("rm -rf \(p) → 0")
                    } else {
                        await onProgress("⚠ rm -rf \(p) → \(r.exit) (TCC may be blocking — try toggling admin)")
                    }
                }
            }
        }

        if !admin.isEmpty {
            await onProgress("=== Admin batch (\(admin.count) tasks) ===")
            if dryRun {
                for t in admin {
                    await onProgress("[dry-run] (admin) \(t.label)")
                    if let cmd = t.command { await onProgress("  cmd: \(cmd)") }
                    for p in t.paths { await onProgress("  rm -rf \(p)") }
                }
                return
            }
            var script = "set +e\n"
            for t in admin {
                script += "echo '▶ \(t.label.replacingOccurrences(of: "'", with: ""))'\n"
                if let cmd = t.command {
                    script += cmd + "\n"
                } else {
                    for p in t.paths {
                        script += "if [ -e '\(p)' ]; then /bin/rm -rf '\(p)' && echo 'removed \(p)'; fi\n"
                    }
                }
                script += "echo\n"
            }
            // Use a temp script file to dodge AppleScript escaping pain.
            let tmp = (NSTemporaryDirectory() as NSString).appendingPathComponent("mp-clean-\(UUID().uuidString).sh")
            try? script.write(toFile: tmp, atomically: true, encoding: .utf8)
            _ = ShellRunner.run(executable: "/bin/chmod", arguments: ["+x", tmp])
            let appleScript = "do shell script \"/bin/bash \(tmp)\" with administrator privileges"
            let r = ShellRunner.run(executable: "/usr/bin/osascript", arguments: ["-e", appleScript])
            try? FileManager.default.removeItem(atPath: tmp)
            // osascript returns lines with \r — split on either.
            let parts = r.output.split(omittingEmptySubsequences: false) { $0 == "\n" || $0 == "\r" }
            for p in parts where !p.isEmpty { await onProgress(String(p)) }
            await onProgress("[admin exit \(r.exit)]")
        }
    }
}
