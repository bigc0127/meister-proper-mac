import Foundation

enum LaunchAgentsService {
    static func loadAll() -> [LaunchAgent] {
        var out: [LaunchAgent] = []
        for scope in LaunchAgent.Scope.allCases {
            out.append(contentsOf: load(scope: scope))
        }
        return out.sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }

    static func load(scope: LaunchAgent.Scope) -> [LaunchAgent] {
        let dir = scope.directory
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return [] }
        return names
            .filter { $0.hasSuffix(".plist") && !$0.hasPrefix(".") }
            .compactMap { name -> LaunchAgent? in
                let path = (dir as NSString).appendingPathComponent(name)
                let (label, program) = parsePlist(at: path)
                return LaunchAgent(
                    path: path,
                    label: label.isEmpty ? (name as NSString).deletingPathExtension : label,
                    program: program,
                    scope: scope
                )
            }
    }

    /// Light plist parse: extract Label and Program/ProgramArguments[0].
    static func parsePlist(at path: String) -> (label: String, program: String) {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return ("", "") }
        let label = plist["Label"] as? String ?? ""
        var program = plist["Program"] as? String ?? ""
        if program.isEmpty, let args = plist["ProgramArguments"] as? [String], let first = args.first { program = first }
        return (label, program)
    }

    /// Unload + delete chosen agents. User scope: no admin. System scope: bundled into a single sudo prompt.
    /// Returns combined log.
    static func remove(_ agents: [LaunchAgent]) -> String {
        var log = ""

        // User-scope ops, no admin.
        let userAgents = agents.filter { $0.scope == .userAgent }
        for agent in userAgents {
            log += unloadAndDelete(agent: agent, sudo: false)
        }

        // System ops batched into one admin prompt.
        let sysAgents = agents.filter { $0.scope != .userAgent }
        if !sysAgents.isEmpty {
            var script = "set -e\n"
            for a in sysAgents {
                let escaped = shellEscape(a.path)
                let label   = shellEscape(a.label)
                if a.scope == .systemDaemon {
                    script += "/bin/launchctl bootout system/\(label) 2>/dev/null || true\n"
                    script += "/bin/launchctl unload \(escaped) 2>/dev/null || true\n"
                } else {
                    script += "/bin/launchctl bootout gui/$(id -u) \(escaped) 2>/dev/null || true\n"
                    script += "/bin/launchctl unload \(escaped) 2>/dev/null || true\n"
                }
                script += "/bin/rm -f \(escaped)\n"
                script += "echo Removed: \(escaped)\n"
            }
            let r = ShellRunner.runWithAdmin(shell: "/bin/bash -c \(shellEscape(script))")
            log += r.output
            if r.exit != 0 { log += "\n[admin script exit \(r.exit)]\n" }
        }

        return log
    }

    private static func unloadAndDelete(agent: LaunchAgent, sudo: Bool) -> String {
        var log = ""
        let unload = ShellRunner.run(executable: "/bin/launchctl", arguments: ["bootout", "gui/\(getuid())", agent.path])
        log += "launchctl bootout: \(unload.output.isEmpty ? "(ok)" : unload.output)"
        let unload2 = ShellRunner.run(executable: "/bin/launchctl", arguments: ["unload", agent.path])
        log += unload2.output
        do {
            try FileManager.default.removeItem(atPath: agent.path)
            log += "Removed: \(agent.path)\n"
        } catch {
            log += "Failed to remove \(agent.path): \(error.localizedDescription)\n"
        }
        return log
    }

    private static func shellEscape(_ s: String) -> String {
        return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
