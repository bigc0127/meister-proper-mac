import Foundation

struct InstalledApp: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let bundleId: String
    let source: String        // "App" / "Homebrew"
    let uninstallName: String // display label for uninstall confirmations
    let path: String
    let size: String
    var selected: Bool = false
}

struct LaunchAgent: Identifiable, Hashable {
    let id = UUID()
    let path: String
    let label: String
    let program: String
    let scope: Scope
    var selected: Bool = false

    enum Scope: String, CaseIterable {
        case userAgent     = "User LaunchAgent"
        case systemAgent   = "System LaunchAgent"
        case systemDaemon  = "System LaunchDaemon"
        var directory: String {
            switch self {
            case .userAgent:    return NSString("~/Library/LaunchAgents").expandingTildeInPath
            case .systemAgent:  return "/Library/LaunchAgents"
            case .systemDaemon: return "/Library/LaunchDaemons"
            }
        }
        var requiresAdmin: Bool {
            self != .userAgent
        }
    }
}

struct CleanupItem: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let detail: String
    let paths: [String]
    var size: Int64? = nil
    var selected: Bool = false
    var requiresAdmin: Bool = false
    var dangerous: Bool = false   // shows extra warning
    var customCommand: String? = nil // if non-nil, run this instead of rm -rf
    var customSizeCommand: String? = nil // if non-nil, run for size (bytes) instead of `du` on paths
}

struct StatusSnapshot {
    var host: String = "—"
    var platform: String = "—"
    var uptime: String = "—"
    var processes: Int = 0
    var modelName: String = "—"
    var cpuModel: String = "—"
    var totalRAM: String = "—"
    var diskSize: String = "—"
    var osVersion: String = "—"
    var healthScore: Int = 0
    var healthMessage: String = "—"
    var cpuUsage: Double = 0
    var memUsedGB: Double = 0
    var memTotalGB: Double = 0
    var diskFree: String = "—"
    var diskUsed: String = "—"
    var healthFactors: [HealthFactor] = []
}

struct HealthFactor: Identifiable, Hashable {
    let id = UUID()
    let name: String          // "Memory pressure"
    let currentText: String   // "82.5% used (13.2 / 16.0 GB)"
    let thresholdText: String // "Penalty starts at 50%"
    let penalty: Int          // points deducted
    let severity: Severity
    let advice: String        // hint for what to do

    enum Severity { case ok, warn, critical }
}
