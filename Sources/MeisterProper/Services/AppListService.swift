import Foundation
import AppKit

enum AppListService {
    /// Discover apps in /Applications, /Applications/Utilities, ~/Applications,
    /// /opt/homebrew/Caskroom, /System/Applications. Reads each .app's Info.plist
    /// for bundle id and name, and computes size.
    static func scan() async -> [InstalledApp] {
        await Task.detached(priority: .userInitiated) {
            collect()
        }.value
    }

    /// Synchronous variant for callers already on a background thread.
    static func scanSync() -> [InstalledApp] {
        collect()
    }

    private static func collect() -> [InstalledApp] {
        let home = NSHomeDirectory()
        let dirs = [
            "/Applications",
            "/Applications/Utilities",
            "\(home)/Applications",
            "/System/Applications",
            "/System/Applications/Utilities",
        ]
        var found: [InstalledApp] = []
        for dir in dirs {
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir) else { continue }
            for n in names where n.hasSuffix(".app") {
                let path = (dir as NSString).appendingPathComponent(n)
                if let app = inspect(path: path, source: dir.hasPrefix("/System") ? "System" : "App") {
                    found.append(app)
                }
            }
        }

        // Walk Homebrew Caskroom too — but those are linked into /Applications, so we
        // mark apps as Homebrew if `brew list --cask` reports them.
        let cask = ShellRunner.run(executable: "/opt/homebrew/bin/brew", arguments: ["list", "--cask", "-1"])
        if cask.exit == 0 {
            let caskNames = Set(cask.output.split(separator: "\n").map { String($0) })
            for i in found.indices {
                let bid = found[i].bundleId.lowercased()
                let nm  = found[i].name.lowercased().replacingOccurrences(of: " ", with: "-")
                if caskNames.contains(where: { bid.contains($0.lowercased()) || nm == $0 }) {
                    found[i] = InstalledApp(
                        name: found[i].name,
                        bundleId: found[i].bundleId,
                        source: "Homebrew",
                        uninstallName: found[i].uninstallName,
                        path: found[i].path,
                        size: found[i].size
                    )
                }
            }
        }

        return found.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func inspect(path: String, source: String) -> InstalledApp? {
        let plistPath = (path as NSString).appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: plistPath)),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        let name  = (plist["CFBundleDisplayName"] as? String) ?? (plist["CFBundleName"] as? String) ?? (path as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")
        let bid   = (plist["CFBundleIdentifier"] as? String) ?? ""
        let size  = byteString(of: path)
        return InstalledApp(
            name: name,
            bundleId: bid,
            source: source,
            uninstallName: name,
            path: path,
            size: size
        )
    }

    private static func byteString(of path: String) -> String {
        let r = ShellRunner.run(executable: "/usr/bin/du", arguments: ["-sk", path])
        guard let first = r.output.split(separator: "\t", maxSplits: 1).first,
              let kb = Int64(first.trimmingCharacters(in: .whitespaces))
        else { return "—" }
        let f = ByteCountFormatter(); f.countStyle = .file
        return f.string(fromByteCount: kb * 1024)
    }
}
