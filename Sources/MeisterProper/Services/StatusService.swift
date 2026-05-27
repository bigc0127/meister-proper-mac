import Foundation
import Darwin

/// Native system metrics via sysctl + Mach host_statistics.
enum StatusService {
    static func fetch() async -> StatusSnapshot {
        await Task.detached(priority: .userInitiated) {
            collect()
        }.value
    }

    private static func collect() -> StatusSnapshot {
        var s = StatusSnapshot()
        s.host       = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
        s.modelName  = sysctlString("hw.model") ?? "Mac"
        s.cpuModel   = sysctlString("machdep.cpu.brand_string") ?? "Apple Silicon"
        s.osVersion  = "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"
        s.platform   = "darwin \(unameRelease())"
        s.processes  = sysctlIntArray("kern.proc.all").count / 648 // rough; we'll use a better approach below
        s.processes  = countProcesses()
        s.uptime     = humanUptime()

        // Memory: host_statistics64
        let mem = memoryStats()
        s.memUsedGB  = Double(mem.used)  / 1_073_741_824
        s.memTotalGB = Double(mem.total) / 1_073_741_824

        // Disk
        let disk = diskStats(mount: "/")
        s.diskSize = byteString(disk.total)
        s.diskUsed = byteString(disk.total - disk.free)
        s.diskFree = byteString(disk.free)
        s.totalRAM = byteString(mem.total)

        // CPU usage: two samples 200ms apart
        let cpu = cpuUsageSampled()
        s.cpuUsage = cpu

        // Health score: simple weighted heuristic with per-factor breakdown
        let memFrac  = mem.total > 0 ? Double(mem.used) / Double(mem.total) : 0
        let diskFrac = disk.total > 0 ? Double(disk.total - disk.free) / Double(disk.total) : 0
        let cpuFrac  = cpu / 100

        let memPen   = Int(max(0, memFrac  - 0.5) * 100)
        let diskPen  = Int(max(0, diskFrac - 0.7) * 200)
        let cpuPen   = Int(max(0, cpuFrac  - 0.6) *  60)

        // Uptime > 14 days: small penalty (cached state, RAM compression piles up)
        let uptimeDays = (Int(Date().timeIntervalSince1970) - bootEpoch()) / 86400
        let uptimePen = uptimeDays > 14 ? min(15, (uptimeDays - 14)) : 0

        var score = 100 - memPen - diskPen - cpuPen - uptimePen
        s.healthScore = max(0, min(100, score))
        s.healthMessage = healthMessage(score: s.healthScore, memFrac: memFrac, diskFrac: diskFrac)

        s.healthFactors = [
            HealthFactor(
                name: "Memory pressure",
                currentText: String(format: "%.1f%% used (%.1f / %.1f GB)", memFrac * 100, s.memUsedGB, s.memTotalGB),
                thresholdText: "Penalty starts at 50% used",
                penalty: memPen,
                severity: severity(memFrac, warn: 0.7, crit: 0.85),
                advice: memFrac > 0.85
                    ? "Quit RAM-hungry apps, then run Optimize → Purge inactive memory"
                    : "Close unused tabs/apps, especially Chromium-based browsers"
            ),
            HealthFactor(
                name: "Disk usage",
                currentText: "\(s.diskUsed) used of \(s.diskSize) (\(String(format: "%.1f%%", diskFrac * 100)))",
                thresholdText: "Penalty starts at 70% used",
                penalty: diskPen,
                severity: severity(diskFrac, warn: 0.8, crit: 0.9),
                advice: diskFrac > 0.85
                    ? "Run Clean (largest items), Project Purge, Installers, App Leftovers"
                    : "Run Clean to reclaim app caches"
            ),
            HealthFactor(
                name: "CPU usage",
                currentText: String(format: "%.0f%% recent", cpuFrac * 100),
                thresholdText: "Penalty starts at 60% busy",
                penalty: cpuPen,
                severity: severity(cpuFrac, warn: 0.7, crit: 0.9),
                advice: cpuFrac > 0.8
                    ? "Check Activity Monitor — a process may be stuck or runaway"
                    : "Background indexing/sync is normal; revisit if it persists"
            ),
            HealthFactor(
                name: "Uptime",
                currentText: "\(uptimeDays) day\(uptimeDays == 1 ? "" : "s") since reboot",
                thresholdText: "Penalty starts at 14 days",
                penalty: uptimePen,
                severity: uptimeDays > 21 ? .warn : .ok,
                advice: uptimeDays > 14
                    ? "Consider rebooting — long uptimes accumulate cached state and memory fragmentation"
                    : "Recent reboot — looking good"
            ),
        ]
        return s
    }

    private static func severity(_ frac: Double, warn: Double, crit: Double) -> HealthFactor.Severity {
        if frac >= crit { return .critical }
        if frac >= warn { return .warn }
        return .ok
    }

    private static func bootEpoch() -> Int {
        var bootTime = timeval()
        var size = MemoryLayout<timeval>.size
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        if sysctl(&mib, 2, &bootTime, &size, nil, 0) != 0 { return Int(Date().timeIntervalSince1970) }
        return bootTime.tv_sec
    }

    // ---------- helpers ----------

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        if sysctlbyname(name, nil, &size, nil, 0) != 0 { return nil }
        var buf = [CChar](repeating: 0, count: size)
        if sysctlbyname(name, &buf, &size, nil, 0) != 0 { return nil }
        return String(cString: buf)
    }

    private static func sysctlIntArray(_ name: String) -> [Int8] {
        var size = 0
        if sysctlbyname(name, nil, &size, nil, 0) != 0 { return [] }
        var buf = [Int8](repeating: 0, count: size)
        if sysctlbyname(name, &buf, &size, nil, 0) != 0 { return [] }
        return buf
    }

    private static func unameRelease() -> String {
        var u = utsname()
        uname(&u)
        let rel = withUnsafePointer(to: &u.release) {
            $0.withMemoryRebound(to: CChar.self, capacity: 256) { String(cString: $0) }
        }
        return rel
    }

    private static func countProcesses() -> Int {
        var size = 0
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        if sysctl(&mib, 4, nil, &size, nil, 0) != 0 { return 0 }
        return size / MemoryLayout<kinfo_proc>.stride
    }

    private static func humanUptime() -> String {
        var bootTime = timeval()
        var size = MemoryLayout<timeval>.size
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        if sysctl(&mib, 2, &bootTime, &size, nil, 0) != 0 { return "—" }
        let now = Date().timeIntervalSince1970
        let up  = now - Double(bootTime.tv_sec)
        let days  = Int(up) / 86400
        let hours = (Int(up) % 86400) / 3600
        let mins  = (Int(up) % 3600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(mins)m" }
        return "\(mins)m"
    }

    private static func memoryStats() -> (used: UInt64, total: UInt64) {
        let total = (sysctlString("hw.memsize")
            .flatMap { UInt64($0) }) ?? sysctlUInt64("hw.memsize") ?? 0

        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, total) }
        let used = (UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * UInt64(pageSize)
        return (used, total)
    }

    private static func sysctlUInt64(_ name: String) -> UInt64? {
        var v: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        if sysctlbyname(name, &v, &size, nil, 0) != 0 { return nil }
        return v
    }

    private static func diskStats(mount: String) -> (total: UInt64, free: UInt64) {
        var fs = statfs()
        guard statfs(mount, &fs) == 0 else { return (0, 0) }
        let total = UInt64(fs.f_blocks) * UInt64(fs.f_bsize)
        let free  = UInt64(fs.f_bavail) * UInt64(fs.f_bsize)
        return (total, free)
    }

    private static func cpuUsageSampled() -> Double {
        let s1 = cpuTotals()
        Thread.sleep(forTimeInterval: 0.2)
        let s2 = cpuTotals()
        let totalDelta = Double((s2.user + s2.sys + s2.idle + s2.nice) - (s1.user + s1.sys + s1.idle + s1.nice))
        let busyDelta  = Double((s2.user + s2.sys + s2.nice) - (s1.user + s1.sys + s1.nice))
        if totalDelta <= 0 { return 0 }
        return min(100, max(0, busyDelta / totalDelta * 100))
    }

    private static func cpuTotals() -> (user: UInt64, sys: UInt64, idle: UInt64, nice: UInt64) {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let r = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard r == KERN_SUCCESS else { return (0, 0, 0, 0) }
        return (
            UInt64(info.cpu_ticks.0),  // user
            UInt64(info.cpu_ticks.1),  // sys
            UInt64(info.cpu_ticks.2),  // idle
            UInt64(info.cpu_ticks.3)   // nice
        )
    }

    private static func byteString(_ b: UInt64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: Int64(b))
    }

    private static func healthMessage(score: Int, memFrac: Double, diskFrac: Double) -> String {
        var notes: [String] = []
        if memFrac > 0.85 { notes.append("memory pressure high") }
        if diskFrac > 0.9 { notes.append("disk nearly full") }
        if notes.isEmpty {
            switch score {
            case 80...: return "Healthy"
            case 60..<80: return "OK"
            case 40..<60: return "Run cleanup"
            default: return "Action needed"
            }
        }
        return notes.joined(separator: ", ")
    }
}
